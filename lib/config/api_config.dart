class ApiConfig {
  static String get host {
    final h = Uri.base.host;
    if (h.isNotEmpty && h != '0.0.0.0') {
      return h;
    }
    return 'localhost';
  }

  static String get streamingUrl => 'http://$host:3000';
  static String get usersUrl => 'http://$host:8080';
  static String get webUrl => 'http://$host:5000';
  static String get hpcUrl => 'http://$host:8081';
}

