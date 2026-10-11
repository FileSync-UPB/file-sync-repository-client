import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'preview_screen.dart';
import 'share_dialog_inner.dart';

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
        Uri.parse('http://localhost:3000/api/files/usage'),
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var urlStr = 'http://localhost:3000/api/files';
      if (_currentParentId != null) {
        urlStr += '?parentId=${Uri.encodeComponent(_currentParentId!)}';
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
        Uri.parse('http://localhost:3000/api/files/folders'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Carpeta "$name" creada exitosamente.'),
            backgroundColor: Colors.green[700],
          ),
        );
        _fetchFiles();
      } else {
        final err = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${err['error'] ?? 'No se pudo crear la carpeta'}'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de red al crear carpeta: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  void _pickAndUploadFile() {
    final uploadInput = html.FileUploadInputElement();
    uploadInput.click();

    uploadInput.onChange.listen((e) async {
      final files = uploadInput.files;
      if (files == null || files.isEmpty) return;

      final html.File file = files.first;

      setState(() {
        _isUploading = true;
      });

      try {
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        
        await reader.onLoad.first;
        final bytes = reader.result as List<int>;

        final uri = Uri.parse('http://localhost:3000/api/files/upload');
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer ${widget.token}';

        if (_currentParentId != null) {
          request.fields['parentId'] = _currentParentId!;
        }

        final multipartFile = http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        );
        request.files.add(multipartFile);

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Archivo "${file.name}" subido con éxito.'),
              backgroundColor: Colors.green[700],
            ),
          );
          _fetchFiles();
          _fetchUsage();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al subir (${response.statusCode}): ${response.body}'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de subida: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isUploading = false;
          });
        }
      }
    });
  }

  Future<void> _deleteItem(String id, String name, bool isFolder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Estás seguro de que deseas enviar "${name}" a la papelera?',
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
          Uri.parse('http://localhost:3000/api/files/files/$id'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$name" movido a la papelera.'),
              backgroundColor: Colors.green[700],
            ),
          );
          _fetchFiles();
          _fetchUsage();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: ${response.statusCode}'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  void _downloadFile(String id, String name) {
    final downloadUrl =
        'http://localhost:3000/api/files/files/$id/content?token=${Uri.encodeComponent(widget.token)}';
    html.AnchorElement(href: downloadUrl)
      ..setAttribute('download', name)
      ..click();
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

  void _navigateToBreadcrumb(int index) {
    if (index == _breadcrumbs.length - 1) return;
    setState(() {
      final target = _breadcrumbs[index];
      _currentParentId = target['id'];
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
    });
    _fetchFiles();
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

  @override
  Widget build(BuildContext context) {
    final usedFormatted = _formatBytes(_usedBytes);
    final limitFormatted = _formatBytes(_limitBytes);
    final progress = _limitBytes > 0
        ? (_usedBytes / _limitBytes).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.cloud, color: Color(0xFF4F46E5), size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'FileSync',
              style: TextStyle(
                color: Colors.grey[900],
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
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
          ),
          IconButton(
            tooltip: 'Cerrar Sesión',
            icon: Icon(Icons.logout, color: Colors.grey[600]),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/');
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSidebarItem(Icons.storage, 'Mi Unidad', true),
                _buildSidebarItem(Icons.group_outlined, 'Compartidos conmigo', false),
                _buildSidebarItem(Icons.access_time, 'Recientes', false),
                _buildSidebarItem(Icons.star_outline, 'Destacados', false),
                _buildSidebarItem(Icons.delete_outline, 'Papelera', false),
                const Spacer(),
                // Storage Bar
                Container(
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
              ],
            ),
          ),
          // Main Workspace
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header & Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Breadcrumbs navigation
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(_breadcrumbs.length, (index) {
                              final b = _breadcrumbs[index];
                              final isLast = index == _breadcrumbs.length - 1;
                              return Row(
                                children: [
                                  InkWell(
                                    onTap: () => _navigateToBreadcrumb(index),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      child: Text(
                                        b['name']!,
                                        style: TextStyle(
                                          fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
                                          fontSize: isLast ? 20 : 18,
                                          color: isLast ? Colors.grey[900] : const Color(0xFF4F46E5),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Actions
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Actualizar',
                            icon: const Icon(Icons.refresh, color: Colors.grey),
                            onPressed: _isLoading ? null : () {
                              _fetchFiles();
                              _fetchUsage();
                            },
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _isLoading || _isUploading ? null : _createFolderDialog,
                            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                            label: const Text('Nueva Carpeta'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[800],
                              side: BorderSide(color: Colors.grey[300]!),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _isLoading || _isUploading ? null : _pickAndUploadFile,
                            icon: _isUploading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_outlined, size: 18, color: Colors.white),
                            label: Text(
                              _isUploading ? 'Subiendo...' : 'Subir Archivo',
                              style: const TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Content grid / list
                  Expanded(
                    child: _buildContent(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
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
              child: Icon(Icons.folder_open, size: 56, color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),
            Text(
              'Esta carpeta está vacía',
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Crea una nueva carpeta o sube archivos para comenzar',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute columns based on width
        int crossAxisCount = (constraints.maxWidth / 220).floor().clamp(2, 6);

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final isFolder = item['kind'] == 'folder';
            final id = item['id'].toString();
            final name = item['name'] ?? 'Sin nombre';
            final size = item['size'];
            final mimeType = item['mimeType'];

            return Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
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
                                    Uri.parse('http://localhost:3000/api/files/files/$id/content'),
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
                                        errorBuilder: (_, __, ___) => Icon(
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
                                  size: 64,
                                  color: isFolder
                                      ? const Color(0xFF4F46E5)
                                      : _getFileColor(mimeType, name),
                                ),
                              ),
                            Positioned(
                              top: 8,
                              right: 8,
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
                                  child: Icon(Icons.more_vert, size: 20, color: Colors.grey[800]),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                onSelected: (value) {
                                  if (value == 'download') {
                                    _downloadFile(id, name);
                                  } else if (value == 'delete') {
                                    _deleteItem(id, name, isFolder);
                                  } else if (value == 'share') {
                                    _shareItem(id, name);
                                  }
                                },
                                itemBuilder: (context) => [
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
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Eliminar', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Details Area
                    Padding(
                      padding: const EdgeInsets.all(12.0),
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
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isFolder ? 'Carpeta' : (size != null ? _formatBytes(size) : 'Archivo'),
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, bool isSelected) {
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
        onTap: () {},
      ),
    );
  }
}
