import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  // IP actual por defecto en la red local UPB
  static const String defaultLanHost = '192.168.1.1';

  static String? _customHost;
  static String? _usersHost;
  static String? _streamingHost;
  static String? _syncHost;
  static String? _hpcHost;

  /// Inicializa la configuración desde SharedPreferences al arrancar la app
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customHost = prefs.getString('fylesync_cfg_host');
      _usersHost = prefs.getString('fylesync_cfg_users_host');
      _streamingHost = prefs.getString('fylesync_cfg_streaming_host');
      _syncHost = prefs.getString('fylesync_cfg_sync_host');
      _hpcHost = prefs.getString('fylesync_cfg_hpc_host');
    } catch (_) {}
  }

  /// Guarda una IP unificada de servidor para todas las peticiones
  static Future<void> setHost(String newHost) async {
    final trimmed = newHost.trim();
    if (trimmed.isNotEmpty) {
      _customHost = trimmed;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fylesync_cfg_host', trimmed);
      } catch (_) {}
    }
  }

  /// Guarda las IPs independientes para despliegue distribuido en 4 máquinas
  static Future<void> setDistributedHosts({
    String? mainHost,
    String? usersHost,
    String? streamingHost,
    String? syncHost,
    String? hpcHost,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mainHost != null && mainHost.trim().isNotEmpty) {
        _customHost = mainHost.trim();
        await prefs.setString('fylesync_cfg_host', _customHost!);
      }
      if (usersHost != null) {
        _usersHost = usersHost.trim().isEmpty ? null : usersHost.trim();
        if (_usersHost != null) {
          await prefs.setString('fylesync_cfg_users_host', _usersHost!);
        } else {
          await prefs.remove('fylesync_cfg_users_host');
        }
      }
      if (streamingHost != null) {
        _streamingHost = streamingHost.trim().isEmpty ? null : streamingHost.trim();
        if (_streamingHost != null) {
          await prefs.setString('fylesync_cfg_streaming_host', _streamingHost!);
        } else {
          await prefs.remove('fylesync_cfg_streaming_host');
        }
      }
      if (syncHost != null) {
        _syncHost = syncHost.trim().isEmpty ? null : syncHost.trim();
        if (_syncHost != null) {
          await prefs.setString('fylesync_cfg_sync_host', _syncHost!);
        } else {
          await prefs.remove('fylesync_cfg_sync_host');
        }
      }
      if (hpcHost != null) {
        _hpcHost = hpcHost.trim().isEmpty ? null : hpcHost.trim();
        if (_hpcHost != null) {
          await prefs.setString('fylesync_cfg_hpc_host', _hpcHost!);
        } else {
          await prefs.remove('fylesync_cfg_hpc_host');
        }
      }
    } catch (_) {}
  }

  static String get host {
    if (_customHost != null && _customHost!.isNotEmpty) {
      return _customHost!;
    }
    if (kIsWeb) {
      try {
        final h = Uri.base.host;
        if (h.isNotEmpty && h != '0.0.0.0') {
          return h;
        }
      } catch (_) {}
      return 'localhost';
    }
    // En Windows/Linux Desktop, 'localhost' garantiza acceso inmediato a streaming y videos locales
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return 'localhost';
    }
    return defaultLanHost;
  }

  // Hosts independientes (o fallback al host principal)
  static String get usersHost => (_usersHost != null && _usersHost!.isNotEmpty) ? _usersHost! : host;
  static String get streamingHost => (_streamingHost != null && _streamingHost!.isNotEmpty) ? _streamingHost! : host;
  static String get syncHost => (_syncHost != null && _syncHost!.isNotEmpty) ? _syncHost! : host;
  static String get hpcHost => (_hpcHost != null && _hpcHost!.isNotEmpty) ? _hpcHost! : host;

  // URLs de los Microservicios
  static String get usersUrl => 'http://$usersHost:8080';
  static String get streamingUrl => 'http://$streamingHost:3000';
  static String get syncGrpcHost => '$syncHost:8443';
  static String get hpcUrl => 'http://$hpcHost:8081';
  static String get webUrl => 'http://$streamingHost:5000';
}
