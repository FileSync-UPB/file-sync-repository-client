import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'preview_screen.dart';
import 'share_dialog_inner.dart';
import 'sync_screen.dart';
import 'hpc_screen.dart';
import '../../config/api_config.dart';
import '../../platform/platform_utils.dart';

enum FileSection {
  myDrive,
  sharedWithMe,
  recent,
  starred,
  trash,
  sync,
  hpc,
}

class HomeScreen extends StatefulWidget {
  final String token;
  final String username;

  const HomeScreen({
    super.key,
    required this.token,
    required this.username,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _errorMessage;

  FileSection _currentSection = FileSection.myDrive;

  // Folder navigation state
  String? _currentParentId;
  final List<Map<String, String?>> _breadcrumbs = [
    {'id': null, 'name': 'Mi Unidad'}
  ];

  // Storage usage state
  int _usedBytes = 0;
  int _limitBytes = 1 * 1024 * 1024 * 1024; // 1 GB default

  @override
  void initState() {
    super.initState();
    _fetchFiles();
    _fetchUsage();
  }

  String _formatBytes(num bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _fetchUsage() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.streamingUrl}/api/files/usage'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _usedBytes = data['usedBytes'] ?? 0;
            _limitBytes = data['quotaBytes'] ?? (1 * 1024 * 1024 * 1024);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchFiles() async {
    if (_currentSection == FileSection.sync || _currentSection == FileSection.hpc) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String urlStr;
      if (_currentParentId != null) {
        urlStr = '${ApiConfig.streamingUrl}/api/files?parentId=${Uri.encodeComponent(_currentParentId!)}';
      } else {
        switch (_currentSection) {
          case FileSection.myDrive:
            urlStr = '${ApiConfig.streamingUrl}/api/files';
            break;
          case FileSection.sharedWithMe:
            urlStr = '${ApiConfig.streamingUrl}/api/files/shared';
            break;
          case FileSection.recent:
            urlStr = '${ApiConfig.streamingUrl}/api/files/recent';
            break;
          case FileSection.starred:
            urlStr = '${ApiConfig.streamingUrl}/api/files/starred';
            break;
          case FileSection.trash:
            urlStr = '${ApiConfig.streamingUrl}/api/files/trash';
            break;
          case FileSection.sync:
          case FileSection.hpc:
            urlStr = '${ApiConfig.streamingUrl}/api/files';
            break;
        }
      }

      final response = await http.get(
        Uri.parse(urlStr),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _items = data['items'] ?? [];
        });
      } else {
        setState(() {
          _errorMessage = 'Error al cargar los archivos (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createFolderDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.create_new_folder_outlined, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('Nueva Carpeta'),
          ],
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre de la carpeta',
              hintText: 'Ej. Documentos, Proyectos...',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El nombre no puede estar vacío';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (created == true) {
      await _createFolder(controller.text.trim());
    }
  }

  Future<void> _createFolder(String name) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.streamingUrl}/api/files/folders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'name': name,
          'parentId': _currentParentId,
        }),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Carpeta "$name" creada exitosamente.'),
              backgroundColor: Colors.green[700],
            ),
          );
        }
        _fetchFiles();
      } else {
        final err = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${err['error'] ?? 'No se pudo crear la carpeta'}'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red al crear carpeta: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  void _pickAndUploadFile() {
    pickFileWeb(
      onFileSelected: (name, size, bytes) async {
        setState(() {
          _isUploading = true;
        });

        try {
          final uri = Uri.parse('${ApiConfig.streamingUrl}/api/files/upload');
          final request = http.MultipartRequest('POST', uri);
          request.headers['Authorization'] = 'Bearer ${widget.token}';

          if (_currentParentId != null) {
            request.fields['parentId'] = _currentParentId!;
          }

          final multipartFile = http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: name,
          );
          request.files.add(multipartFile);

          final streamedResponse = await request.send();
          final response = await http.Response.fromStream(streamedResponse);

          if (response.statusCode == 201) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Archivo "$name" subido con éxito.'),
                  backgroundColor: Colors.green[700],
                ),
              );
            }
            _fetchFiles();
            _fetchUsage();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error al subir (${response.statusCode}): ${response.body}'),
                  backgroundColor: Colors.red[700],
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error de subida: $e'),
                backgroundColor: Colors.red[700],
              ),
            );
          }
        } finally {
          if (mounted) {
            setState(() {
              _isUploading = false;
            });
          }
        }
      },
    );
  }

  Future<void> _deleteItem(String id, String name, bool isFolder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Estás seguro de que deseas enviar "$name" a la papelera?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await http.delete(
          Uri.parse('${ApiConfig.streamingUrl}/api/files/files/$id'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"$name" movido a la papelera.'),
                backgroundColor: Colors.green[700],
              ),
            );
          }
          _fetchFiles();
          _fetchUsage();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al eliminar: ${response.statusCode}'),
                backgroundColor: Colors.red[700],
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
    }
  }

  void _downloadFile(String id, String name) {
    final downloadUrl =
        '${ApiConfig.streamingUrl}/api/files/files/$id/content?token=${Uri.encodeComponent(widget.token)}';
    openUrlOrDownload(downloadUrl, downloadName: name);
  }

  void _previewFile(String id, String name, String? mimeType) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          id: id,
          name: name,
          token: widget.token,
          mimeType: mimeType,
        ),
      ),
    );
  }

  void _enterFolder(String id, String name) {
    setState(() {
      _currentParentId = id;
      _breadcrumbs.add({'id': id, 'name': name});
    });
    _fetchFiles();
  }

  void _shareItem(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) {
        return ShareDialogInner(
          fileId: id,
          fileName: name,
          token: widget.token,
          onShared: () {
            _fetchFiles();
          },
        );
      },
    );
  }

  void _switchSection(FileSection section) {
    if (_currentSection == section) return;
    setState(() {
      _currentSection = section;
      _currentParentId = null;
      _breadcrumbs.clear();
      _breadcrumbs.add({'id': null, 'name': _getSectionTitle(section)});
    });
    _fetchFiles();
  }

  String _getSectionTitle(FileSection section) {
    switch (section) {
      case FileSection.myDrive:
        return 'Mi Unidad';
      case FileSection.sharedWithMe:
        return 'Compartidos conmigo';
      case FileSection.recent:
        return 'Recientes';
      case FileSection.starred:
        return 'Destacados';
      case FileSection.trash:
        return 'Papelera';
      case FileSection.sync:
        return 'Sincronización de Dispositivos';
      case FileSection.hpc:
        return 'Computación de Alto Rendimiento';
    }
  }

  String _getSectionSubtitle(FileSection section) {
    switch (section) {
      case FileSection.myDrive:
        return 'Tus archivos y carpetas en la nube';
      case FileSection.sharedWithMe:
        return 'Archivos compartidos contigo por otros colaboradores';
      case FileSection.recent:
        return 'Archivos consultados o modificados recientemente';
      case FileSection.starred:
        return 'Elementos marcados con estrella para acceso rápido';
      case FileSection.trash:
        return 'Elementos eliminados que puedes restaurar o borrar definitivamente';
      case FileSection.sync:
        return 'Estado y control de sincronización automática de clientes Windows, Linux y Android';
      case FileSection.hpc:
        return 'Ejecución acelerada y distribuida de algoritmos científicos, análisis de datos y procesamiento intensivo';
    }
  }

  IconData _getSectionEmptyIcon(FileSection section) {
    switch (section) {
      case FileSection.myDrive:
        return Icons.folder_open;
      case FileSection.sharedWithMe:
        return Icons.people_outline;
      case FileSection.recent:
        return Icons.access_time;
      case FileSection.starred:
        return Icons.star_border;
      case FileSection.trash:
        return Icons.delete_outline;
      case FileSection.sync:
        return Icons.sync_alt;
      case FileSection.hpc:
        return Icons.rocket_launch_rounded;
    }
  }

  String _getSectionEmptyTitle(FileSection section) {
    switch (section) {
      case FileSection.myDrive:
        return 'Esta carpeta está vacía';
      case FileSection.sharedWithMe:
        return 'No hay archivos compartidos contigo';
      case FileSection.recent:
        return 'No hay archivos recientes';
      case FileSection.starred:
        return 'No tienes elementos destacados';
      case FileSection.trash:
        return 'La papelera está vacía';
      case FileSection.sync:
        return 'Panel de sincronización';
      case FileSection.hpc:
        return 'Panel de Computación Avanzada';
    }
  }

  String _getSectionEmptySubtitle(FileSection section) {
    switch (section) {
      case FileSection.myDrive:
        return 'Crea una nueva carpeta o sube archivos para comenzar';
      case FileSection.sharedWithMe:
        return 'Cuando otros usuarios compartan archivos contigo, aparecerán aquí';
      case FileSection.recent:
        return 'Los archivos que abras o subas recientemente se mostrarán aquí';
      case FileSection.starred:
        return 'Usa la opción de destacar en cualquier archivo para tenerlo a mano';
      case FileSection.trash:
        return 'Los elementos que envíes a la papelera aparecerán en este apartado';
      case FileSection.sync:
        return 'Administra tus dispositivos y políticas de red';
      case FileSection.hpc:
        return 'Configura parámetros y envía tareas de procesamiento distribuido';
    }
  }

  Future<void> _toggleStar(String id) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.streamingUrl}/api/files/$id/star'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isStarred = data['isStarred'] ?? false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isStarred ? 'Marcado como destacado' : 'Desmarcado de destacados'),
              duration: const Duration(seconds: 1),
              backgroundColor: const Color(0xFF4F46E5),
            ),
          );
        }
        _fetchFiles();
      }
    } catch (_) {}
  }

  Future<void> _restoreItem(String id, String name) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.streamingUrl}/api/files/trash/$id/restore'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$name" restaurado con éxito.'),
              backgroundColor: Colors.green[700],
            ),
          );
        }
        _fetchFiles();
        _fetchUsage();
      } else {
        final err = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al restaurar: ${err['error'] ?? response.body}'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[700]),
        );
      }
    }
  }

  Future<void> _deletePermanently(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar definitivamente'),
        content: Text('¿Deseas eliminar permanentemente "$name"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar para siempre'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final response = await http.delete(
          Uri.parse('${ApiConfig.streamingUrl}/api/files/trash/$id/permanent'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('"$name" eliminado permanentemente.'), backgroundColor: Colors.green[700]),
            );
          }
          _fetchFiles();
          _fetchUsage();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[700]),
          );
        }
      }
    }
  }

  Future<void> _emptyTrashDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Vaciar Papelera'),
        content: const Text('¿Estás seguro de que deseas vaciar toda la papelera? Todos los elementos se eliminarán de forma permanente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vaciar Todo'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final response = await http.delete(
          Uri.parse('${ApiConfig.streamingUrl}/api/files/trash/empty'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Papelera vaciada por completo.'), backgroundColor: Colors.green),
            );
          }
          _fetchFiles();
          _fetchUsage();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[700]),
          );
        }
      }
    }
  }

  void _navigateToBreadcrumb(int index) {
    if (index == _breadcrumbs.length - 1) return;
    setState(() {
      final target = _breadcrumbs[index];
      _currentParentId = target['id'];
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
    });
    _fetchFiles();
  }

  Future<void> _moveItem(String id, String name, String? targetParentId, String targetFolderName) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.streamingUrl}/api/files/files/$id'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'parentId': targetParentId,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$name" se movió a "$targetFolderName".'),
              backgroundColor: Colors.green[700],
            ),
          );
        }
        _fetchFiles();
        _fetchUsage();
      } else {
        final err = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al mover: ${err['error'] ?? response.body}'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión al mover: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  void _showMoveDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => MoveFileDialog(
        item: item,
        token: widget.token,
        onMoved: (targetParentId, targetFolderName) {
          _moveItem(item['id'].toString(), item['name'] ?? '', targetParentId, targetFolderName);
        },
      ),
    );
  }

  IconData _getFileIcon(String? mimeType, String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].contains(ext) ||
        (mimeType?.startsWith('image/') ?? false)) {
      return Icons.image_outlined;
    }
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext) ||
        (mimeType?.startsWith('video/') ?? false)) {
      return Icons.video_file_outlined;
    }
    if (['mp3', 'wav', 'ogg', 'm4a'].contains(ext) ||
        (mimeType?.startsWith('audio/') ?? false)) {
      return Icons.audio_file_outlined;
    }
    if (['pdf'].contains(ext)) {
      return Icons.picture_as_pdf_outlined;
    }
    if (['doc', 'docx', 'txt', 'rtf'].contains(ext)) {
      return Icons.description_outlined;
    }
    if (['xls', 'xlsx', 'csv'].contains(ext)) {
      return Icons.table_chart_outlined;
    }
    if (['zip', 'rar', 'tar', 'gz', '7z'].contains(ext)) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _getFileColor(String? mimeType, String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].contains(ext) ||
        (mimeType?.startsWith('image/') ?? false)) {
      return Colors.purple[400]!;
    }
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext) ||
        (mimeType?.startsWith('video/') ?? false)) {
      return Colors.red[400]!;
    }
    if (['mp3', 'wav', 'ogg', 'm4a'].contains(ext) ||
        (mimeType?.startsWith('audio/') ?? false)) {
      return Colors.amber[700]!;
    }
    if (['pdf'].contains(ext)) {
      return Colors.red[600]!;
    }
    if (['doc', 'docx', 'txt'].contains(ext)) {
      return Colors.blue[600]!;
    }
    if (['xls', 'xlsx', 'csv'].contains(ext)) {
      return Colors.green[600]!;
    }
    return Colors.blueGrey[400]!;
  }

  bool _isImage(String? mimeType, String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].contains(ext) ||
        (mimeType?.startsWith('image/') ?? false);
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _getBottomNavIndex(FileSection section) {
    switch (section) {
      case FileSection.myDrive:
        return 0;
      case FileSection.sharedWithMe:
        return 1;
      case FileSection.sync:
        return 2;
      case FileSection.hpc:
        return 3;
      default:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usedFormatted = _formatBytes(_usedBytes);
    final limitFormatted = _formatBytes(_limitBytes);
    final progress = _limitBytes > 0
        ? (_usedBytes / _limitBytes).clamp(0.0, 1.0)
        : 0.0;
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: isMobile
          ? Drawer(
              backgroundColor: Colors.white,
              child: SafeArea(
                child: _buildNavigationList(
                  progress: progress,
                  usedFormatted: usedFormatted,
                  limitFormatted: limitFormatted,
                  isDrawer: true,
                ),
              ),
            )
          : null,
      bottomNavigationBar: isMobile
          ? BottomNavigationBar(
              currentIndex: _getBottomNavIndex(_currentSection),
              onTap: (index) {
                if (index == 0) _switchSection(FileSection.myDrive);
                if (index == 1) _switchSection(FileSection.sharedWithMe);
                if (index == 2) _switchSection(FileSection.sync);
                if (index == 3) _switchSection(FileSection.hpc);
                if (index == 4) _scaffoldKey.currentState?.openDrawer();
              },
              selectedItemColor: const Color(0xFF4F46E5),
              unselectedItemColor: Colors.grey[500],
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              elevation: 8,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Archivos'),
                BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Compartidos'),
                BottomNavigationBarItem(icon: Icon(Icons.sync_alt), label: 'Sync'),
                BottomNavigationBarItem(icon: Icon(Icons.rocket_launch_rounded), label: 'Cómputo'),
                BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Más'),
              ],
            )
          : null,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF1E293B)),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud, color: Color(0xFF4F46E5), size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              'FileSync',
              style: TextStyle(
                color: Colors.grey[900],
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          if (!isMobile)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF4F46E5),
                      child: Text(
                        widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.username,
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF4F46E5),
                child: Text(
                  widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Cerrar Sesión',
            icon: Icon(Icons.logout, color: Colors.grey[600]),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isMobile
          ? _buildMainWorkspace(isMobile)
          : Row(
              children: [
                // Sidebar Escritorio
                Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Colors.grey[200]!)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: _buildNavigationList(
                    progress: progress,
                    usedFormatted: usedFormatted,
                    limitFormatted: limitFormatted,
                    isDrawer: false,
                  ),
                ),
                // Workspace Escritorio
                Expanded(
                  child: _buildMainWorkspace(isMobile),
                ),
              ],
            ),
    );
  }

  Widget _buildMainWorkspace(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 12 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Action Buttons
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBreadcrumbsOrTitle(),
                const SizedBox(height: 12),
                _buildActionButtons(isMobile),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildBreadcrumbsOrTitle()),
                const SizedBox(width: 16),
                _buildActionButtons(isMobile),
              ],
            ),
          SizedBox(height: isMobile ? 12 : 24),
          // Content grid / list
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbsOrTitle() {
    if (_breadcrumbs.length > 1 || _currentSection == FileSection.myDrive) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_breadcrumbs.length, (index) {
            final b = _breadcrumbs[index];
            final isLast = index == _breadcrumbs.length - 1;
            return Row(
              children: [
                DragTarget<Map<String, dynamic>>(
                  onWillAcceptWithDetails: (details) {
                    final dragged = details.data;
                    return dragged['id'].toString() != b['id']?.toString() && _currentParentId != b['id'];
                  },
                  onAcceptWithDetails: (details) {
                    final dragged = details.data;
                    _moveItem(dragged['id'].toString(), dragged['name'] ?? '', b['id'], b['name']!);
                  },
                  builder: (context, candidateData, rejectedData) {
                    final isHovered = candidateData.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: isHovered
                          ? BoxDecoration(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF4F46E5), width: 1.5),
                            )
                          : null,
                      child: InkWell(
                        onTap: () => _navigateToBreadcrumb(index),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            b['name']!,
                            style: TextStyle(
                              fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
                              fontSize: isLast ? 18 : 16,
                              color: isLast ? Colors.grey[900] : const Color(0xFF4F46E5),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (!isLast)
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
              ],
            );
          }),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getSectionTitle(_currentSection),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.grey[900],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _getSectionSubtitle(_currentSection),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isMobile) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh, color: Colors.grey),
          onPressed: _isLoading ? null : () {
            _fetchFiles();
            _fetchUsage();
          },
        ),
        if (_currentSection == FileSection.myDrive) ...[
          OutlinedButton.icon(
            onPressed: _isLoading || _isUploading ? null : _createFolderDialog,
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            label: const Text('Carpeta'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[800],
              side: BorderSide(color: Colors.grey[300]!),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 8 : 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isLoading || _isUploading ? null : _pickAndUploadFile,
            icon: _isUploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.white),
            label: Text(
              _isUploading ? 'Subiendo...' : 'Subir',
              style: const TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 18, vertical: isMobile ? 8 : 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ] else if (_currentSection == FileSection.trash) ...[
          OutlinedButton.icon(
            onPressed: _isLoading || _items.isEmpty ? null : _emptyTrashDialog,
            icon: const Icon(Icons.delete_forever, size: 16, color: Colors.red),
            label: const Text('Vaciar Papelera', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.red[300]!),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 8 : 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContent() {
    if (_currentSection == FileSection.sync) {
      return SyncScreen(token: widget.token, username: widget.username);
    }

    if (_currentSection == FileSection.hpc) {
      return HpcScreen(token: widget.token, username: widget.username);
    }

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4F46E5)),
            SizedBox(height: 16),
            Text('Cargando archivos...', style: TextStyle(color: Colors.grey)),
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
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red[600], fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchFiles,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(_getSectionEmptyIcon(_currentSection), size: 56, color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),
            Text(
              _getSectionEmptyTitle(_currentSection),
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getSectionEmptySubtitle(_currentSection),
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        int crossAxisCount = isNarrow ? 2 : (constraints.maxWidth / 220).floor().clamp(2, 6);
        double childAspectRatio = isNarrow ? 0.86 : 1.1;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: isNarrow ? 10 : 16,
            mainAxisSpacing: isNarrow ? 10 : 16,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final isFolder = item['kind'] == 'folder';
            final id = item['id'].toString();
            final name = item['name'] ?? 'Sin nombre';
            final size = item['size'];
            final mimeType = item['mimeType'];
            final isOwner = _currentSection != FileSection.sharedWithMe &&
                (item['ownerId'] == widget.username ||
                    (item['ownerId'] == null && _currentSection == FileSection.myDrive));

            final cardWidget = Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (_currentSection == FileSection.trash) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Text('Elemento en Papelera'),
                        content: Text('"$name" está en la papelera. ¿Deseas restaurarlo?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _restoreItem(id, name);
                            },
                            child: const Text('Restaurar'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }
                  if (isFolder) {
                    _enterFolder(id, name);
                  } else {
                    _previewFile(id, name, mimeType);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Thumbnail/Icon Area
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isFolder
                              ? const Color(0xFFEEF2FF)
                              : Colors.grey[50],
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (!isFolder && _isImage(mimeType, name))
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                child: FutureBuilder<http.Response>(
                                  future: http.get(
                                    Uri.parse('${ApiConfig.streamingUrl}/api/files/files/$id/content'),
                                    headers: {'Authorization': 'Bearer ${widget.token}'},
                                  ),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                    }
                                    if (snapshot.hasData && snapshot.data!.statusCode == 200) {
                                      return Image.memory(
                                        snapshot.data!.bodyBytes,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Icon(
                                          _getFileIcon(mimeType, name),
                                          size: 48,
                                          color: _getFileColor(mimeType, name),
                                        ),
                                      );
                                    }
                                    return Center(
                                      child: Icon(
                                        _getFileIcon(mimeType, name),
                                        size: 48,
                                        color: _getFileColor(mimeType, name),
                                      ),
                                    );
                                  },
                                ),
                              )
                            else
                              Center(
                                child: Icon(
                                  isFolder ? Icons.folder : _getFileIcon(mimeType, name),
                                  size: isNarrow ? 46 : 64,
                                  color: isFolder
                                      ? const Color(0xFF4F46E5)
                                      : _getFileColor(mimeType, name),
                                ),
                              ),
                            // Star button in top-left
                            if (_currentSection != FileSection.trash)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: InkWell(
                                  onTap: () => _toggleStar(id),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      shape: BoxShape.circle,
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                                      ],
                                    ),
                                    child: Icon(
                                      item['isStarred'] == true ? Icons.star : Icons.star_border,
                                      size: 18,
                                      color: item['isStarred'] == true ? Colors.amber[700] : Colors.grey[400],
                                    ),
                                  ),
                                ),
                              ),
                            // Popup Menu in top-right
                            Positioned(
                              top: 6,
                              right: 6,
                              child: PopupMenuButton<String>(
                                icon: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                                    ],
                                  ),
                                  child: Icon(Icons.more_vert, size: 18, color: Colors.grey[800]),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                onSelected: (value) {
                                  if (value == 'download') {
                                    _downloadFile(id, name);
                                  } else if (value == 'move') {
                                    _showMoveDialog(item);
                                  } else if (value == 'delete') {
                                    _deleteItem(id, name, isFolder);
                                  } else if (value == 'share') {
                                    _shareItem(id, name);
                                  } else if (value == 'star') {
                                    _toggleStar(id);
                                  } else if (value == 'restore') {
                                    _restoreItem(id, name);
                                  } else if (value == 'permanent_delete') {
                                    _deletePermanently(id, name);
                                  }
                                },
                                itemBuilder: (context) {
                                  if (_currentSection == FileSection.trash) {
                                    return [
                                      const PopupMenuItem(
                                        value: 'restore',
                                        child: Row(
                                          children: [
                                            Icon(Icons.restore, size: 18, color: Colors.green),
                                            SizedBox(width: 8),
                                            Text('Restaurar', style: TextStyle(color: Colors.green)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'permanent_delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_forever, size: 18, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Eliminar definitivamente', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ];
                                  }
                                  if (!isOwner) {
                                    return [
                                      PopupMenuItem(
                                        value: 'star',
                                        child: Row(
                                          children: [
                                            Icon(
                                              item['isStarred'] == true ? Icons.star_outline : Icons.star,
                                              size: 18,
                                              color: Colors.amber[700],
                                            ),
                                            const SizedBox(width: 8),
                                            Text(item['isStarred'] == true ? 'Quitar de destacados' : 'Destacar'),
                                          ],
                                        ),
                                      ),
                                      if (!isFolder)
                                        const PopupMenuItem(
                                          value: 'download',
                                          child: Row(
                                            children: [
                                              Icon(Icons.download, size: 18),
                                              SizedBox(width: 8),
                                              Text('Descargar'),
                                            ],
                                          ),
                                        ),
                                    ];
                                  }
                                  return [
                                    PopupMenuItem(
                                      value: 'star',
                                      child: Row(
                                        children: [
                                          Icon(
                                            item['isStarred'] == true ? Icons.star_outline : Icons.star,
                                            size: 18,
                                            color: Colors.amber[700],
                                          ),
                                          const SizedBox(width: 8),
                                          Text(item['isStarred'] == true ? 'Quitar de destacados' : 'Destacar'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'share',
                                      child: Row(
                                        children: [
                                          Icon(Icons.share_outlined, size: 18, color: Colors.blue),
                                          SizedBox(width: 8),
                                          Text('Compartir', style: TextStyle(color: Colors.blue)),
                                        ],
                                      ),
                                    ),
                                    if (!isFolder)
                                      const PopupMenuItem(
                                        value: 'download',
                                        child: Row(
                                          children: [
                                            Icon(Icons.download, size: 18),
                                            SizedBox(width: 8),
                                            Text('Descargar'),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'move',
                                      child: Row(
                                        children: [
                                          Icon(Icons.drive_file_move_outlined, size: 18, color: Color(0xFF4F46E5)),
                                          SizedBox(width: 8),
                                          Text('Mover...', style: TextStyle(color: Color(0xFF4F46E5))),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Mover a papelera', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ];
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Details Area
                    Padding(
                      padding: EdgeInsets.all(isNarrow ? 8.0 : 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[900],
                              fontWeight: FontWeight.w600,
                              fontSize: isNarrow ? 12 : 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isFolder ? 'Carpeta' : (size != null ? _formatBytes(size) : 'Archivo'),
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: isNarrow ? 10 : 12,
                                ),
                              ),
                              if (item['ownerId'] != null && item['ownerId'] != widget.username)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'De: ${item['ownerId']}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF4F46E5),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else if (_currentSection == FileSection.trash)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red[50],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Papelera',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            Widget finalCardWidget = cardWidget;

            if (isFolder && isOwner && _currentSection != FileSection.trash) {
              finalCardWidget = DragTarget<Map<String, dynamic>>(
                onWillAcceptWithDetails: (details) {
                  final dragged = details.data;
                  return dragged['id'].toString() != id;
                },
                onAcceptWithDetails: (details) {
                  final dragged = details.data;
                  _moveItem(dragged['id'].toString(), dragged['name'] ?? '', id, name);
                },
                builder: (context, candidateData, rejectedData) {
                  final isHovered = candidateData.isNotEmpty;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: isHovered
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF4F46E5), width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4F46E5).withOpacity(0.35),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          )
                        : null,
                    child: cardWidget,
                  );
                },
              );
            }

            if (isOwner && _currentSection != FileSection.trash) {
              return Draggable<Map<String, dynamic>>(
                data: item,
                feedback: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 170,
                    height: 110,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF818CF8), width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isFolder ? Icons.folder : _getFileIcon(mimeType, name),
                          size: 36,
                          color: const Color(0xFF818CF8),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: finalCardWidget,
                ),
                child: finalCardWidget,
              );
            }

            return finalCardWidget;
          },
        );
      },
    );
  }

  Widget _buildSidebarItem(
    IconData icon,
    String title,
    bool isSelected,
    VoidCallback onTap, {
    bool isDrawer = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEEF2FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          size: 20,
          color: isSelected ? const Color(0xFF4F46E5) : Colors.grey[600],
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFF4F46E5) : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        onTap: () {
          if (isDrawer && mounted) {
            Navigator.of(context).pop();
          }
          onTap();
        },
      ),
    );
  }

  Widget _buildNavigationList({
    required double progress,
    required String usedFormatted,
    required String limitFormatted,
    bool isDrawer = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDrawer) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1B4B),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF4F46E5),
                  child: Text(
                    widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.username,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'FileSync Enterprise',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDrawer ? 12 : 0),
          child: Column(
            children: [
              _buildSidebarItem(Icons.storage, 'Mi Unidad', _currentSection == FileSection.myDrive, () => _switchSection(FileSection.myDrive), isDrawer: isDrawer),
              _buildSidebarItem(Icons.group_outlined, 'Compartidos conmigo', _currentSection == FileSection.sharedWithMe, () => _switchSection(FileSection.sharedWithMe), isDrawer: isDrawer),
              _buildSidebarItem(Icons.access_time, 'Recientes', _currentSection == FileSection.recent, () => _switchSection(FileSection.recent), isDrawer: isDrawer),
              _buildSidebarItem(Icons.star_outline, 'Destacados', _currentSection == FileSection.starred, () => _switchSection(FileSection.starred), isDrawer: isDrawer),
              _buildSidebarItem(Icons.delete_outline, 'Papelera', _currentSection == FileSection.trash, () => _switchSection(FileSection.trash), isDrawer: isDrawer),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 8),
              _buildSidebarItem(Icons.sync_alt, 'Sincronización (Sync)', _currentSection == FileSection.sync, () => _switchSection(FileSection.sync), isDrawer: isDrawer),
              _buildSidebarItem(Icons.rocket_launch_rounded, 'Computación de Alto Rendimiento', _currentSection == FileSection.hpc, () => _switchSection(FileSection.hpc), isDrawer: isDrawer),
            ],
          ),
        ),
        if (!isDrawer) const Spacer(),
        if (isDrawer) const SizedBox(height: 16),
        Padding(
          padding: EdgeInsets.all(isDrawer ? 12 : 0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_sync, size: 18, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Text(
                      'Almacenamiento',
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$usedFormatted de $limitFormatted usados',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MoveFileDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final String token;
  final void Function(String? targetParentId, String targetFolderName) onMoved;

  const MoveFileDialog({
    super.key,
    required this.item,
    required this.token,
    required this.onMoved,
  });

  @override
  State<MoveFileDialog> createState() => _MoveFileDialogState();
}

class _MoveFileDialogState extends State<MoveFileDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _folders = [];
  final List<Map<String, String?>> _folderStack = [
    {'id': null, 'name': 'Mi Unidad'}
  ];

  @override
  void initState() {
    super.initState();
    _fetchFolders();
  }

  String? get _currentBrowseId => _folderStack.last['id'];
  String get _currentBrowseName => _folderStack.last['name']!;

  Future<void> _fetchFolders() async {
    setState(() => _isLoading = true);
    try {
      String url = '${ApiConfig.streamingUrl}/api/files';
      if (_currentBrowseId != null) {
        url += '?parentId=${Uri.encodeComponent(_currentBrowseId!)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['items'] ?? [];
        final movingItemId = widget.item['id'].toString();

        setState(() {
          _folders = items
              .where((i) => i['kind'] == 'folder' && i['id'].toString() != movingItemId)
              .map((i) => Map<String, dynamic>.from(i))
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _enterFolder(String id, String name) {
    setState(() {
      _folderStack.add({'id': id, 'name': name});
    });
    _fetchFolders();
  }

  void _goUp() {
    if (_folderStack.length <= 1) return;
    setState(() {
      _folderStack.removeLast();
    });
    _fetchFolders();
  }

  @override
  Widget build(BuildContext context) {
    final currentParentOfItem = widget.item['parentId'];
    final isAlreadyHere = _currentBrowseId == currentParentOfItem;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.drive_file_move_outlined, color: Color(0xFF4F46E5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mover "${widget.item['name']}"',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current Location Path
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_open, size: 18, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _folderStack.map((f) => f['name']).join(' > '),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_folderStack.length > 1)
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 18, color: Color(0xFF4F46E5)),
                      tooltip: 'Subir un nivel',
                      onPressed: _isLoading ? null : _goUp,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Selecciona la carpeta de destino:',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[200]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)))
                    : _folders.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_off_outlined, size: 36, color: Colors.grey[400]),
                                const SizedBox(height: 6),
                                Text(
                                  'No hay más carpetas en esta ubicación',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _folders.length,
                            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[100]),
                            itemBuilder: (context, index) {
                              final f = _folders[index];
                              return ListTile(
                                leading: const Icon(Icons.folder, color: Color(0xFF4F46E5), size: 22),
                                title: Text(f['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                                dense: true,
                                onTap: () => _enterFolder(f['id'].toString(), f['name']),
                              );
                            },
                          ),
              ),
            ),
            if (isAlreadyHere) ...[
              const SizedBox(height: 8),
              Text(
                'El elemento ya se encuentra en esta ubicación.',
                style: TextStyle(fontSize: 11, color: Colors.amber[800], fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300],
          ),
          onPressed: isAlreadyHere
              ? null
              : () {
                  Navigator.pop(context);
                  widget.onMoved(_currentBrowseId, _currentBrowseName);
                },
          child: Text(isAlreadyHere ? 'Ubicación actual' : 'Mover aquí'),
        ),
      ],
    );
  }
}
