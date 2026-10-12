import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fylesync_frontend/security/gpg_service.dart';

void main() {
  test('GpgService full asymmetric hybrid encryption and decryption', () {
    final gpg = GpgService();
    final pair = gpg.getOrCreateKeyPair('admin');

    expect(pair.keyId.isNotEmpty, isTrue);
    expect(pair.fingerprint.startsWith('UPB-GPG-'), isTrue);

    final pubArmor = pair.exportPublicKeyArmor();
    expect(pubArmor.contains('BEGIN PGP PUBLIC KEY BLOCK'), isTrue);

    final privArmor = pair.exportPrivateKeyArmor();
    expect(privArmor.contains('BEGIN PGP PRIVATE KEY BLOCK'), isTrue);

    // Test with binary and text payload
    final originalText = 'Documento confidencial de la Universidad Pontificia Bolivariana - UPB 2026';
    final plainBytes = Uint8List.fromList(utf8.encode(originalText));

    // Asymmetric Zero-Knowledge encryption with Public Key
    final encrypted = gpg.encryptFileAsymmetric(plainBytes, pair.publicKey);
    expect(gpg.isGpgEncrypted(encrypted), isTrue);
    expect(encrypted, isNot(equals(plainBytes)));

    // Asymmetric decryption with Private Key
    final decrypted = gpg.decryptFileAsymmetric(encrypted, pair.privateKey);
    expect(utf8.decode(decrypted), equals(originalText));
  });
}
