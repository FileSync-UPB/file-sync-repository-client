import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
  String _shareType = 'interno'; // 'interno' or 'publico'
  final List<String> _selectedUsers = [];
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;

  final List<String> _availableUsers = [
    'admin',
    'investigador1',
    'empleado1',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
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

  Future<void> _submitShare() async {
    if (_shareType == 'interno' && _selectedUsers.isEmpty) {
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
      final uri = Uri.parse('http://localhost:3000/api/files/${widget.fileId}/permissions');

      if (_shareType == 'publico') {
        final response = await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'userId': 'public', 'role': 'viewer'}),
        );

        if (!mounted) return;

        if (response.statusCode == 200) {
          Navigator.pop(context);
          widget.onShared();
          _showPublicLinkDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${response.body}'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      } else {
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

        Navigator.pop(context);
        widget.onShared();

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
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo compartir con: ${failedUsers.join(', ')}'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
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

  void _showPublicLinkDialog() {
    final url = 'http://localhost:5000/?share=${widget.fileId}';
    showDialog(
      context: context,
      builder: (ctx2) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.public, color: Color(0xFF818CF8)),
            SizedBox(width: 10),
            Text(
              'Enlace Público Generado',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Comparte este enlace directo para que cualquier persona pueda visualizar el archivo en la plataforma sin requerir inicio de sesión:',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      url,
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: Color(0xFF94A3B8)),
                    tooltip: 'Copiar enlace',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
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
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx2),
            child: const Text('Aceptar'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.share_outlined, color: Color(0xFF818CF8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Compartir "${widget.fileName}"',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tipo de acceso:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            // Segmented selector for clear contrast and modern UI
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'interno',
                    label: Text('Interno'),
                    icon: Icon(Icons.people_outline, size: 18),
                  ),
                  ButtonSegment(
                    value: 'publico',
                    label: Text('Público'),
                    icon: Icon(Icons.public, size: 18),
                  ),
                ],
                selected: {_shareType},
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFF4F46E5);
                    }
                    return const Color(0xFF0F172A);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return const Color(0xFF94A3B8);
                  }),
                  side: WidgetStateProperty.all(const BorderSide(color: Color(0xFF334155))),
                ),
                onSelectionChanged: (newSelection) {
                  setState(() => _shareType = newSelection.first);
                },
              ),
            ),
            const SizedBox(height: 20),
            if (_shareType == 'interno') ...[
              const Text(
                'Usuarios con acceso:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),

              // Chip tags of selected users
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
                const SizedBox(height: 12),
              ],

              // Autocomplete input that supports typing, Enter, and suggestions
              RawAutocomplete<String>(
                textEditingController: _inputController,
                focusNode: _focusNode,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _availableUsers.where((u) => !_selectedUsers.contains(u));
                  }
                  return _availableUsers.where((u) =>
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
                        tooltip: 'Agregar usuario',
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
                        constraints: const BoxConstraints(maxHeight: 200),
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
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF64748B)),
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
                'Presiona Enter o haz clic en "+" para añadir cada usuario a la lista.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            ] else ...[
              // High-contrast, elegant public access card (No ugly orange!)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.public, color: Color(0xFF818CF8), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Acceso Público Directo',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Cualquier persona que reciba el enlace generado podrá abrir y previsualizar este archivo directamente en la plataforma sin tener que iniciar sesión ni forzar la descarga.',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _isLoading ? null : _submitShare,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(_shareType == 'publico' ? 'Generar Enlace' : 'Guardar y Compartir'),
        ),
      ],
    );
  }
}
