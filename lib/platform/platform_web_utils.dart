import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

void openUrlOrDownload(String url, {String? downloadName}) {
  final anchor = html.AnchorElement(href: url);
  if (downloadName != null && downloadName.isNotEmpty) {
    anchor.setAttribute('download', downloadName);
  }
  anchor.click();
}

void pickFileWeb({required Function(String name, int size, List<int> bytes) onFileSelected}) {
  final uploadInput = html.FileUploadInputElement();
  uploadInput.multiple = false;
  uploadInput.click();

  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) return;
    final html.File file = files.first;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    reader.onLoadEnd.listen((e) {
      if (reader.result != null) {
        final bytes = (reader.result as List<dynamic>).cast<int>();
        onFileSelected(file.name, file.size, bytes);
      }
    });
  });
}

void registerHtmlPreview(String viewId, String url, {required bool isVideo}) {
  // ignore: undefined_prefixed_name
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int viewId) {
      if (isVideo) {
        return html.VideoElement()
          ..src = url
          ..controls = true
          ..autoplay = false
          ..preload = 'auto'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = 'black';
      } else {
        return html.IFrameElement()
          ..src = url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
      }
    },
  );
}

Widget buildHtmlPlatformView(String viewId) {
  return HtmlElementView(viewType: viewId);
}

Future<String?> pickNativeDirectory() async {
  return null;
}

Future<Map<String, dynamic>> runNativeSyncClient({
  required String token,
  required String deviceId,
  required String syncFolder,
  String? serverAddr,
}) async {
  return {'success': false, 'message': 'No soportado en web'};
}

Future<List<Map<String, dynamic>>> listLocalDirectoryFiles(String dirPath) async {
  return [];
}

Future<dynamic> readLocalFile(String filePath) async {
  return null;
}

Future<bool> saveLocalFile(String dirPath, String fileName, List<int> bytes) async {
  openUrlOrDownload('data:application/octet-stream;base64,${html.window.btoa(String.fromCharCodes(bytes))}', downloadName: fileName);
  return true;
}

Future<bool> requestStoragePermissions() async {
  return true;
}
