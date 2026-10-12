import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../security/gpg_service.dart';
import '../../platform/platform_utils.dart';

class GpgScreen extends StatefulWidget {
  final String token;
  final String username;

  const GpgScreen({
    super.key,
    required this.token,
    required this.username,
  });

  @override
  State<GpgScreen> createState() => _GpgScreenState();
}

class _GpgScreenState extends State<GpgScreen> {
  final GpgService _gpg = GpgService();
  late GpgKeyPair _keyPair;

  bool _showPrivateKey = false;
  bool _isTestingCrypto = false;
  String? _testResult;

  // Decryption section state
  bool _isDecrypting = false;
  String? _decryptedFileName;
  Uint8List? _decryptedBytes;
  String? _decryptedText;
  bool _isImage = false;
  String? _decryptError;

  @override
  void initState() {
    super.initState();
    _keyPair = _gpg.getOrCreateKeyPair(widget.username);
  }

  void _runSelfTest() {
    setState(() {
      _isTestingCrypto = true;
      _testResult = null;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      final sw = Stopwatch()..start();
      try {
        final sample = 'FyleSync-UPB-ZeroKnowledge-GPG-Test-${DateTime.now().millisecondsSinceEpoch}';
        final sampleBytes = Uint8List.fromList(utf8.encode(sample));

        // Asymmetric Hybrid Encryption (RSA-2048 + AES-256)
        final enc = _gpg.encryptFileAsymmetric(sampleBytes, _keyPair.publicKey);

        // Asymmetric Decryption
        final dec = _gpg.decryptFileAsymmetric(enc, _keyPair.privateKey);
        final restored = utf8.decode(dec);

        sw.stop();
        if (restored == sample) {
          setState(() {
            _testResult = '✅ Autotest superado con éxito (${sw.elapsedMilliseconds} ms). Cifrado RSA 2048-bit + AES-256 verificado al 100%.';
            _isTestingCrypto = false;
          });
        } else {
          setState(() {
            _testResult = '❌ Error de coincidencia de contenido.';
            _isTestingCrypto = false;
          });
        }
      } catch (e) {
        setState(() {
          _testResult = '❌ Error en prueba criptográfica: $e';
          _isTestingCrypto = false;
        });
      }
    });
  }

  void _pickAndDecryptFile() {
    setState(() {
      _decryptError = null;
      _decryptedBytes = null;
      _decryptedText = null;
      _decryptedFileName = null;
      _isImage = false;
    });

    pickFileWeb(
      context: context,
      onFileSelected: (name, size, rawBytes) {
        try {
          final bytes = Uint8List.fromList(rawBytes);

          if (!_gpg.isGpgEncrypted(bytes)) {
            setState(() {
              _decryptError = 'El archivo "$name" no contiene la firma binaria de cifrado GPG1 de FyleSync.';
            });
            return;
          }

          setState(() => _isDecrypting = true);

          final decBytes = _gpg.decryptFileAsymmetric(bytes, _keyPair.privateKey);

          // Determinar nombre original quitando extensiones .gpg o .backup.gpg
          String cleanName = name;
          if (cleanName.endsWith('.backup.gpg')) {
            cleanName = cleanName.replaceAll('.backup.gpg', '');
          } else if (cleanName.endsWith('.gpg')) {
            cleanName = cleanName.substring(0, cleanName.length - 4);
          } else {
            cleanName = 'restaurado_$cleanName';
          }

          // Detectar si es imagen
          final isImg = cleanName.endsWith('.png') ||
              cleanName.endsWith('.jpg') ||
              cleanName.endsWith('.jpeg') ||
              cleanName.endsWith('.webp') ||
              cleanName.endsWith('.gif') ||
              (decBytes.length >= 4 && decBytes[0] == 0x89 && decBytes[1] == 0x50 && decBytes[2] == 0x4E && decBytes[3] == 0x47) ||
              (decBytes.length >= 3 && decBytes[0] == 0xFF && decBytes[1] == 0xD8 && decBytes[2] == 0xFF);

          String? textPreview;
          if (!isImg && decBytes.length < 500000) {
            try {
              textPreview = utf8.decode(decBytes);
            } catch (_) {
              textPreview = null;
            }
          }

          setState(() {
            _isDecrypting = false;
            _decryptedFileName = cleanName;
            _decryptedBytes = decBytes;
            _decryptedText = textPreview;
            _isImage = isImg;
            _decryptError = null;
          });
        } catch (e) {
          setState(() {
            _isDecrypting = false;
            _decryptError = 'Error al descifrar el archivo: $e';
          });
        }
      },
    );
  }

