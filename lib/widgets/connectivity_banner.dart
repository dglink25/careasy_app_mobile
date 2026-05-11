import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ConnectivityBanner extends StatefulWidget {
  /// URL à pinguer pour tester la connexion (HEAD request).
  final String? pingUrl;

  /// Intervalle entre chaque vérification (défaut : 5 s).
  final Duration checkInterval;

  const ConnectivityBanner({
    super.key,
    this.pingUrl,
    this.checkInterval = const Duration(seconds: 5),
  });

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  // null = non encore déterminé
  bool? _isOnline;
  bool _showRestored = false;
  Timer? _timer;
  Timer? _restoreTimer;
  late AnimationController _animController;
  late Animation<double> _slideAnim;

  // Couleurs
  static const _redDark    = Color(0xFFB71C1C);
  static const _redLight   = Color(0xFFEF5350);
  static const _greenDark  = Color(0xFF1B5E20);
  static const _greenLight = Color(0xFF43A047);

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    // Premier check immédiat, puis à intervalle
    _check();
    _timer = Timer.periodic(widget.checkInterval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restoreTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final url = widget.pingUrl ?? 'https://www.google.com';
    bool online;
    try {
      final resp = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 4));
      online = resp.statusCode < 500;
    } catch (_) {
      online = false;
    }

    if (!mounted) return;

    final wasOnline = _isOnline;

    setState(() => _isOnline = online);

    if (online) {
      if (wasOnline == false) {
        // Vient de se reconnecter
        _showRestored = true;
        _animController.forward(from: 0);
        _restoreTimer?.cancel();
        _restoreTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() => _showRestored = false);
          _animController.reverse();
        });
      } else if (wasOnline == true && !_showRestored) {
        // Déjà en ligne, on cache la bannière
        _animController.reverse();
      }
    } else {
      _showRestored = false;
      _restoreTimer?.cancel();
      _animController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tant qu'on n'a pas encore de résultat, on n'affiche rien
    if (_isOnline == null) return const SizedBox.shrink();
    // En ligne et bannière "rétablie" expirée → rien
    if (_isOnline == true && !_showRestored) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _slideAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _slideAnim.value * 60),
        child: child,
      ),
      child: _BannerContent(isOnline: _isOnline!, showRestored: _showRestored),
    );
  }
}

class _BannerContent extends StatelessWidget {
  final bool isOnline;
  final bool showRestored;

  const _BannerContent({required this.isOnline, required this.showRestored});

  @override
  Widget build(BuildContext context) {
    final bool restored = isOnline && showRestored;

    final gradient = restored
        ? const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
          )
        : const LinearGradient(
            colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
          );

    final icon    = restored ? Icons.wifi       : Icons.wifi_off_rounded;
    final message = restored ? 'Connexion rétablie ✓' : 'Vous êtes actuellement hors ligne';
    final sub     = restored
        ? 'Vos données sont à nouveau synchronisées'
        : 'Vérifiez votre connexion Internet';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: (restored
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFFB71C1C))
                .withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Icône avec pulsation si hors ligne
              restored
                  ? Icon(icon, color: Colors.white, size: 22)
                  : _PulsingIcon(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sub,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icône avec animation de pulsation (hors ligne uniquement)
class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  const _PulsingIcon({required this.icon});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(widget.icon, color: Colors.white, size: 22),
    );
  }
}