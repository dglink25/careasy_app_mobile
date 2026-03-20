
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../services/notification_service.dart';
import '../services/message_polling_service.dart';
import '../utils/constants.dart';
import 'home_screen.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));
    _anim.forward();
    Future.delayed(const Duration(milliseconds: 1200), _checkSession);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    if (!mounted) return;
    try {
      final token = await _storage.read(key: 'auth_token');
      final userData = await _storage.read(key: 'user_data');

      if (token == null || token.isEmpty) {
        debugPrint('[Splash] Aucun token → WelcomeScreen');
        _goTo(const WelcomeScreen());
        return;
      }

      final isValid = await _verifyToken(token);
      if (!mounted) return;

      if (isValid) {
        debugPrint('[Splash] Token valide → HomeScreen');
        if (userData != null && userData.isNotEmpty) {
          try {
            final map = jsonDecode(userData) as Map<String, dynamic>;
            await context.read<AuthProvider>().login(token, map);
          } catch (_) {
            await _refreshUser(token);
          }
        } else {
          await _refreshUser(token);
        }
        if (!mounted) return;

        // ⭐ Démarrer Pusher + Polling + FCM après login
        await context.read<MessageProvider>().reinitializeAfterLogin();
        await NotificationService().refreshTokenAfterLogin();

        if (!mounted) return;
        _goTo(const HomeScreen());
      } else {
        debugPrint('[Splash] Token invalide → WelcomeScreen');
        await _clearSession();
        _goTo(const WelcomeScreen());
      }
    } catch (e) {
      debugPrint('[Splash] Erreur: $e → WelcomeScreen');
      _goTo(const WelcomeScreen());
    }
  }

  Future<bool> _verifyToken(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/profile'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          if (data.isNotEmpty) {
            await _storage.write(key: 'user_data', value: jsonEncode(data));
          }
        } catch (_) {}
        return true;
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) return false;
      debugPrint('[Splash] Serveur ${resp.statusCode} → token accepté');
      return true;
    } catch (e) {
      debugPrint('[Splash] Pas de réseau → token local accepté');
      return true;
    }
  }

  Future<void> _refreshUser(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/profile'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        await _storage.write(key: 'user_data', value: jsonEncode(data));
        await context.read<AuthProvider>().login(token, data);
      }
    } catch (e) {
      debugPrint('[Splash] _refreshUser: $e');
    }
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_data');
    await _storage.delete(key: 'fcm_token_pending');
    await _storage.delete(key: 'remember_me');
    // Arrêter le polling
    MessagePollingService().stop();
    if (mounted) {
      try {
        await context.read<AuthProvider>().logout();
      } catch (_) {}
    }
  }

  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppConstants.primaryRed.withOpacity(0.07),
                    Colors.transparent
                  ])),
            )),
        Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppConstants.primaryRed.withOpacity(0.05),
                    Colors.transparent
                  ])),
            )),
        Center(
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Votre Automobile, Notre Expertise',
                    style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w400),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => FadeTransition(
              opacity: _fade,
              child: Column(children: [
                SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppConstants.primaryRed.withOpacity(0.7))),
                const SizedBox(height: 12),
                Text('Chargement…',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}