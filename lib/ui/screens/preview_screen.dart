import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';
import '../../config/api_config.dart';
import '../../platform/platform_utils.dart';

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

  // Video Controller
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoError = false;
  String? _videoErrorMessage;
  bool _showControls = true;

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

    if (_isVideo) {
      _initVideoPlayer();
    }
  }

  Future<void> _initVideoPlayer() async {
    try {
      final headers = widget.token.isNotEmpty ? {'Authorization': 'Bearer ${widget.token}'} : const <String, String>{};
      final controller = await createVideoPlayerController(
        _url,
        headers,
        fileName: widget.name,
        fileId: widget.id,
      );

      if (!mounted) {
        controller.dispose();
        return;
      }

      _videoController = controller;
      await _videoController!.initialize();

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _isVideoError = false;
        });
        _videoController!.play();
      }

      _videoController!.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (err) {
      if (mounted) {
        setState(() {
          _isVideoError = true;
          _videoErrorMessage = err.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _downloadFile() {
    openUrlOrDownload(_url, downloadName: widget.name);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text(widget.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_isPdf)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Abrir PDF en pestaña',
              onPressed: () => openUrlOrDownload(_url, downloadName: widget.name),
            ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Descargar archivo',
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
    // 1. Imagen
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

    // 2. Video (Nativo en Pantalla para Android, Windows y Web)
    if (_isVideo) {
      if (_isVideoError) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              const Text(
                'No se pudo inicializar la reproducción directa de este video.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _videoErrorMessage ?? 'Verifica la conexión a la red UPB o los códecs del contenedor.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  clearCachedVideo(widget.id, widget.name);
                  setState(() {
                    _isVideoError = false;
                    _isVideoInitialized = false;
                  });
                  _videoController?.dispose();
                  _videoController = null;
                  _initVideoPlayer();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar Reproducción'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }

      if (!_isVideoInitialized || _videoController == null) {
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF4F46E5)),
            SizedBox(height: 16),
            Text('Cargando flujo de video...', style: TextStyle(color: Colors.white)),
          ],
        );
      }

      return GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(_videoController!),
                if (_showControls) ...[
                  // Play/Pause center overlay
                  Center(
                    child: IconButton(
                      iconSize: 64,
                      icon: Icon(
                        _videoController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      onPressed: () {
                        setState(() {
                          _videoController!.value.isPlaying
                              ? _videoController!.pause()
                              : _videoController!.play();
                        });
                      },
                    ),
                  ),
                  // Bottom control bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoProgressIndicator(
                          _videoController!,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFF4F46E5),
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_formatDuration(_videoController!.value.position)} / ${_formatDuration(_videoController!.value.duration)}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            IconButton(
                              icon: Icon(
                                _videoController!.value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _videoController!.setVolume(_videoController!.value.volume == 0 ? 1.0 : 0.0);
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // 3. Documento PDF (Visor Nativo In-App sin Redirección)
    if (_isPdf) {
      return Container(
        color: const Color(0xFF1E293B),
        width: double.infinity,
        height: double.infinity,
        child: SfPdfViewer.network(
          _url,
          headers: kIsWeb ? null : (widget.token.isNotEmpty ? {'Authorization': 'Bearer ${widget.token}'} : null),
          canShowScrollHead: true,
          canShowScrollStatus: true,
          enableDoubleTapZooming: true,
          enableTextSelection: true,
          onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error cargando PDF: ${details.description}'),
                backgroundColor: Colors.red[700],
              ),
            );
          },
        ),
      );
    }

    // 4. Tipo de archivo no visualizable directamente
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file, size: 64, color: Colors.indigoAccent),
                const SizedBox(height: 16),
                Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Este tipo de archivo no dispone de visualización directa integrada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _downloadFile,
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar para abrir localmente'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
