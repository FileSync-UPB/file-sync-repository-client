import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../../config/api_config.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('auth_token');
    final savedUsername = prefs.getString('auth_username');
    if (savedToken != null && savedToken.isNotEmpty && savedUsername != null && savedUsername.isNotEmpty) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              token: savedToken,
              username: savedUsername,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    try {
      final envelope = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:upbcientifica:user-service">
   <soap:Body>
      <urn:authenticateUser>
         <username>$username</username>
         <password>$password</password>
      </urn:authenticateUser>
   </soap:Body>
</soap:Envelope>''';

      // Use localhost when running locally on web.
      final response = await http.post(
        Uri.parse('${ApiConfig.usersUrl}/public/SoapServer.php'),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction': 'urn:upbcientifica:user-service#authenticateUser',
        },
        body: envelope,
      );

      if (response.statusCode == 200) {
        // Parse XML response
        final document = xml.XmlDocument.parse(response.body);
        final tokenNode = document.findAllElements('token').firstOrNull;
        
        if (tokenNode != null) {
          final token = tokenNode.innerText;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
          await prefs.setString('auth_username', username);

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => HomeScreen(
                  token: token,
                  username: username,
                ),
              ),
            );
          }
        } else {
          setState(() {
            _errorMessage = 'Respuesta inválida del servidor.';
          });
        }
      } else {
        // Try to parse SOAP Fault
        try {
          final document = xml.XmlDocument.parse(response.body);
          final faultString = document.findAllElements('faultstring').firstOrNull?.innerText;
          setState(() {
            _errorMessage = faultString ?? 'Fallo en la autenticación. Revisa tus credenciales.';
          });
        } catch (_) {
          setState(() {
            _errorMessage = 'Error del servidor: ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de red: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated Background Gradient
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(const Color(0xFF0F172A), const Color(0xFF1E1B4B), _bgController.value)!,
                      Color.lerp(const Color(0xFF1E1B4B), const Color(0xFF312E81), _bgController.value)!,
                      const Color(0xFF0F172A),
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Floating Orbs for Premium Feel
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4F46E5).withOpacity(0.3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withOpacity(0.3),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF06B6D4).withOpacity(0.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF06B6D4).withOpacity(0.2),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),

          // Glassmorphic Login Card
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                physics: const ClampingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 30,
                                spreadRadius: -5,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(
                                Icons.cloud_sync_rounded,
                                size: 56,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'FileSync',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Plataforma de Datos Empresarial',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Colors.white70,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 32),
                              if (_errorMessage != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                                  ),
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: Colors.redAccent),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              _buildTextField(
                                controller: _usernameController,
                                label: 'Usuario',
                                icon: Icons.person_outline,
                              ),
                              const SizedBox(height: 20),
                              _buildTextField(
                                controller: _passwordController,
                                label: 'Contraseña',
                                icon: Icons.lock_outline,
                                isPassword: true,
                                onSubmitted: (_) => _handleLogin(),
                              ),
                              const SizedBox(height: 32),
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Iniciar Sesión',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 16),
                              InkWell(
                                onTap: _showServerConfigDialog,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.settings_ethernet, size: 14, color: Colors.indigoAccent),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Servidor: ${ApiConfig.host}',
                                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.edit, size: 12, color: Colors.white38),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Botón flotante superior para configuración rápida de IP
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                tooltip: 'Configurar IP del Servidor / Red',
                onPressed: _showServerConfigDialog,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showServerConfigDialog() {
    final hostCtrl = TextEditingController(text: ApiConfig.host);
    final usersCtrl = TextEditingController(text: ApiConfig.usersHost != ApiConfig.host ? ApiConfig.usersHost : '');
    final streamCtrl = TextEditingController(text: ApiConfig.streamingHost != ApiConfig.host ? ApiConfig.streamingHost : '');
    final syncCtrl = TextEditingController(text: ApiConfig.syncHost != ApiConfig.host ? ApiConfig.syncHost : '');
    final hpcCtrl = TextEditingController(text: ApiConfig.hpcHost != ApiConfig.host ? ApiConfig.hpcHost : '');

    bool showAdvanced = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.dns_rounded, color: Colors.indigoAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Configuración de Servidor & IP',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Si la IP de la máquina cambió en la red UPB o te conectas desde otra PC/móvil, configúrala aquí:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: hostCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'IP / Host Principal del Servidor',
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: '192.168.1.1 o localhost',
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(Icons.router_outlined, color: Colors.indigoAccent),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.my_location, size: 16, color: Colors.cyanAccent),
                        label: const Text('Fijar 192.168.1.1', style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                        onPressed: () => setDlgState(() => hostCtrl.text = '192.168.1.1'),
                      ),
                      const Spacer(),
                      TextButton(
                        child: Text(
                          showAdvanced ? 'Ocultar Avanzado' : 'Despliegue 4 Máquinas',
                          style: const TextStyle(color: Colors.indigoAccent, fontSize: 12),
                        ),
                        onPressed: () => setDlgState(() => showAdvanced = !showAdvanced),
                      ),
                    ],
                  ),
                  if (showAdvanced) ...[
                    const Divider(color: Colors.white12, height: 24),
                    const Text(
                      'IPs Distribuidas (Para el clúster de 4 máquinas):',
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: usersCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Máquina 1 (Usuarios / LDAP / SOAP :8080)',
                        labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: streamCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Máquina 2 (Almacenamiento / Streaming :3000)',
                        labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: syncCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Máquina 3 (FileSync gRPC :8443)',
                        labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: hpcCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Máquina 4 (Maestro HPC & Monitoreo :8081)',
                        labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final mainH = hostCtrl.text.trim();
                if (showAdvanced) {
                  await ApiConfig.setDistributedHosts(
                    mainHost: mainH,
                    usersHost: usersCtrl.text.trim(),
                    streamingHost: streamCtrl.text.trim(),
                    syncHost: syncCtrl.text.trim(),
                    hpcHost: hpcCtrl.text.trim(),
                  );
                } else {
                  await ApiConfig.setHost(mainH);
                }
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Servidor actualizado a: ${ApiConfig.host}'),
                      backgroundColor: Colors.green[700],
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: const Text('Guardar Configuración'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    Function(String)? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4F46E5)),
        ),
      ),
    );
  }
}
