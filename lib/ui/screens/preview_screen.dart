import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../../config/api_config.dart';

class PreviewScreen extends StatefulWidget {
  final String id;
  final String name;
  final String token;
  final String? mimeType;

  const PreviewScreen({
    super.key,
    required this.id,
    required this.name,
    required this.token,
    required this.mimeType,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  bool _isVideo = false;
  bool _isImage = false;
  bool _isPdf = false;
  late String _url;

  @override
  void initState() {
    super.initState();
    _url = widget.token.isEmpty
        ? '${ApiConfig.streamingUrl}/api/files/files/${widget.id}/content'
        : '${ApiConfig.streamingUrl}/api/files/files/${widget.id}/content?token=${Uri.encodeComponent(widget.token)}';

    final ext = widget.name.split('.').last.toLowerCase();
    _isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].contains(ext) ||
        (widget.mimeType?.startsWith('image/') ?? false);
    _isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext) ||
        (widget.mimeType?.startsWith('video/') ?? false);
    _isPdf = ext == 'pdf' || widget.mimeType == 'application/pdf';

    if (_isPdf) {
      final viewId = 'pdf-iframe-${widget.id}';
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int viewId) => html.IFrameElement()
          ..src = _url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%',
      );
    }

    if (_isVideo) {
      final viewId = 'video-player-${widget.id}';
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int viewId) => html.VideoElement()
          ..src = _url
          ..controls = true
          ..autoplay = false
          ..preload = 'auto'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = 'black',
      );
    }
  }

  void _downloadFile() {
    html.AnchorElement(href: _url)
      ..setAttribute('download', widget.name)
      ..click();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Descargar',
            onPressed: _downloadFile,
          ),
        ],
      ),
      body: Center(
        child: _buildPreview(),
      ),
    );
  }

  Widget _buildPreview() {
    if (_isImage) {
      return InteractiveViewer(
        child: Image.network(
          _url,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const CircularProgressIndicator(color: Colors.white);
          },
          errorBuilder: (context, error, stackTrace) {
            return const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: Colors.white54, size: 64),
                SizedBox(height: 16),
                Text('Error al cargar la imagen', style: TextStyle(color: Colors.white)),
              ],
            );
          },
        ),
      );
    }

    if (_isVideo) {
      return Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: HtmlElementView(viewType: 'video-player-${widget.id}'),
        ),
      );
    }

    if (_isPdf) {
      return HtmlElementView(viewType: 'pdf-iframe-${widget.id}');
    }

    // Default for unsupported types like docs
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.insert_drive_file, color: Colors.white54, size: 80),
        const SizedBox(height: 16),
        const Text(
          'Previsualización no disponible',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _downloadFile,
          icon: const Icon(Icons.download),
          label: const Text('Descargar Archivo'),
        ),
      ],
    );
  }
}
