import 'package:flutter/material.dart';
import 'api/api_client.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';
import 'theme/ui_theme.dart';
import 'features/splash/splash_screen.dart';

class P2PDeliveryApp extends StatefulWidget {
  const P2PDeliveryApp({super.key});

  @override
  State<P2PDeliveryApp> createState() => _P2PDeliveryAppState();
}

class _P2PDeliveryAppState extends State<P2PDeliveryApp> {
  final ApiClient _api = ApiClient(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
  );
  bool _ready = false;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final start = DateTime.now();
    await _api.restoreSession();
    var ok = _api.token != null &&
        _api.token!.isNotEmpty &&
        _api.currentUser != null &&
        _api.currentUser!.isNotEmpty;
    if (_api.token != null && _api.token!.isNotEmpty) {
      try {
        await _api.me();
        ok = true;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final tokenInvalid = msg.contains('invalid token') ||
            msg.contains('missing bearer token') ||
            msg.contains('insufficient role') ||
            msg.contains('user not found');
        if (tokenInvalid) {
          await _api.clearSession();
          ok = false;
        }
      }
    }
    final elapsed = DateTime.now().difference(start);
    const splashMin = Duration(milliseconds: 6500);
    if (elapsed < splashMin) {
      await Future<void>.delayed(splashMin - elapsed);
    }
    if (!mounted) return;
    setState(() {
      _authenticated = ok;
      _ready = true;
    });
  }

  void _onAuthed() {
    setState(() => _authenticated = true);
  }

  void _onLogout() {
    _api.clearSession();
    setState(() => _authenticated = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Elysian Flee',
      theme: buildAppTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: !_ready
          ? SplashScreen(onDone: () {})
          : (_authenticated
              ? HomeScreen(api: _api, onLogout: _onLogout)
              : AuthScreen(api: _api, onAuthenticated: _onAuthed)),
    );
  }
}
