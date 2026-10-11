import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';

class ShareDialogInner extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String token;
  final VoidCallback onShared;

  const ShareDialogInner({
    super.key,
    required this.fileId,
    required this.fileName,
    required this.token,
    required this.onShared,
  });

  @override
  State<ShareDialogInner> createState() => _ShareDialogInnerState();
}

class _ShareDialogInnerState extends State<ShareDialogInner> {
  final List<String> _selectedUsers = [];
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  bool _isLoadingPermissions = true;

  String? _ownerId;
  List<Map<String, dynamic>> _permissions = [];

  final List<String> _availableUsers = [
    'admin',
    'investigador1',
    'empleado1',
  ];

  @override
  void initState() {
    super.initState();
    _fetchPermissions();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchPermissions() async {
    setState(() => _isLoadingPermissions = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.streamingUrl}/api/files/${widget.fileId}/permissions'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawPerms = (data['permissions'] as List? ?? []);
        setState(() {
          _ownerId = data['ownerId']?.toString();
          _permissions = rawPerms.map((p) => Map<String, dynamic>.from(p)).toList();
        });
      }
    } catch (_) {
      // Ignorar error transitorio de red
    } finally {
      if (mounted) {
        setState(() => _isLoadingPermissions = false);
      }
    }
  }

  bool get _isPublicActive {
    return _permissions.any((p) => p['userId'] == 'public');
  }

  void _addUser(String user) {
    final clean = user.trim();
    if (clean.isEmpty) return;
    if (!_selectedUsers.contains(clean)) {
      setState(() {
        _selectedUsers.add(clean);
      });
    }
    _inputController.clear();
    _focusNode.requestFocus();
  }

  void _removeUser(String user) {
    setState(() {
      _selectedUsers.remove(user);
    });
  }

  Future<void> _togglePublicAccess(bool enable) async {
    setState(() => _isLoading = true);
    try {
      if (enable) {
        // Habilitar enlace público
        final response = await http.post(
          Uri.parse('${ApiConfig.streamingUrl}/api/files/${widget.fileId}/permissions'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'userId': 'public', 'role': 'viewer'}),
        );

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Enlace público habilitado exitosamente.'),
                backgroundColor: Color(0xFF4F46E5),
              ),
            );
          }
          await _fetchPermissions();
          widget.onShared();
        }
      } else {
        // Deshabilitar/Cerrar enlace público
        final response = await http.delete(
          Uri.parse('${ApiConfig.streamingUrl}/api/files/${widget.fileId}/permissions/public'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
          },
        );

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Enlace público cerrado. Ya no es accesible públicamente.'),
                backgroundColor: Colors.amber,
              ),
            );
          }
          await _fetchPermissions();
          widget.onShared();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al modificar enlace público: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _revokeUserAccess(String targetUserId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Revocar acceso', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Deseas quitarle los permisos a "$targetUserId"? Ya no podrá ver este elemento ni sus contenidos.',
          style: const TextStyle(color: Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar permiso'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.streamingUrl}/api/files/${widget.fileId}/permissions/$targetUserId'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Permiso revocado a "$targetUserId".'),
              backgroundColor: Colors.green[700],
            ),
          );
        }
        await _fetchPermissions();
        widget.onShared();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al revocar permiso: ${response.body}'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAddUsers() async {
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe o selecciona al menos un usuario para compartir.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final uri = Uri.parse('${ApiConfig.streamingUrl}/api/files/${widget.fileId}/permissions');
      final List<String> failedUsers = [];

      for (final user in _selectedUsers) {
        final response = await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'userId': user, 'role': 'viewer'}),
        );

        if (response.statusCode != 200) {
          failedUsers.add(user);
        }
      }

      if (!mounted) return;

      if (failedUsers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedUsers.length == 1
                  ? 'Compartido exitosamente con ${_selectedUsers.first}.'
                  : 'Compartido exitosamente con ${_selectedUsers.length} usuarios.',
            ),
            backgroundColor: Colors.green[700],
          ),
        );
        setState(() {
          _selectedUsers.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo compartir con: ${failedUsers.join(', ')}'),
            backgroundColor: Colors.red[700],
          ),
        );
      }

      await _fetchPermissions();
      widget.onShared();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al compartir: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final publicUrl = '${ApiConfig.webUrl}/?share=${widget.fileId}';
    final userPermissions = _permissions.where((p) => p['userId'] != 'public').toList();

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.share_outlined, color: Color(0xFF818CF8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Compartir y accesos: "${widget.fileName}"',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -----------------------------------------------------------------
              // 1. SECCIÓN DE ENLACE PÚBLICO (Cerrar o Abrir)
              // -----------------------------------------------------------------
              const Text(
                'Acceso Público General',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isPublicActive ? const Color(0xFF6366F1) : const Color(0xFF334155),
                    width: _isPublicActive ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _isPublicActive
                                ? const Color(0xFF4F46E5).withValues(alpha: 0.25)
                                : const Color(0xFF334155).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _isPublicActive ? Icons.public : Icons.public_off,
                            color: _isPublicActive ? const Color(0xFF818CF8) : const Color(0xFF94A3B8),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _isPublicActive ? 'Enlace Público Activo' : 'Enlace Público Desactivado',
                                    style: TextStyle(
                                      color: _isPublicActive ? Colors.white : const Color(0xFFCBD5E1),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _isPublicActive ? Colors.green[900]!.withOpacity(0.4) : Colors.grey[800],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _isPublicActive ? 'Público' : 'Privado',
                                      style: TextStyle(
                                        color: _isPublicActive ? Colors.green[400] : Colors.grey[400],
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isPublicActive
                                    ? 'Cualquier persona con el enlace puede visualizar este elemento y sus subelementos.'
                                    : 'Solo las personas con permiso explícito pueden acceder a este elemento.',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_isPublicActive) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                publicUrl,
                                style: const TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18, color: Color(0xFF94A3B8)),
                              tooltip: 'Copiar enlace público',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: publicUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('¡Enlace copiado al portapapeles!'),
                                    backgroundColor: Color(0xFF4F46E5),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[400],
                            side: BorderSide(color: Colors.red[400]!.withOpacity(0.6)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isLoading ? null : () => _togglePublicAccess(false),
                          icon: const Icon(Icons.link_off, size: 16),
                          label: const Text('Cerrar enlace público', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isLoading ? null : () => _togglePublicAccess(true),
                          icon: const Icon(Icons.add_link, size: 16),
                          label: const Text('Crear enlace público', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // -----------------------------------------------------------------
              // 2. SECCIÓN DE PERSONAS CON ACCESO (Y Quitar Permisos)
              // -----------------------------------------------------------------
              const Text(
                'Personas con Acceso',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: _isLoadingPermissions
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1))),
                      )
                    : Column(
                        children: [
                          // Propietario
                          ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(0xFF4F46E5),
                              child: Text(
                                (_ownerId ?? 'P').substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  _ownerId ?? 'Propietario',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF312E81),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Propietario', style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 10)),
                                ),
                              ],
                            ),
                            subtitle: const Text('Tiene control total sobre este archivo', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                            dense: true,
                          ),
                          if (userPermissions.isNotEmpty) const Divider(color: Color(0xFF1E293B), height: 1),
                          // Lista de usuarios con acceso compartido
                          ...userPermissions.map((perm) {
                            final uId = perm['userId']?.toString() ?? '';
                            final role = perm['role']?.toString() ?? 'viewer';
                            return Column(
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF334155),
                                    child: Text(
                                      uId.isNotEmpty ? uId.substring(0, 1).toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  title: Text(
                                    uId,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    role == 'editor' ? 'Editor' : 'Lector',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  ),
                                  trailing: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red[400],
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    ),
                                    icon: const Icon(Icons.person_remove_outlined, size: 16),
                                    label: const Text('Quitar permiso', style: TextStyle(fontSize: 12)),
                                    onPressed: _isLoading ? null : () => _revokeUserAccess(uId),
                                  ),
                                  dense: true,
                                ),
                                const Divider(color: Color(0xFF1E293B), height: 1),
                              ],
                            );
                          }),
                        ],
                      ),
              ),

              const SizedBox(height: 20),

              // -----------------------------------------------------------------
              // 3. SECCIÓN DE AÑADIR NUEVOS USUARIOS
              // -----------------------------------------------------------------
              const Text(
                'Compartir con otros usuarios',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),

              if (_selectedUsers.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedUsers.map((user) {
                    return InputChip(
                      avatar: const CircleAvatar(
                        backgroundColor: Color(0xFF4F46E5),
                        child: Icon(Icons.person, size: 14, color: Colors.white),
                      ),
                      label: Text(
                        user,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16, color: Color(0xFFCBD5E1)),
                      onDeleted: () => _removeUser(user),
                      backgroundColor: const Color(0xFF312E81).withValues(alpha: 0.5),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
              ],

              RawAutocomplete<String>(
                textEditingController: _inputController,
                focusNode: _focusNode,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final activeUsers = userPermissions.map((p) => p['userId']).toSet();
                  final candidates = _availableUsers.where((u) => u != _ownerId && !activeUsers.contains(u));
                  if (textEditingValue.text.isEmpty) {
                    return candidates.where((u) => !_selectedUsers.contains(u));
                  }
                  return candidates.where((u) =>
                      !_selectedUsers.contains(u) &&
                      u.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (String selection) {
                  _addUser(selection);
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Escribe un usuario y presiona Enter...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      prefixIcon: const Icon(Icons.person_add_outlined, color: Color(0xFF818CF8)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF6366F1)),
                        tooltip: 'Añadir usuario a la selección',
                        onPressed: () {
                          if (controller.text.trim().isNotEmpty) {
                            _addUser(controller.text);
                          }
                        },
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                      ),
                    ),
                    onSubmitted: (value) {
                      _addUser(value);
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8,
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 320,
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final String option = options.elementAt(index);
                            return ListTile(
                              leading: const CircleAvatar(
                                radius: 14,
                                backgroundColor: Color(0xFF1E293B),
                                child: Icon(Icons.person_outline, size: 16, color: Color(0xFF818CF8)),
                              ),
                              title: Text(
                                option,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              dense: true,
                              hoverColor: const Color(0xFF1E293B),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              const Text(
                'Presiona Enter o haz clic en "+" para agregar usuarios.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),

              if (_selectedUsers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isLoading ? null : _submitAddUsers,
                    icon: _isLoading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 16),
                    label: const Text('Otorgar acceso a seleccionados', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF334155),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}