  void _saveDecryptedFile() async {
    if (_decryptedBytes == null || _decryptedFileName == null) return;
    try {
      await saveLocalFile('', _decryptedFileName!, _decryptedBytes!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archivo "$_decryptedFileName" guardado con éxito.'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar archivo: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6366F1)),
                  ),
                  child: const Icon(Icons.security, color: Color(0xFF818CF8), size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seguridad y Cifrado GPG Zero-Knowledge',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cifrado asimétrico en cliente (RSA 2048-bit + AES-256) para copias de seguridad de grado institucional',
                        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Card 1: Identidad Criptográfica del Usuario
            _buildIdentityCard(),
            const SizedBox(height: 24),

            // Card 2: Descifrador Interactivo de Archivos .gpg
            _buildDecryptorCard(),
            const SizedBox(height: 24),

            // Card 3: Autotest y Terminal CLI
            _buildTerminalInstructionsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.vpn_key_rounded, color: Color(0xFF818CF8), size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Identidad Criptográfica Institucional',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, size: 14, color: Colors.greenAccent),
                    SizedBox(width: 6),
                    Text('Zero-Knowledge Activo', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Key ID & Fingerprint
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('KEY ID:', style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      SelectableText(
                        _keyPair.keyId,
                        style: const TextStyle(color: Color(0xFF38BDF8), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FINGERPRINT INSTITUCIONAL:', style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      SelectableText(
                        _keyPair.fingerprint,
                        style: const TextStyle(color: Colors.amberAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Public Key Box
          Text('Clave Pública OpenPGP Armor (Para Cifrado en Origen):', style: TextStyle(color: Colors.grey[300], fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _keyPair.exportPublicKeyArmor(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF94A3B8)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _keyPair.exportPublicKeyArmor()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Clave pública copiada al portapapeles.'), backgroundColor: Colors.indigo),
                  );
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copiar Clave Pública', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF818CF8)),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _showPrivateKey = !_showPrivateKey);
                },
                icon: Icon(_showPrivateKey ? Icons.visibility_off : Icons.visibility, size: 14),
                label: Text(_showPrivateKey ? 'Ocultar Clave Privada' : 'Revelar Clave Privada', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.amber[400]),
              ),
            ],
          ),

          if (_showPrivateKey) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF451A03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                      SizedBox(width: 8),
                      Text('Clave Privada Local Zero-Knowledge', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 90,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _keyPair.exportPrivateKeyArmor(),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.amberAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _keyPair.exportPrivateKeyArmor()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Clave privada copiada al portapapeles.'), backgroundColor: Colors.orange),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copiar Clave Privada', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700], foregroundColor: Colors.black),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDecryptorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4F46E5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lock_open_rounded, color: Color(0xFF818CF8), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Descifrador Interactivo de Archivos (.gpg)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Restaura y previsualiza imágenes, documentos y backups protegidos con GPG',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Upload / Pick Button
          Center(
            child: ElevatedButton.icon(
              onPressed: _pickAndDecryptFile,
              icon: const Icon(Icons.folder_open_rounded, size: 20),
              label: const Text('Examinar y Descifrar Archivo .gpg'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

          if (_isDecrypting) ...[
            const SizedBox(height: 20),
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFF818CF8)),
                  SizedBox(height: 10),
                  Text('Descifrando asimétricamente con RSA 2048 y AES-256...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],

          if (_decryptError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[900]!.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_decryptError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          if (_decryptedBytes != null && _decryptedFileName != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _decryptedFileName!,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                'Restaurado con éxito (${(_decryptedBytes!.length / 1024).toStringAsFixed(1)} KB)',
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: _saveDecryptedFile,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Descargar Archivo'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Image Preview if applicable
                  if (_isImage) ...[
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 350, maxWidth: 500),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.memory(
                          _decryptedBytes!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ] else if (_decryptedText != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _decryptedText!,
                          style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.insert_drive_file, color: Color(0xFF818CF8)),
                          SizedBox(width: 8),
                          Text('Archivo binario listo para descargar y usar.', style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTerminalInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.terminal_rounded, color: Color(0xFF38BDF8), size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Verificación y Comandos por Consola',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isTestingCrypto ? null : _runSelfTest,
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Autotest Criptográfico', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.startsWith('✅') ? Colors.green[900]!.withOpacity(0.3) : Colors.red[900]!.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _testResult!.startsWith('✅') ? Colors.green : Colors.red),
              ),
              child: Text(_testResult!, style: TextStyle(color: _testResult!.startsWith('✅') ? Colors.greenAccent : Colors.redAccent, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Descifrado desde PowerShell en Windows:',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const SelectableText(
              '# Ejecutar script descifrador incluido en la raiz del proyecto:\n'
              'PS> .\\fylesync-decrypt.ps1 -FilePath "C:\\Users\\Usuario\\Downloads\\a.png.gpg"\n'
              '# El script restaura automaticamente el archivo original "a.png" en la misma carpeta.',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF38BDF8)),
            ),
          ),
        ],
      ),
    );
  }
}
