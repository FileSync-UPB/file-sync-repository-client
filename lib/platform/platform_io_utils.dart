import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _nativeChannel = MethodChannel('com.example.fylesync/native');

void openUrlOrDownload(String url, {String? downloadName}) async {
  try {
    if (Platform.isAndroid) {
      await _nativeChannel.invokeMethod('openUrl', {'url': url});
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    } else {
      debugPrint('Plataforma no soportada para openUrlOrDownload: $url');
    }
  } catch (e) {
    debugPrint('Error en openUrlOrDownload: $e');
  }
}

void pickFileWeb({
  required Function(String name, int size, List<int> bytes) onFileSelected,
}) async {
  try {
    if (Platform.isAndroid) {
      final res = await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>('pickFile');
      if (res != null) {
        final name = res['name'] as String? ?? 'archivo_subido';
        final size = (res['size'] as num?)?.toInt() ?? 0;
        final rawBytes = res['bytes'];
        List<int> bytes = [];
        if (rawBytes is Uint8List) {
          bytes = rawBytes.toList();
        } else if (rawBytes is List) {
          bytes = rawBytes.cast<int>();
        }
        if (bytes.isNotEmpty) {
          onFileSelected(name, size > 0 ? size : bytes.length, bytes);
        }
      }
      return;
    }

    if (Platform.isWindows) {
      const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = "Todos los archivos (*.*)|*.*"
$dialog.Title = "Seleccionar archivo para subir a FyleSync"
$form = New-Object System.Windows.Forms.Form
$form.TopMost = $true
if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::WriteLine($dialog.FileName)
}
$form.Dispose()
''';
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', script],
      );
      final selectedPath = res.stdout.toString().trim();
      if (selectedPath.isNotEmpty) {
        final file = File(selectedPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final name = file.uri.pathSegments.last;
          onFileSelected(name, bytes.length, bytes);
        }
      }
      return;
    }
  } catch (e) {
    debugPrint('Error en pickFileWeb (nativo): $e');
  }
}

void registerHtmlPreview(String viewId, String url, {required bool isVideo}) {
  // No-op en plataformas nativas
}

Widget buildHtmlPlatformView(String viewId) {
  return const Center(
    child: Icon(Icons.file_present_rounded, size: 64, color: Colors.white54),
  );
}

Future<String?> pickNativeDirectory() async {
  try {
    if (Platform.isWindows) {
      const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "Seleccionar carpeta para sincronización con FyleSync"
$form = New-Object System.Windows.Forms.Form
$form.TopMost = $true
if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::WriteLine($dialog.SelectedPath)
}
$form.Dispose()
''';
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', script],
      );
      final selectedPath = res.stdout.toString().trim();
      if (selectedPath.isNotEmpty) {
        return selectedPath;
      }
    }
  } catch (e) {
    debugPrint('Error en pickNativeDirectory: $e');
  }
  return null;
}

Future<Map<String, dynamic>> runNativeSyncClient({
  required String token,
  required String deviceId,
  required String syncFolder,
  String? serverAddr,
}) async {
  try {
    if (!Platform.isWindows && !Platform.isLinux) {
      return {'success': false, 'message': 'No soportado en móvil'};
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      Platform.isWindows ? '$exeDir\\filesync-client.exe' : '$exeDir/filesync-client-linux',
      Platform.isWindows ? 'filesync-client.exe' : './filesync-client-linux',
      Platform.isWindows ? '${Directory.current.path}\\filesync-client.exe' : '',
      Platform.isWindows ? '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\filesync-client.exe' : '',
      Platform.isWindows ? '${Directory.current.path}\\build\\web\\filesync-client.exe' : '',
    ];

    String? executable;
    for (final c in candidates) {
      if (c.isNotEmpty && File(c).existsSync()) {
        executable = c;
        break;
      }
    }

    if (executable == null) {
      return {
        'success': false,
        'message': 'No se encontró el ejecutable filesync-client.exe.'
      };
    }

    final dir = Directory(syncFolder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final addr = serverAddr ?? '127.0.0.1:8443';
    final result = await Process.run(executable, [
      '-server', addr,
      '-token', token,
      '-device', deviceId,
      '-dir', syncFolder,
      '-action', 'sync',
    ]);

    if (result.exitCode == 0) {
      return {
        'success': true,
        'output': result.stdout.toString(),
        'message': 'Sincronización nativa con el repositorio central completada con éxito.'
      };
    } else {
      final err = result.stderr.toString().isNotEmpty ? result.stderr.toString() : result.stdout.toString();
      return {
        'success': false,
        'message': err.isNotEmpty ? err : 'Error en la sincronización gRPC.'
      };
    }
  } catch (e) {
    return {'success': false, 'message': 'Error ejecutando cliente: $e'};
  }
}

Future<List<Map<String, dynamic>>> listLocalDirectoryFiles(String dirPath) async {
  try {
    if (Platform.isAndroid) {
      final res = await _nativeChannel.invokeMethod<List<dynamic>>('listDirectory', {'path': dirPath});
      if (res != null) {
        return res.map((item) {
          final m = Map<String, dynamic>.from(item as Map);
          return m;
        }).toList();
      }
      return [];
    }

    if (Platform.isWindows || Platform.isLinux) {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final list = <Map<String, dynamic>>[];
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            final stat = entity.statSync();
            final name = entity.uri.pathSegments.isNotEmpty
                ? entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'archivo')
                : 'archivo';
            list.add({
              'name': name,
              'path': entity.path,
              'size': stat.size,
              'lastModified': stat.modified.millisecondsSinceEpoch,
            });
          }
        }
        return list;
      }
    }
  } catch (e) {
    debugPrint('Error en listLocalDirectoryFiles: $e');
  }
  return [];
}

Future<Uint8List?> readLocalFile(String filePath) async {
  try {
    if (Platform.isAndroid) {
      final res = await _nativeChannel.invokeMethod('readFileBytes', {'path': filePath});
      if (res is Uint8List) return res;
      if (res is List) return Uint8List.fromList(res.cast<int>());
      return null;
    }

    if (Platform.isWindows || Platform.isLinux) {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    }
  } catch (e) {
    debugPrint('Error en readLocalFile: $e');
  }
  return null;
}

Future<bool> saveLocalFile(String dirPath, String fileName, List<int> bytes) async {
  try {
    if (Platform.isAndroid) {
      final res = await _nativeChannel.invokeMethod<bool>('saveFileBytes', {
        'dirPath': dirPath,
        'fileName': fileName,
        'bytes': bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      });
      return res ?? false;
    }

    if (Platform.isWindows || Platform.isLinux) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final sep = Platform.isWindows ? '\\' : '/';
      final file = File('$dirPath$sep$fileName');
      await file.writeAsBytes(bytes);
      return true;
    }
  } catch (e) {
    debugPrint('Error en saveLocalFile: $e');
  }
  return false;
}

Future<bool> requestStoragePermissions() async {
  try {
    if (Platform.isAndroid) {
      return await _nativeChannel.invokeMethod<bool>('requestManageStorage') ?? true;
    }
  } catch (e) {
    debugPrint('Error en requestStoragePermissions: $e');
  }
  return true;
}
