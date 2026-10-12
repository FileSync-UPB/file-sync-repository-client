import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/api_config.dart';
import 'platform/platform_utils.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/public_view_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initPlatformVideoPlayer();
  await ApiConfig.init();
  final prefs = await SharedPreferences.getInstance();
  final savedToken = prefs.getString('auth_token');
  final savedUsername = prefs.getString('auth_username');

  runApp(FyleSyncApp(
    initialToken: savedToken,
    initialUsername: savedUsername,
  ));
}

class FyleSyncApp extends StatelessWidget {
  final String? initialToken;
  final String? initialUsername;

  const FyleSyncApp({
    super.key,
    this.initialToken,
    this.initialUsername,
  });

  @override
  Widget build(BuildContext context) {
    String? shareId = Uri.base.queryParameters['share'];
    if (shareId == null || shareId.isEmpty) {
      final frag = Uri.base.fragment;
      final qIndex = frag.indexOf('?');
      if (qIndex != -1) {
        final params = Uri.splitQueryString(frag.substring(qIndex + 1));
        shareId = params['share'];
      }
    }

    final bool hasValidSavedSession = initialToken != null &&
        initialToken!.isNotEmpty &&
        initialUsername != null &&
        initialUsername!.isNotEmpty;

    return MaterialApp(
      title: 'FileSync Enterprise',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Segoe UI',
      ),
      home: shareId != null && shareId.isNotEmpty
          ? PublicViewScreen(fileId: shareId)
          : hasValidSavedSession
              ? HomeScreen(
                  token: initialToken!,
                  username: initialUsername!,
                )
              : const LoginScreen(),
    );
  }
}
