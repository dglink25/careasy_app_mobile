import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

class ConnectivityHomeBanner extends StatefulWidget {
  final Widget child;

  /// Callback appelé quand la connexion est rétablie (pour reload les données)
  final VoidCallback? onReconnected;

  const ConnectivityHomeBanner({
    super.key,
    required this.child,
    this.onReconnected,
  });

  @override
  State<ConnectivityHomeBanner> createState() => _ConnectivityHomeBannerState();
}

class _ConnectivityHomeBannerState extends State<ConnectivityHomeBanner>
    with SingleTickerProviderStateMixin {
  final _svc = ConnectivityService();

  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _ctrl;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isOnline    = true;    // état courant
  bool _showBanner  = false;   // banner visible ?
  bool _wasOffline  = false;   // était hors-ligne → pour détecter le retour
  Timer? _hideTimer;

  StreamSubscription<bool>? _sub;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _isOnline = _svc.isOnline;

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnim = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );

    // Afficher immédiatement si déjà hors-ligne au démarrage
    if (!_isOnline) {
      _wasOffline = true;
      _showBanner = true;
      _ctrl.forward();
    }

    // Écoute des changements de connectivité
    _sub = _svc.onConnectivityChanged.listen(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // ── Logic ──────────────────────────────────────────────────────────────────
  void _onConnectivityChanged(bool online) {
    if (!mounted) return;

    if (!online) {
      // → HORS LIGNE : afficher le banner rouge
      _hideTimer?.cancel();
      setState(() {
        _isOnline   = false;
        _wasOffline = true;
        _showBanner = true;
      });
      _ctrl.forward(from: 0);
    } else {
      // → EN LIGNE : switcher vers le banner vert puis masquer après 3 s
      setState(() { _isOnline = true; });

      if (_wasOffline) {
        // Déclencher le rechargement des données
        widget.onReconnected?.call();

        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            _ctrl.reverse().then((_) {
              if (mounted) setState(() { _showBanner = false; _wasOffline = false; });
            });
          }
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Banner ────────────────────────────────────────────────────────
        if (_showBanner)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => FractionalTranslation(
              translation: Offset(0, _slideAnim.value),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _BannerContent(isOnline: _isOnline),
              ),
            ),
          ),

        // ── Corps de l'écran ──────────────────────────────────────────────
        Expanded(child: widget.child),
      ],
    );
  }
}

// ── Contenu visuel du banner ──────────────────────────────────────────────────
class _BannerContent extends StatelessWidget {
  final bool isOnline;
  const _BannerContent({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final Color bgColor  = isOnline ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final Color bgLight  = isOnline ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final IconData icon  = isOnline ? Icons.wifi           : Icons.wifi_off_rounded;
    final String title   = isOnline ? 'Connexion rétablie' : 'Vous êtes hors ligne';
    final String subtitle= isOnline
        ? 'Mise à jour des données en cours…'
        : 'Vérifiez votre connexion internet';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgColor, bgLight],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Icône avec cercle animé
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),

              // Textes
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Indicateur : spinner si reconnexion, sinon pastille rouge
              if (isOnline)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}