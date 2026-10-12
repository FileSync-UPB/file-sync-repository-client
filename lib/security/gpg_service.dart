import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class GpgKeyPair {
  final RSAPublicKey publicKey;
  final RSAPrivateKey privateKey;
  final String keyId;
  final String fingerprint;

  GpgKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.keyId,
    required this.fingerprint,
  });

  String exportPublicKeyArmor() {
    final payload = {
      'modulus': publicKey.modulus.toString(),
      'exponent': publicKey.exponent.toString(),
      'keyId': keyId,
      'fingerprint': fingerprint,
    };
    final b64 = base64Encode(utf8.encode(jsonEncode(payload)));
    return '-----BEGIN PGP PUBLIC KEY BLOCK-----\n'
        'Version: UPB-FyleSync GPG v2.4 (RSA 2048-bit)\n'
        'Comment: Clave Asimetrica Publica de Respaldo Zero-Knowledge\n\n'
        '${_wrap64(b64)}\n'
        '-----END PGP PUBLIC KEY BLOCK-----';
  }

  String exportPrivateKeyArmor() {
    final payload = {
      'modulus': privateKey.modulus.toString(),
      'privateExponent': privateKey.privateExponent.toString(),
      'p': privateKey.p.toString(),
      'q': privateKey.q.toString(),
      'keyId': keyId,
      'fingerprint': fingerprint,
    };
    final b64 = base64Encode(utf8.encode(jsonEncode(payload)));
    return '-----BEGIN PGP PRIVATE KEY BLOCK-----\n'
        'Version: UPB-FyleSync GPG v2.4 (RSA 2048-bit)\n'
        'Comment: Clave Asimetrica Privada para Descifrado Local\n\n'
        '${_wrap64(b64)}\n'
        '-----END PGP PRIVATE KEY BLOCK-----';
  }

  static String _wrap64(String str) {
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i += 64) {
      buffer.writeln(str.substring(i, min(i + 64, str.length)));
    }
    return buffer.toString().trim();
  }
}

class GpgService {
  static final GpgService _instance = GpgService._internal();
  factory GpgService() => _instance;
  GpgService._internal();

  final Map<String, GpgKeyPair> _inMemoryKeys = {};

  GpgKeyPair getOrCreateKeyPair(String username) {
    if (_inMemoryKeys.containsKey(username)) {
      return _inMemoryKeys[username]!;
    }

    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seed = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seed)));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    final pub = pair.publicKey;
    final priv = pair.privateKey;

    final digest = SHA256Digest();
    final input = Uint8List.fromList(utf8.encode('$username:${pub.modulus}'));
    final hashBytes = digest.process(input);
    final sha = hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final keyId = sha.substring(0, 16).toUpperCase();
    final fingerprint = 'UPB-GPG-${sha.substring(0, 4)}-${sha.substring(4, 8)}-${sha.substring(8, 12)}-${sha.substring(12, 16)}'.toUpperCase();

    final gpgPair = GpgKeyPair(
      publicKey: pub,
      privateKey: priv,
      keyId: keyId,
      fingerprint: fingerprint,
    );

    _inMemoryKeys[username] = gpgPair;
    return gpgPair;
  }

  /// Cifrado Asimétrico Híbrido Zero-Knowledge estilo OpenPGP/GPG
  /// Cifra los datos del archivo localmente con AES-256 y envuelve la clave de sesión con RSA-2048 Public Key.
  Uint8List encryptFileAsymmetric(Uint8List fileBytes, RSAPublicKey recipientPublicKey) {
    final random = Random.secure();
    // 1. Clave de sesión AES de 256 bits (32 bytes) y Vector de Inicialización (16 bytes)
    final sessionKey = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
    final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));

    // 2. Cifrado simétrico AES-256-CBC del contenido del archivo
    final cbcCipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(sessionKey), iv));

    final paddedPlain = _padPkcs7(fileBytes, cbcCipher.blockSize);
    final encryptedContent = Uint8List(paddedPlain.length);
    var offset = 0;
    while (offset < paddedPlain.length) {
      offset += cbcCipher.processBlock(paddedPlain, offset, encryptedContent, offset);
    }

    // 3. Cifrado asimétrico RSA-PKCS1 de la clave de sesión
    final rsaEncryptor = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(recipientPublicKey));
    final encryptedSessionKey = rsaEncryptor.process(sessionKey);

    // 4. Empaquetar bloque PGP: [Magic 4B: 'GPG1'] [EncKeyLen 2B] [EncKey] [IV 16B] [EncryptedPayload]
    final encKeyLen = encryptedSessionKey.length;
    final byteData = ByteData(4 + 2 + encKeyLen + 16 + encryptedContent.length);

    // Magic: GPG1
    byteData.setUint8(0, 0x47); // G
    byteData.setUint8(1, 0x50); // P
    byteData.setUint8(2, 0x47); // G
    byteData.setUint8(3, 0x31); // 1

    byteData.setUint16(4, encKeyLen);

    var cur = 6;
    for (int i = 0; i < encKeyLen; i++) {
      byteData.setUint8(cur++, encryptedSessionKey[i]);
    }
    for (int i = 0; i < 16; i++) {
      byteData.setUint8(cur++, iv[i]);
    }
    for (int i = 0; i < encryptedContent.length; i++) {
      byteData.setUint8(cur++, encryptedContent[i]);
    }

    return byteData.buffer.asUint8List();
  }

  /// Descifrado Asimétrico Híbrido Zero-Knowledge en cliente
  Uint8List decryptFileAsymmetric(Uint8List encryptedPayload, RSAPrivateKey privateKey) {
    if (!isGpgEncrypted(encryptedPayload)) {
      // Si no está cifrado con GPG, devolver tal cual
      return encryptedPayload;
    }

    final byteData = ByteData.sublistView(encryptedPayload);
    final encKeyLen = byteData.getUint16(4);

    var cur = 6;
    final encryptedSessionKey = Uint8List(encKeyLen);
    for (int i = 0; i < encKeyLen; i++) {
      encryptedSessionKey[i] = byteData.getUint8(cur++);
    }

    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      iv[i] = byteData.getUint8(cur++);
    }

    final encryptedContent = Uint8List(encryptedPayload.length - cur);
    for (int i = 0; i < encryptedContent.length; i++) {
      encryptedContent[i] = byteData.getUint8(cur++);
    }

    // 1. Descifrar clave de sesión con RSA Private Key
    final rsaDecryptor = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final sessionKey = rsaDecryptor.process(encryptedSessionKey);

    // 2. Descifrar contenido con AES-256-CBC
    final cbcCipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(sessionKey), iv));

    final decryptedPadded = Uint8List(encryptedContent.length);
    var offset = 0;
    while (offset < encryptedContent.length) {
      offset += cbcCipher.processBlock(encryptedContent, offset, decryptedPadded, offset);
    }

    return _unpadPkcs7(decryptedPadded);
  }

  bool isGpgEncrypted(Uint8List bytes) {
    if (bytes.length < 24) return false;
    return bytes[0] == 0x47 && bytes[1] == 0x50 && bytes[2] == 0x47 && bytes[3] == 0x31;
  }

  Uint8List _padPkcs7(Uint8List data, int blockSize) {
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setRange(0, data.length, data);
    for (int i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  Uint8List _unpadPkcs7(Uint8List padded) {
    if (padded.isEmpty) return padded;
    final padLength = padded.last;
    if (padLength <= 0 || padLength > 16 || padLength > padded.length) {
      return padded;
    }
    return padded.sublist(0, padded.length - padLength);
  }
}
