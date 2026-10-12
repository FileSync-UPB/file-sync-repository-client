import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../platform/platform_utils.dart';
import '../../security/gpg_service.dart';

class SyncScreen extends StatefulWidget {
  final String token;
  final String username;

  const SyncScreen({
    super.key,
    required this.token,
    required this.username,
  });

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _errorMessage;

  List<dynamic> _devices = [];
  List<dynamic> _syncedFiles = [];
  List<dynamic> _history = [];

  // ID persistido localmente de este dispositivo
  String? _localDeviceId;

  // Red Privada Institucional (UPB)
  bool _isOnPrivateNetwork = true;
  bool _wasPreviouslyOffline = false;
  Timer? _networkMonitorTimer;

  // Cifrado Asimétrico GPG Zero-Knowledge
  bool _gpgEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadLocalDeviceIdAndFetch();
    _startNetworkMonitor();
  }

  @override
  void dispose() {
    _networkMonitorTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalDeviceIdAndFetch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _localDeviceId = prefs.getString('fylesync_local_device_id_${widget.username}');
    } catch (_) {}
    await _fetchSyncOverview();
  }

  Future<void> _saveLocalDeviceId(String? id) async {
    _localDeviceId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id != null) {
        await prefs.setString('fylesync_local_device_id_${widget.username}', id);
      } else {
        await prefs.remove('fylesync_local_device_id_${widget.username}');
      }
    } catch (_) {}
  }

  String _getCurrentPlatform() {
    if (kIsWeb) return 'Web';
    if (defaultTargetPlatform == TargetPlatform.android) return 'Android';
    if (defaultTargetPlatform == TargetPlatform.windows) return 'Windows';
    if (defaultTargetPlatform == TargetPlatform.linux) return 'Linux';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'iOS';
    if (defaultTargetPlatform == TargetPlatform.macOS) return 'macOS';
    return 'Windows';
  }

  void _startNetworkMonitor() {
    _networkMonitorTimer?.cancel();
    _networkMonitorTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkPrivateNetworkAndAutoSync();
    });
  }

  Future<void> _checkPrivateNetworkAndAutoSync() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.streamingUrl}/api/sync'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        if (!_isOnPrivateNetwork || _wasPreviouslyOffline) {
          if (mounted) {
            setState(() {
              _isOnPrivateNetwork = true;
              _wasPreviouslyOffline = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.wifi, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(child: Text('Conectado a la Red Privada UPB. Sincronización automática iniciada...')),
                  ],
                ),
                backgroundColor: Color(0xFF1E1B4B),
                duration: Duration(seconds: 3),
              ),
            );
          }
          final currentDev = _getCurrentDevice();
          if (currentDev != null && !_isSyncing) {
            _triggerSync(currentDev, isAuto: true);
          }
        } else {
          if (mounted && !_isOnPrivateNetwork) {
            setState(() => _isOnPrivateNetwork = true);
          }
        }
      } else {
        if (mounted && _isOnPrivateNetwork) {
          setState(() {
            _isOnPrivateNetwork = false;
            _wasPreviouslyOffline = true;
          });
        }
      }
    } catch (_) {
      if (mounted && _isOnPrivateNetwork) {
        setState(() {
          _isOnPrivateNetwork = false;
          _wasPreviouslyOffline = true;
        });
      }
    }
  }

  Future<void> _fetchSyncOverview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.streamingUrl}/api/sync'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _devices = data['devices'] ?? [];
            _syncedFiles = data['syncedFiles'] ?? [];
            _history = data['history'] ?? [];
            _isOnPrivateNetwork = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Servidor respondió con código ${response.statusCode}';
            _isOnPrivateNetwork = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudo conectar a la Red Privada de la UPB ($e)';
          _isOnPrivateNetwork = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, dynamic>? _getCurrentDevice() {
    // 1. Si tenemos un ID guardado en preferencias locales, buscarlo
    if (_localDeviceId != null) {
      final found = _devices.where((d) => d['id'] == _localDeviceId).toList();
      if (found.isNotEmpty) return found.first as Map<String, dynamic>;
    }

    // 2. Si no, verificar si existe EXACTAMENTE un dispositivo de nuestra misma plataforma
    final plat = _getCurrentPlatform();
    final matching = _devices.where((d) => d['platform'] == plat).toList();
    if (matching.length == 1) {
      final dev = matching.first as Map<String, dynamic>;
      _saveLocalDeviceId(dev['id']);
      return dev;
    }

    // 3. De lo contrario, este equipo no está vinculado (no asumir otros dispositivos)
    return null;
  }

  List<dynamic> _getOtherDevices() {
    final currentDev = _getCurrentDevice();
    if (currentDev == null) {
      // Si el equipo actual no está vinculado, mostrar todos los registrados
      return _devices;
    }
    return _devices.where((d) => d['id'] != currentDev['id']).toList();
  }

  Future<void> _triggerSync(Map<String, dynamic> device, {bool isAuto = false}) async {
    if (!_isOnPrivateNetwork && !isAuto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se requiere conexión a la Red Privada UPB para sincronizar.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);

    try {
      int uploadedCount = 0;
      final folder = (device['syncFolder'] != null && device['syncFolder'].toString().isNotEmpty)
          ? device['syncFolder'].toString()
          : (device['platform'] == 'Android' ? '/sdcard/Documents/UPB_Sync' : 'C:\\Users\\${widget.username}\\Sync');

      if (!kIsWeb) {
        if (device['platform'] == 'Android') {
          await requestStoragePermissions();
        }

        // 1. Escanear archivos en la carpeta local
        var localFiles = await listLocalDirectoryFiles(folder);

        if (localFiles.isEmpty && device['platform'] == 'Android') {
          if (folder.contains('UPB_Sync')) {
            localFiles = await listLocalDirectoryFiles(folder.replaceAll('UPB_Sync', 'UPB_SYNC'));
          } else if (folder.contains('UPB_SYNC')) {
            localFiles = await listLocalDirectoryFiles(folder.replaceAll('UPB_SYNC', 'UPB_Sync'));
          }
        }

        final gpg = GpgService();
        final keyPair = gpg.getOrCreateKeyPair(widget.username);

        // 2. Subir archivos encontrados al repositorio central
        for (final lf in localFiles) {
          final filePath = lf['path'] as String;
          final fileName = lf['name'] as String;
          var bytes = await readLocalFile(filePath);

          if (bytes != null && bytes.isNotEmpty) {
            String uploadName = fileName;

            // Aplicar Cifrado Asimétrico GPG Zero-Knowledge si está activo
            if (_gpgEnabled && !gpg.isGpgEncrypted(bytes)) {
              bytes = gpg.encryptFileAsymmetric(bytes, keyPair.publicKey);
              uploadName = fileName.endsWith('.gpg') ? fileName : '$fileName.gpg';
            }

            try {
              final uploadUri = Uri.parse('${ApiConfig.streamingUrl}/api/sync/devices/${device['id']}/upload');
              final req = http.MultipartRequest('POST', uploadUri)
                ..headers['Authorization'] = 'Bearer ${widget.token}'
                ..fields['relativePath'] = uploadName
                ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: uploadName));

              final streamedRes = await req.send();
              if (streamedRes.statusCode == 200 || streamedRes.statusCode == 201) {
                uploadedCount++;
              }
            } catch (err) {
              debugPrint('Error subiendo $fileName: $err');
            }
          }
        }

        // 3. En escritorio, ejecutar cliente nativo en background si aplica
        if (device['platform'] == 'Windows' || device['platform'] == 'Linux') {
          await runNativeSyncClient(
            token: widget.token,
            deviceId: device['id'],
            syncFolder: folder,
            serverAddr: '${ApiConfig.host}:8443',
          );
        }
      }

      // Notificar al servidor finalización
      final response = await http.post(
        Uri.parse('${ApiConfig.streamingUrl}/api/sync/devices/${device['id']}/trigger'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'isWiFiConnected': true,
          'filesCount': uploadedCount,
        }),
      );

      if (response.statusCode == 200 && mounted) {
        final res = jsonDecode(response.body);
        final msg = uploadedCount > 0
            ? '$uploadedCount archivo(s) sincronizado(s) con el repositorio central.'
            : (res['message'] ?? 'Sincronización completada exitosamente.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 4),
          ),
        );
        _fetchSyncOverview();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al ejecutar sincronización: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _pickAndAddFileToSync(Map<String, dynamic> device) {
    final folder = (device['syncFolder'] != null && device['syncFolder'].toString().isNotEmpty)
        ? device['syncFolder'].toString()
        : (device['platform'] == 'Android' ? '/sdcard/Documents/UPB_Sync' : 'C:\\Users\\${widget.username}\\Sync');

    pickFileWeb(
      onFileSelected: (fileName, fileSize, bytes) async {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guardando "$fileName" y sincronizando...'),
            duration: const Duration(seconds: 2),
          ),
        );

        if (!kIsWeb) {
          await saveLocalFile(folder, fileName, bytes);
        }

        // Subir al repositorio
        try {
          var uploadBytes = Uint8List.fromList(bytes);
          String uploadName = fileName;

          if (_gpgEnabled) {
            final gpg = GpgService();
            final keyPair = gpg.getOrCreateKeyPair(widget.username);
            uploadBytes = gpg.encryptFileAsymmetric(uploadBytes, keyPair.publicKey);
            uploadName = fileName.endsWith('.gpg') ? fileName : '$fileName.gpg';
          }

          final uploadUri = Uri.parse('${ApiConfig.streamingUrl}/api/sync/devices/${device['id']}/upload');
          final req = http.MultipartRequest('POST', uploadUri)
            ..headers['Authorization'] = 'Bearer ${widget.token}'
            ..fields['relativePath'] = uploadName
            ..files.add(http.MultipartFile.fromBytes('file', uploadBytes, filename: uploadName));

          final streamedRes = await req.send();
          if (streamedRes.statusCode == 200 || streamedRes.statusCode == 201) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('"$fileName" respaldado localmente y sincronizado en Mi Unidad.'),
                  backgroundColor: Colors.green[700],
                ),
              );
            }
            _fetchSyncOverview();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al sincronizar: $e'), backgroundColor: Colors.red[700]),
            );
          }
        }
      },
    );
  }

  Future<void> _downloadOfflineCopy(Map<String, dynamic> file) async {
    final fileId = file['id'];
    final fileName = file['name'] ?? 'archivo';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Descargando copia local de "$fileName"...'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final downloadUrl = fileId != null
          ? '${ApiConfig.streamingUrl}/api/files/files/$fileId/content'
          : '${ApiConfig.streamingUrl}/api/files/files/${file['name']}/content';

      final res = await http.get(
        Uri.parse(downloadUrl),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (res.statusCode == 200) {
        final currentDev = _getCurrentDevice();
        final folder = currentDev != null && currentDev['syncFolder'] != null
            ? currentDev['syncFolder'].toString()
            : '/sdcard/Documents/UPB_Sync';

        var finalBytes = res.bodyBytes;
        var cleanName = fileName;

        // Descifrado local automático con GPG si el archivo fue cifrado
        final gpg = GpgService();
        if (gpg.isGpgEncrypted(finalBytes)) {
          final keyPair = gpg.getOrCreateKeyPair(widget.username);
          finalBytes = gpg.decryptFileAsymmetric(finalBytes, keyPair.privateKey);
          if (cleanName.endsWith('.gpg')) {
            cleanName = cleanName.substring(0, cleanName.length - 4);
          }
        }

        final saved = await saveLocalFile(folder, cleanName, finalBytes);
        if (mounted) {
          if (saved) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copia local guardada en "$folder/$cleanName". Lista para trabajar sin conexión.'),
                backgroundColor: Colors.green[700],
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            openUrlOrDownload(downloadUrl, downloadName: cleanName);
          }
        }
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar copia: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  Future<void> _deleteDevice(Map<String, dynamic> device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('¿Desvincular ${device['name']}?'),
        content: Text('Este dispositivo (${device['platform']}) dejará de figurar en el sistema institucional.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await http.delete(
          Uri.parse('${ApiConfig.streamingUrl}/api/sync/devices/${device['id']}'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (res.statusCode == 200) {
          if (_localDeviceId == device['id']) {
            await _saveLocalDeviceId(null);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Dispositivo "${device['name']}" desvinculado con éxito.'),
                backgroundColor: Colors.green[700],
              ),
            );
            _fetchSyncOverview();
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al desvincular: $e'), backgroundColor: Colors.red[700]),
          );
        }
      }
    }
  }

  Future<void> _showRegisterDeviceDialog() async {
    final plat = _getCurrentPlatform();
    final defaultName = plat == 'Android'
        ? 'Móvil Android (${widget.username})'
        : (plat == 'Windows' ? 'Laptop Windows (${widget.username})' : 'Equipo $plat (${widget.username})');
    final defaultFolder = plat == 'Android'
        ? '/sdcard/Documents/UPB_Sync'
        : 'C:\\Users\\${widget.username}\\Sync';

    final nameCtrl = TextEditingController(text: defaultName);
    final folderCtrl = TextEditingController(text: defaultFolder);
    bool wifiOnly = plat == 'Android';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(plat == 'Android' ? Icons.smartphone : Icons.laptop, color: const Color(0xFF4F46E5)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Vincular este Dispositivo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nombre descriptivo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.devices, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Carpeta local a sincronizar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: folderCtrl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.folder_open, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.drive_folder_upload, color: Color(0xFF4F46E5)),
                          tooltip: 'Examinar carpeta...',
                          onPressed: () async {
                            final picked = await pickNativeDirectory();
                            if (picked != null && picked.isNotEmpty) {
                              setDlgState(() => folderCtrl.text = picked);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    title: const Text('Exigir Red Privada UPB (Wi-Fi)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                    subtitle: const Text('Solo sincronizar cuando esté conectado a la red institucional de la universidad.', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                    value: wifiOnly,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setDlgState(() => wifiOnly = val ?? true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 18),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                await _registerNewDevice(nameCtrl.text.trim(), plat, folderCtrl.text.trim(), wifiOnly);
              },
              label: const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _registerNewDevice(String name, String platform, String folder, bool wifiOnly) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.streamingUrl}/api/sync/devices'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'platform': platform,
          'syncFolder': folder,
          'wifiOnly': wifiOnly,
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['id'] != null) {
          await _saveLocalDeviceId(data['id']);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dispositivo "$name" vinculado exitosamente.'),
              backgroundColor: Colors.green[700],
            ),
          );
        }
        _fetchSyncOverview();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al vincular: $e'), backgroundColor: Colors.red[700]),
        );
      }
    }
  }

  void _showGpgKeysDialog() {
    final gpg = GpgService();
    final keyPair = gpg.getOrCreateKeyPair(widget.username);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield, color: Color(0xFF4F46E5)),
            SizedBox(width: 10),
            Text('Cifrado Asimétrico GPG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Esquema de Seguridad Zero-Knowledge:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Los archivos se cifran localmente con tu Clave Pública GPG antes de subirse. El servidor central solo almacena datos cifrados y nadie puede leerlos sin tu Clave Privada local.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.3, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.vpn_key, size: 16, color: Color(0xFF4F46E5)),
                          const SizedBox(width: 6),
                          Text('ID de Clave: ${keyPair.keyId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E1B4B))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Huella: ${keyPair.fingerprint}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('Algoritmo: RSA 2048-bit + AES-256-CBC', style: TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Clave Pública OpenPGP Armor:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(6)),
                  child: SelectableText(
                    keyPair.exportPublicKeyArmor(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: Color(0xFF38BDF8)),
                    maxLines: 6,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _showEditPolicyDialog(Map<String, dynamic> device) async {
    final scheduleTimeCtrl = TextEditingController(text: device['scheduleTime'] ?? '02:00');
    final folderCtrl = TextEditingController(text: device['syncFolder'] ?? '');
    String scheduleMode = device['scheduleMode'] ?? 'interval';
    int intervalMinutes = device['intervalMinutes'] ?? 5;
    bool wifiOnly = device['wifiOnly'] ?? true;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.settings, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Políticas de ${device['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Carpeta local a sincronizar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: folderCtrl,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.folder_open, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          if (!kIsWeb) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.drive_folder_upload, color: Color(0xFF4F46E5)),
                              tooltip: 'Examinar carpeta...',
                              onPressed: () async {
                                final picked = await pickNativeDirectory();
                                if (picked != null && picked.isNotEmpty) {
                                  setDlgState(() => folderCtrl.text = picked);
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Frecuencia de sincronización:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: scheduleMode,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'auto', child: Text('Al detectar conexión a la red')),
                          DropdownMenuItem(value: 'interval', child: Text('Por intervalo periódico')),
                          DropdownMenuItem(value: 'scheduled', child: Text('A una hora fija diaria')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDlgState(() => scheduleMode = val);
                        },
                      ),
                      if (scheduleMode == 'scheduled') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: scheduleTimeCtrl,
                          decoration: InputDecoration(
                            labelText: 'Hora programada (HH:MM)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                      if (scheduleMode == 'interval') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: intervalMinutes,
                          decoration: InputDecoration(
                            labelText: 'Intervalo',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Cada 1 minuto')),
                            DropdownMenuItem(value: 5, child: Text('Cada 5 minutos')),
                            DropdownMenuItem(value: 15, child: Text('Cada 15 minutos')),
                            DropdownMenuItem(value: 60, child: Text('Cada 1 hora')),
                          ],
                          onChanged: (val) {
                            if (val != null) setDlgState(() => intervalMinutes = val);
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        title: const Text('Exigir Red Privada UPB', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                        subtitle: const Text('Solo sincronizar cuando esté conectado a la red institucional', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                        value: wifiOnly,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setDlgState(() => wifiOnly = val ?? true),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteDevice(device);
                  },
                  child: const Text('Desvincular Dispositivo', style: TextStyle(color: Colors.red)),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _updateDevicePolicy(device['id'], {
                      'syncFolder': folderCtrl.text.trim(),
                      'scheduleMode': scheduleMode,
                      'scheduleTime': scheduleTimeCtrl.text.trim(),
                      'intervalMinutes': intervalMinutes,
                      'wifiOnly': wifiOnly,
                    });
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateDevicePolicy(String deviceId, Map<String, dynamic> updates) async {
    try {
      final res = await http.patch(
        Uri.parse('${ApiConfig.streamingUrl}/api/sync/devices/$deviceId'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(updates),
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Políticas guardadas.'), backgroundColor: Colors.green),
          );
        }
        _fetchSyncOverview();
      }
    } catch (_) {}
  }

  String _formatBytes(num bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4F46E5)),
            SizedBox(height: 16),
            Text('Comprobando servicio de sincronización institucional...', style: TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    if (_errorMessage != null && _devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, size: 48, color: Colors.amber[700]),
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Conéctate a la red institucional para iniciar la sincronización.', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchSyncOverview,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 768;
    final currentDevice = _getCurrentDevice();
    final otherDevices = _getOtherDevices();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de Cabecera con Estado de Red UPB
          Container(
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF312E81).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.sync, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'Sincronización Automática',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _isOnPrivateNetwork
                                      ? Colors.green[500]!.withValues(alpha: 0.25)
                                      : Colors.amber[600]!.withValues(alpha: 0.25),
                                  border: Border.all(
                                    color: _isOnPrivateNetwork ? Colors.greenAccent : Colors.amberAccent,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.fiber_manual_record,
                                      color: _isOnPrivateNetwork ? Colors.greenAccent : Colors.amberAccent,
                                      size: 8,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _isOnPrivateNetwork ? 'Red Privada UPB: Conectado' : 'Modo Offline (Fuera de Red UPB)',
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isOnPrivateNetwork
                                ? 'Tus archivos se respaldan automáticamente al estar conectado a la red institucional de la universidad.'
                                : 'Actualmente fuera de la red UPB. Puedes trabajar sin conexión; los cambios se sincronizarán al conectar.',
                            style: TextStyle(color: Colors.indigo[100], fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _showGpgKeysDialog,
                      icon: const Icon(Icons.shield_outlined, size: 16),
                      label: const Text('Seguridad GPG (Zero-Knowledge)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _fetchSyncOverview,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Verificar Red'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tarjeta Principal: Dispositivo Actual o Vincular Dispositivo
          if (currentDevice != null) ...[
            _buildCurrentDeviceCard(currentDevice, isMobile),
            const SizedBox(height: 20),
          ] else ...[
            _buildUnlinkedDeviceCard(isMobile),
            const SizedBox(height: 20),
          ],

          // Otros Dispositivos Vinculados (si los hay)
          if (otherDevices.isNotEmpty) ...[
            _buildOtherDevicesCard(otherDevices, currentDevice != null),
            const SizedBox(height: 20),
          ],

          // Repositorio Central y Registro de Actividad
          if (isMobile) ...[
            _buildSyncedFilesCard(),
            const SizedBox(height: 16),
            _buildHistoryCard(),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: _buildSyncedFilesCard()),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: _buildHistoryCard()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnlinkedDeviceCard(bool isMobile) {
    final plat = _getCurrentPlatform();
    final isAndroid = plat == 'Android';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Icon(
                  isAndroid ? Icons.smartphone : Icons.laptop_windows,
                  color: const Color(0xFF475569),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Este $plat no está vinculado',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Vincula este equipo para sincronizar tus archivos locales con el servidor central UPB.',
                      style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showRegisterDeviceDialog,
            icon: const Icon(Icons.add_link, size: 18),
            label: Text('Vincular este $plat ahora'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentDeviceCard(Map<String, dynamic> device, bool isMobile) {
    final isAndroid = device['platform'] == 'Android';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7FF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isAndroid ? Colors.green[50] : Colors.blue[50],
                child: Icon(
                  isAndroid ? Icons.smartphone : Icons.laptop_windows,
                  color: isAndroid ? Colors.green[700] : const Color(0xFF4F46E5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          device['name'] ?? 'Dispositivo Actual',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Equipo Actual',
                            style: TextStyle(color: Color(0xFF4F46E5), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device['platform']} • Carpeta local sincronizada',
                      style: const TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Color(0xFF334155)),
                tooltip: 'Configurar carpeta y horario',
                onPressed: () => _showEditPolicyDialog(device),
              ),
            ],
          ),
          const Divider(height: 24),

          // Carpeta local y opciones
          Row(
            children: [
              const Icon(Icons.folder_outlined, color: Color(0xFF4F46E5), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  device['syncFolder'] ?? 'Carpeta no configurada',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Toggle de Cifrado GPG Zero-Knowledge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _gpgEnabled ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _gpgEnabled ? const Color(0xFFC7D2FE) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield, size: 18, color: _gpgEnabled ? const Color(0xFF4F46E5) : const Color(0xFF64748B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cifrado Asimétrico GPG (Zero-Knowledge)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        _gpgEnabled ? 'Archivos cifrados antes de enviar con tu clave pública.' : 'Respaldo estándar en repositorio central.',
                        style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _gpgEnabled,
                  activeThumbColor: const Color(0xFF4F46E5),
                  onChanged: (val) => setState(() => _gpgEnabled = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Botones de acción principales
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: _isSyncing ? null : () => _triggerSync(device),
                icon: _isSyncing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync, size: 18),
                label: Text(_isSyncing ? 'Sincronizando...' : 'Sincronizar Ahora'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isSyncing ? null : () => _pickAndAddFileToSync(device),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Añadir archivo a sincronizar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFF4F46E5)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _deleteDevice(device),
                icon: const Icon(Icons.link_off, size: 16, color: Colors.red),
                label: const Text('Desvincular', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtherDevicesCard(List<dynamic> devices, bool hasCurrentDevice) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                hasCurrentDevice
                    ? 'Otros Dispositivos Vinculados (${devices.length})'
                    : 'Dispositivos Registrados (${devices.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
              ),
              Text(
                hasCurrentDevice
                    ? 'Sincronización reservada al equipo en uso'
                    : 'Administra tus equipos',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: devices.length,
            separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (ctx, i) {
              final d = devices[i];
              final isAndroid = d['platform'] == 'Android';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFF1F5F9),
                  child: Icon(
                    isAndroid ? Icons.smartphone : Icons.computer,
                    size: 16,
                    color: const Color(0xFF334155),
                  ),
                ),
                title: Text(
                  d['name'] ?? 'Dispositivo',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                ),
                subtitle: Text(
                  'Ruta: ${d['syncFolder']} • ${d['status'] ?? 'Registrado'}',
                  style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w500),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  tooltip: 'Desvincular dispositivo',
                  onPressed: () => _deleteDevice(d),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncedFilesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done_outlined, color: Color(0xFF4F46E5), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Archivos en Repositorio Central',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              Text(
                '${_syncedFiles.length} archivos',
                style: const TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_syncedFiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.folder_open, size: 40, color: Color(0xFF94A3B8)),
                    SizedBox(height: 8),
                    Text(
                      'No hay archivos sincronizados aún en el repositorio central.',
                      style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _syncedFiles.length,
              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final f = _syncedFiles[index];
                final isGpg = (f['name'] as String? ?? '').endsWith('.gpg');

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isGpg ? const Color(0xFFFDF2F8) : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isGpg ? Icons.lock : Icons.insert_drive_file,
                      color: isGpg ? Colors.pink[700] : const Color(0xFF4F46E5),
                      size: 18,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          f['name'] ?? f['path'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isGpg)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.pink[50],
                            border: Border.all(color: Colors.pinkAccent),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('GPG Zero-Knowledge', style: TextStyle(color: Colors.pink, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${f['device'] ?? 'Dispositivo'} • ${f['size'] != null ? _formatBytes(f['size']) : ''}',
                    style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF4F46E5), size: 20),
                    tooltip: isGpg ? 'Descargar y descifrar copia local' : 'Descargar copia local (offline)',
                    onPressed: () => _downloadOfflineCopy(f),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, color: Color(0xFF4F46E5), size: 20),
                  SizedBox(width: 8),
                  Text('Historial y Auditoría', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                ],
              ),
              Text('${_history.length} registros', style: const TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28.0),
              child: Center(
                child: Text('Sin eventos recientes', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _history.length > 8 ? 8 : _history.length,
              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final h = _history[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Colors.green[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h['detail'] ?? h['action'] ?? '',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                            ),
                            if (h['timestamp'] != null)
                              Text(
                                h['timestamp'].toString().substring(0, 19).replaceAll('T', ' '),
                                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
