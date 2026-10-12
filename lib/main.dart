import 'package:flutter/material.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/public_view_screen.dart';

void main() {
  runApp(const FyleSyncApp());
}

class FyleSyncApp extends StatelessWidget {
  const FyleSyncApp({super.key});

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
          : const LoginScreen(),
    );
  }
}
