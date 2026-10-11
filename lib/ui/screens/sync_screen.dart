import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';

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

  Map<String, dynamic>? _serverInfo;
  List<dynamic> _devices = [];
  List<dynamic> _syncedFiles = [];
  List<dynamic> _history = [];

  String? _selectedDeviceId;
  bool _simulatedWiFi = true; // Permite simular Wi-Fi vs datos móviles en pruebas

  @override
  void initState() {
    super.initState();
    _fetchSyncOverview();
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
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _serverInfo = data['server'];
            _devices = data['devices'] ?? [];
            _syncedFiles = data['syncedFiles'] ?? [];
            _history = data['history'] ?? [];
            if (_selectedDeviceId == null && _devices.isNotEmpty) {
              _selectedDeviceId = _devices.first['id'];
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Error ${response.statusCode}: ${response.body}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error conectando al servidor de sincronización: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _triggerSync(Map<String, dynamic> device) async {
    setState(() => _isSyncing = true);

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.streamingUrl}/api/sync/devices/${device['id']}/trigger'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'isWiFiConnected': _simulatedWiFi,
        }),
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (mounted) {
          if (res['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text(res['message'] ?? 'Sincronización exitosa')),
                  ],
                ),
                backgroundColor: Colors.green[700],
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text(res['message'] ?? 'Sincronización en pausa')),
                  ],
                ),
                backgroundColor: Colors.amber[900],
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
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

  Future<void> _showEditPolicyDialog(Map<String, dynamic> device) async {
    final scheduleTimeCtrl = TextEditingController(text: device['scheduleTime'] ?? '02:00');
    final folderCtrl = TextEditingController(text: device['syncFolder'] ?? '');
    String scheduleMode = device['scheduleMode'] ?? 'interval';
    int intervalMinutes = device['intervalMinutes'] ?? 5;
    bool wifiOnly = device['wifiOnly'] ?? (device['platform'] == 'Android');

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    device['platform'] == 'Android' ? Icons.smartphone : Icons.computer,
                    color: const Color(0xFF4F46E5),
                  ),
                  const SizedBox(width: 10),
                  Text('Políticas de ${device['name']}'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Directorio local a sincronizar:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: folderCtrl,
                        decoration: InputDecoration(
                          hintText: 'Ruta local (ej. C:\\FyleSync o /sdcard/Documents)',
                          prefixIcon: const Icon(Icons.folder_open, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Modo de Programación:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: scheduleMode,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'auto', child: Text('En tiempo real / Automático')),
                          DropdownMenuItem(value: 'interval', child: Text('Por intervalo periódico')),
                          DropdownMenuItem(value: 'scheduled', child: Text('A una hora fija programada')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDlgState(() => scheduleMode = val);
                        },
                      ),
                      if (scheduleMode == 'scheduled') ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Hora diaria programada (HH:MM):',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: scheduleTimeCtrl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.access_time, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ] else if (scheduleMode == 'interval') ...[
                        const SizedBox(height: 12),
                        Text(
                          'Intervalo: cada $intervalMinutes minutos',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Slider(
                          value: intervalMinutes.toDouble(),
                          min: 1,
                          max: 60,
                          divisions: 59,
                          label: '$intervalMinutes min',
                          activeColor: const Color(0xFF4F46E5),
                          onChanged: (val) {
                            setDlgState(() => intervalMinutes = val.round());
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.wifi,
                              color: wifiOnly ? Colors.blue[700] : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Exigir conexión Wi-Fi local',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    'Si se desactiva o está en red celular, la sincronización se detiene hasta conectar al Wi-Fi.',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: wifiOnly,
                              activeColor: const Color(0xFF4F46E5),
                              onChanged: (val) {
                                setDlgState(() => wifiOnly = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _updatePolicy(device['id'], {
                      'syncFolder': folderCtrl.text.trim(),
                      'scheduleMode': scheduleMode,
                      'scheduleTime': scheduleTimeCtrl.text.trim(),
                      'intervalMinutes': intervalMinutes,
                      'wifiOnly': wifiOnly,
                    });
                  },
                  child: const Text('Guardar Políticas'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updatePolicy(String deviceId, Map<String, dynamic> updates) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.streamingUrl}/api/sync/devices/$deviceId'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(updates),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Políticas actualizadas correctamente.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _fetchSyncOverview();
      }
    } catch (_) {}
  }

  Future<void> _showRegisterDeviceDialog() async {
    final nameCtrl = TextEditingController();
    final folderCtrl = TextEditingController();
    String platform = 'Windows';
    bool wifiOnly = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.devices, color: Color(0xFF4F46E5)),
                  SizedBox(width: 10),
                  Text('Vincular Nuevo Dispositivo'),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: platform,
                      decoration: InputDecoration(
                        labelText: 'Plataforma',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Windows', child: Text('Windows (Escritorio / Portátil)')),
                        DropdownMenuItem(value: 'Linux', child: Text('Linux (Servidor / Estación)')),
                        DropdownMenuItem(value: 'Android', child: Text('Android (Dispositivo Móvil)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDlgState(() {
                            platform = val;
                            wifiOnly = (val == 'Android');
                            if (folderCtrl.text.isEmpty) {
                              folderCtrl.text = val == 'Android'
                                  ? '/sdcard/Documents/UPB_Sync'
                                  : 'C:\\Users\\${widget.username}\\Sync';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nombre del dispositivo',
                        hintText: 'Ej. Laptop Personal HP',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: folderCtrl,
                      decoration: InputDecoration(
                        labelText: 'Directorio local a sincronizar',
                        hintText: platform == 'Android' ? '/sdcard/Documents/Sync' : 'C:\\FyleSync',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('Exigir Wi-Fi local para sincronizar'),
                      subtitle: const Text('Recomendado para celulares y datos limitados'),
                      value: wifiOnly,
                      onChanged: (val) => setDlgState(() => wifiOnly = val ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _registerNewDevice(
                      nameCtrl.text.trim().isEmpty ? 'Dispositivo $platform' : nameCtrl.text.trim(),
                      platform,
                      folderCtrl.text.trim(),
                      wifiOnly,
                    );
                  },
                  child: const Text('Vincular'),
                ),
              ],
            );
          },
        );
      },
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
      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dispositivo "$name" vinculado con éxito.'),
              backgroundColor: Colors.green,
            ),
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
            Text('Cargando servicio de sincronización automática...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red[600], fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchSyncOverview,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de Cabecera con Estado del Servidor gRPC
          Container(
            padding: const EdgeInsets.all(20),
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
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.sync, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'File Sync: Sincronización Automática',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green[500]!.withValues(alpha: 0.25),
                              border: Border.all(color: Colors.greenAccent),
                              borderRadius: BorderRadius.circular(12),
                            ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.fiber_manual_record, color: Colors.greenAccent, size: 10),
                                  const SizedBox(width: 6),
                                  Text(
                                    _serverInfo != null
                                        ? '${_serverInfo!['name'] ?? 'File Sync'} (${_serverInfo!['address'] ?? ':8443'})'
                                        : 'Servidor Go gRPC Online (:8443 TLS)',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Copia síncrona transparente entre dispositivos locales (Escritorio / Android) y el repositorio central unificado.',
                        style: TextStyle(color: Colors.indigo[100], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showRegisterDeviceDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Vincular Dispositivo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Simulador de Estado de Conexión (Para pruebas del requerimiento Wi-Fi móvil)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(
                  _simulatedWiFi ? Icons.wifi : Icons.signal_cellular_alt,
                  color: _simulatedWiFi ? Colors.blue[600] : Colors.amber[800],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _simulatedWiFi
                            ? 'Conectado a Red Wi-Fi Local (UPB Campus / Red Interna)'
                            : 'Conectado a Red Celular / Datos Móviles 4G/5G (Sin Wi-Fi local)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _simulatedWiFi ? Colors.grey[900] : Colors.amber[900],
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Alterna el switch para verificar la política que restringe la sincronización móvil en redes celulares.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _simulatedWiFi,
                  activeColor: Colors.blue[600],
                  inactiveThumbColor: Colors.amber[800],
                  onChanged: (val) {
                    setState(() => _simulatedWiFi = val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Título de Sección: Dispositivos Vinculados
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Dispositivos Registrados (Escritorio y Móvil)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${_devices.length} dispositivos configurados',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Cuadrícula de Tarjetas de Dispositivos
          LayoutBuilder(
            builder: (context, constraints) {
              int cols = (constraints.maxWidth / 360).floor().clamp(1, 3);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final dev = _devices[index];
                  final isAndroid = dev['platform'] == 'Android';
                  final isWindows = dev['platform'] == 'Windows';
                  final isSelected = dev['id'] == _selectedDeviceId;

                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF4F46E5) : Colors.grey[200]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: isAndroid
                                    ? Colors.green[50]
                                    : (isWindows ? Colors.blue[50] : Colors.purple[50]),
                                child: Icon(
                                  isAndroid ? Icons.smartphone : (isWindows ? Icons.desktop_windows : Icons.terminal),
                                  color: isAndroid
                                      ? Colors.green[700]
                                      : (isWindows ? Colors.blue[700] : Colors.purple[700]),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dev['name'] ?? dev['id'],
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${dev['platform']} • ID: ${dev['id']}',
                                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings_outlined, size: 20),
                                tooltip: 'Configurar Políticas',
                                onPressed: () => _showEditPolicyDialog(dev),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          // Info de Carpeta y Programador
                          Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 14, color: Colors.grey),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  dev['syncFolder'] ?? 'Sin carpeta configurada',
                                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.schedule, size: 14, color: Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                dev['scheduleMode'] == 'scheduled'
                                    ? 'Programado a las ${dev['scheduleTime'] ?? '02:00'}'
                                    : (dev['scheduleMode'] == 'auto'
                                        ? 'Sincronización en tiempo real'
                                        : 'Cada ${dev['intervalMinutes'] ?? 5} min'),
                                style: TextStyle(color: Colors.grey[700], fontSize: 12),
                              ),
                              const Spacer(),
                              if (dev['wifiOnly'] == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Solo Wi-Fi',
                                    style: TextStyle(color: Colors.blue[800], fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          // Botón Sincronizar Ahora
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSyncing ? null : () => _triggerSync(dev),
                              icon: const Icon(Icons.sync, size: 16),
                              label: Text(_isSyncing ? 'Sincronizando...' : 'Sincronizar Ahora'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 32),

          // Dos columnas: Archivos en Repositorio Central y Registro de Auditoría
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Columna 1: Archivos Sincronizados
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.cloud_done_outlined, color: Color(0xFF4F46E5), size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Archivos Sincronizados en el Repositorio Central',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          Text(
                            '${_syncedFiles.length} archivos',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_syncedFiles.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32.0),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.folder_open, size: 48, color: Colors.grey[300]),
                                const SizedBox(height: 8),
                                Text(
                                  'Aún no hay archivos sincronizados en /var/fylesync/home/${widget.username}',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
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
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[100]),
                          itemBuilder: (context, index) {
                            final f = _syncedFiles[index];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.insert_drive_file, color: Color(0xFF4F46E5), size: 20),
                              ),
                              title: Text(
                                f['name'] ?? f['path'],
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              subtitle: Text(
                                'Rama: ${f['branch']} • Rev: ${f['revision']} • ${f['size'] != null ? _formatBytes(f['size']) : ''}',
                                style: TextStyle(color: Colors.grey[500], fontSize: 11),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Sincronizado',
                                  style: TextStyle(color: Colors.green[800], fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Columna 2: Historial y Auditoría en Tiempo Real
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.history, color: Color(0xFF4F46E5), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Historial de Sincronización',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32.0),
                          child: Center(
                            child: Text(
                              'No hay eventos registrados recientemente.',
                              style: TextStyle(color: Colors.grey[500], fontSize: 13),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _history.length,
                          separatorBuilder: (_, __) => Divider(height: 12, color: Colors.grey[100]),
                          itemBuilder: (context, index) {
                            final h = _history[index];
                            final isSuccess = h['status'] == 'EXITO';
                            final isBlocked = h['status'] == 'EN_ESPERA_WIFI';

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isSuccess
                                        ? Colors.green[50]
                                        : (isBlocked ? Colors.amber[50] : Colors.blue[50]),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isSuccess
                                        ? Icons.check
                                        : (isBlocked ? Icons.wifi_off : Icons.sync),
                                    size: 14,
                                    color: isSuccess
                                        ? Colors.green[700]
                                        : (isBlocked ? Colors.amber[800] : Colors.blue[700]),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        h['detail'] ?? h['action'],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isBlocked ? Colors.amber[900] : Colors.grey[800],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${h['platform']} • ${h['timestamp'] != null ? h['timestamp'].toString().substring(11, 19) : ''}',
                                        style: TextStyle(color: Colors.grey[400], fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
