import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fylesync_frontend/security/gpg_service.dart';

void main() {
  test('Export admin key and create sample encrypted file', () {
    final gpg = GpgService();
    final pair = gpg.getOrCreateKeyPair('admin');

    // 1. Export key pair json
    final keyData = {
      'modulus': pair.privateKey.modulus.toString(),
      'exponent': pair.publicKey.exponent.toString(),
      'privateExponent': pair.privateKey.privateExponent.toString(),
      'p': pair.privateKey.p.toString(),
      'q': pair.privateKey.q.toString(),
      'keyId': pair.keyId,
      'fingerprint': pair.fingerprint,
    };
    File('admin_gpg_key.json').writeAsStringSync(jsonEncode(keyData));
    File('admin_private_key.asc').writeAsStringSync(pair.exportPrivateKeyArmor());
    File('admin_public_key.asc').writeAsStringSync(pair.exportPublicKeyArmor());

    // 2. Encrypt a test payload
    final samplePlain = utf8.encode('UPB-FyleSync-Enterprise-Prueba-2026');
    final encrypted = gpg.encryptFileAsymmetric(Uint8List.fromList(samplePlain), pair.publicKey);
    File('sample_test.txt.gpg').writeAsBytesSync(encrypted);

    print('KEY ID: ${pair.keyId}');
    print('FINGERPRINT: ${pair.fingerprint}');
  });
}
