import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String defaultLanHost = '192.168.1.2';
  static String? customHost;

  static void setHost(String newHost) {
    if (newHost.trim().isNotEmpty) {
      customHost = newHost.trim();
    }
  }

  static String get host {
    if (customHost != null && customHost!.isNotEmpty) {
      return customHost!;
    }
    if (kIsWeb) {
      try {
        final h = Uri.base.host;
        if (h.isNotEmpty && h != '0.0.0.0') {
          return h;
        }
      } catch (_) {}
    }
    return defaultLanHost;
  }

  static String get streamingUrl => 'http://$host:3000';
  static String get usersUrl => 'http://$host:8080';
  static String get webUrl => 'http://$host:5000';
  static String get hpcUrl => 'http://$host:8081';
}


