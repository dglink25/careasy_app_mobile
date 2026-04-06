import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../providers/rendez_vous_provider.dart';         
import '../services/notification_service.dart';
import '../services/message_polling_service.dart';
import '../services/pusher_service.dart';
import '../utils/constants.dart';
import 'home_screen.dart';
import 'welcome_screen.dart';
import '../services/update_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<double> _scale;
  
  // Pour les 5 points de chargement
  late List<AnimationController> _dotControllers;
  late List<Animation<double>> _dotAnimations;
  Timer? _loadingMessageTimer;
  int _currentMessageIndex = 0;
  
  // Messages de chargement
  final List<String> _loadingMessages = [
    'Connexion en cours...',
    'Préparation de votre espace...',
    'Chargement des services...',
    'Presque prêt...',
    'Bienvenue !'
  ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));
    _anim.forward();
    
    // Initialisation des animations pour les 5 points
    _initDotAnimations();
    
    // Démarrage du changement de messages
    _startLoadingMessages();
    
    Future.delayed(const Duration(milliseconds: 1200), _checkSession);
  }

  void _initDotAnimations() {
    _dotControllers = List.generate(5, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      )..repeat(reverse: true);
    });
    
    _dotAnimations = List.generate(5, (index) {
      return Tween<double>(begin: 0.6, end: 1.2).animate(
        CurvedAnimation(
          parent: _dotControllers[index],
          curve: Curves.easeInOut,
        ),
      );
    });
    
    // Décaler les animations pour un effet cascade
    Future.delayed(Duration.zero, () {
      for (int i = 0; i < _dotControllers.length; i++) {
        Future.delayed(Duration(milliseconds: i * 100), () {
          if (mounted && _dotControllers[i].isCompleted) {
            _dotControllers[i].forward();
          }
        });
      }
    });
  }

  void _startLoadingMessages() {
    _loadingMessageTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (mounted && _currentMessageIndex < _loadingMessages.length - 1) {
        setState(() {
          _currentMessageIndex++;
        });
      } else if (_currentMessageIndex >= _loadingMessages.length - 1) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    for (var controller in _dotControllers) {
      controller.dispose();
    }
    _loadingMessageTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkSession() async {
    if (!mounted) return;
    try {
      final token    = await _storage.read(key: 'auth_token');
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

        // ── Démarrer Pusher + Polling + FCM ──────────────────────────
        await context.read<MessageProvider>().reinitializeAfterLogin();
        await NotificationService().refreshTokenAfterLogin();

        // ── Injecter RendezVousProvider dans PusherService ──────────
        if (mounted) {
          PusherService().setRendezVousProvider(
              context.read<RendezVousProvider>());
        }

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
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
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
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
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
    MessagePollingService().stop();
    if (mounted) {
      try { await context.read<AuthProvider>().logout(); } catch (_) {}
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdate(context);
    });
  }

  // Widget pour les 5 points de chargement style Facebook
  Widget _buildFacebookStyleLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Les 5 points animés
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            return AnimatedBuilder(
              animation: _dotControllers[index],
              builder: (context, child) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 8 * _dotAnimations[index].value,
                  height: 8 * _dotAnimations[index].value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.primaryRed.withOpacity(
                      0.3 + (0.5 * (_dotAnimations[index].value - 0.6) / 0.6)
                    ),
                  ),
                );
              },
            );
          }),
        ),
        const SizedBox(height: 16),
        // Message de chargement changeant
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            _loadingMessages[_currentMessageIndex],
            key: ValueKey(_currentMessageIndex),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        // Cercles décoratifs
        Positioned(
          top: -80, right: -80,
          child: Container(
            width: 320, height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppConstants.primaryRed.withOpacity(0.07),
                Colors.transparent,
              ]),
            ),
          ),
        ),
        Positioned(
          bottom: -60, left: -60,
          child: Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppConstants.primaryRed.withOpacity(0.05),
                Colors.transparent,
              ]),
            ),
          ),
        ),
        
        // Contenu principal
        Center(
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    // Logo
                    SizedBox(
                      width: 200, height: 200,
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Slogan
                    Text(
                      'La solution pour ne jamais tomber en panne au Bénin',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        
        // Footer avec le loader style Facebook
        Positioned(
          bottom: 50,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => FadeTransition(
              opacity: _fade,
              child: _buildFacebookStyleLoading(),
            ),
          ),
        ),
      ]),
    );
  }
}