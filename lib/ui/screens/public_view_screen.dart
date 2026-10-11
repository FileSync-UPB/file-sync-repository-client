import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import 'preview_screen.dart';

class PublicViewScreen extends StatefulWidget {
  final String fileId;

  const PublicViewScreen({super.key, required this.fileId});

  @override
  State<PublicViewScreen> createState() => _PublicViewScreenState();
}

class _PublicViewScreenState extends State<PublicViewScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _fileData;

  @override
  void initState() {
    super.initState();
    _fetchPublicFile();
  }

  Future<void> _fetchPublicFile() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.streamingUrl}/api/files/files/${widget.fileId}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _fileData = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'El archivo no existe o no tiene permisos de visualización pública.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error al conectar con el servidor: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF6366F1)),
              SizedBox(height: 16),
              Text(
                'Cargando visualización pública...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          title: const Text('FileSync Enterprise - Acceso Público'),
          backgroundColor: const Color(0xFF1E293B),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 450),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Acceso Restringido',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // Navigate to root to login
                    Navigator.pushReplacementNamed(context, '/');
                  },
                  child: const Text('Ir al Inicio de Sesión'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PreviewScreen(
      id: widget.fileId,
      name: _fileData!['name'] ?? 'Archivo Público',
      token: '', // Empty token indicates public guest access
      mimeType: _fileData!['mimeType'],
    );
  }
}
