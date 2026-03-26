import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';

class NewPasswordScreen extends StatefulWidget {
  final String resetToken;
  final int    expiresIn; // secondes

  const NewPasswordScreen({
    super.key,
    required this.resetToken,
    required this.expiresIn,
  });

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey              = GlobalKey<FormState>();
  final _passwordCtrl         = TextEditingController();
  final _confirmPasswordCtrl  = TextEditingController();

  bool _showPassword        = false;
  bool _showConfirmPassword = false;
  bool _isLoading           = false;

  // Indicateur de force du mot de passe
  double _passwordStrength  = 0;
  String _strengthLabel     = '';
  Color  _strengthColor     = Colors.transparent;

  // Timer d'expiration du reset_token
  late int   _secondsLeft;
  Timer?     _timer;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.expiresIn;

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn)
        .drive(Tween(begin: 0.0, end: 1.0));
    _slideAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic)
        .drive(Tween(begin: const Offset(0, 0.08), end: Offset.zero));
    _animCtrl.forward();

    _startTimer();
    _passwordCtrl.addListener(_evaluateStrength);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _passwordCtrl.removeListener(_evaluateStrength);
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        setState(() {});
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  String _formatTime(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  // ── Force du mot de passe ─────────────────────────────────────────────────

  void _evaluateStrength() {
    final p = _passwordCtrl.text;
    double score = 0;

    if (p.length >= 8)  score += 0.25;
    if (p.length >= 12) score += 0.15;
    if (RegExp(r'[A-Z]').hasMatch(p)) score += 0.20;
    if (RegExp(r'[0-9]').hasMatch(p)) score += 0.20;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(p)) score += 0.20;

    setState(() {
      _passwordStrength = score.clamp(0.0, 1.0);
      if (score < 0.35) {
        _strengthLabel = 'Faible';
        _strengthColor = Colors.red;
      } else if (score < 0.65) {
        _strengthLabel = 'Moyen';
        _strengthColor = Colors.orange;
      } else if (score < 0.85) {
        _strengthLabel = 'Bon';
        _strengthColor = Colors.blue;
      } else {
        _strengthLabel = 'Très fort';
        _strengthColor = Colors.green;
      }
    });
  }

  // ── Soumission ────────────────────────────────────────────────────────────

  Future<void> _handleReset() async {
    if (!_formKey.currentState!.validate()) return;
    if (_secondsLeft <= 0) {
      _showError('Session expirée. Recommencez depuis le début.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/forgot-password/otp/reset'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'reset_token'           : widget.resetToken,
          'password'              : _passwordCtrl.text,
          'password_confirmation' : _confirmPasswordCtrl.text,
        }),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (!mounted) return;

      if (resp.statusCode == 200 && body['success'] == true) {
        _timer?.cancel();
        await _saveSession(body);
        _navigateToHome();
      } else {
        _showError(body['message'] ?? 'Une erreur est survenue.');
      }
    } catch (e) {
      _showError('Erreur réseau. Vérifiez votre connexion.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Sauvegarder le token et les données utilisateur après reset réussi.
  Future<void> _saveSession(Map<String, dynamic> body) async {
    final token    = body['token']    as String?;
    final userData = body['user']     as Map<String, dynamic>?;

    if (token != null && token.isNotEmpty) {
      await _storage.write(key: 'auth_token', value: token);
    }
    if (userData != null) {
      await _storage.write(key: 'user_data', value: jsonEncode(userData));
    }

    // Mettre à jour le AuthProvider
    if (token != null && userData != null && mounted) {
      await context.read<AuthProvider>().login(token, userData);
    }
  }

  void _navigateToHome() {
    _showSuccess('Mot de passe mis à jour ! Bienvenue 🎉');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final expired = _secondsLeft <= 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        title: const Text('Nouveau mot de passe',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        automaticallyImplyLeading: false, // Pas de retour arrière sur cet écran
        elevation: 0,
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icône
                    Center(
                      child: Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE63946), Color(0xFFFF6B6B)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppConstants.primaryRed.withOpacity(0.25),
                              blurRadius: 24, offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.lock_open_rounded,
                            size: 42, color: Colors.white),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Créez un nouveau\nmot de passe',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800,
                          color: Color(0xFF2D3436), height: 1.3),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Choisissez un mot de passe sécurisé\nd\'au moins 8 caractères.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: Color(0xFF718096), height: 1.5),
                    ),

                    const SizedBox(height: 20),

                    // Timer session
                    if (!expired)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: (_secondsLeft < 60
                                    ? Colors.orange
                                    : AppConstants.primaryRed)
                                .withOpacity(0.08),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined,
                                  size: 16,
                                  color: _secondsLeft < 60
                                      ? Colors.orange
                                      : AppConstants.primaryRed),
                              const SizedBox(width: 6),
                              Text(
                                'Session valide : ${_formatTime(_secondsLeft)}',
                                style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: _secondsLeft < 60
                                      ? Colors.orange
                                      : AppConstants.primaryRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Session expirée. Recommencez depuis le début.',
                                style:
                                    TextStyle(color: Colors.red, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 28),

                    // ── Nouveau mot de passe ────────────────────────────────────
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: !_showPassword,
                      decoration: _inputDecoration(
                        hint: 'Nouveau mot de passe',
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF718096), size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Ce champ est requis.';
                        if (v.length < 8) return 'Minimum 8 caractères.';
                        return null;
                      },
                    ),

                    // Jauge de force
                    if (_passwordCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _passwordStrength,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation(_strengthColor),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _strengthLabel,
                            style: TextStyle(
                                fontSize: 12, color: _strengthColor,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _PasswordHints(password: _passwordCtrl.text),
                    ],

                    const SizedBox(height: 16),

                    // ── Confirmer mot de passe ──────────────────────────────────
                    TextFormField(
                      controller: _confirmPasswordCtrl,
                      obscureText: !_showConfirmPassword,
                      decoration: _inputDecoration(
                        hint: 'Confirmer le mot de passe',
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _showConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF718096), size: 20,
                          ),
                          onPressed: () => setState(
                              () => _showConfirmPassword = !_showConfirmPassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return 'Confirmez votre mot de passe.';
                        if (v != _passwordCtrl.text)
                          return 'Les mots de passe ne correspondent pas.';
                        return null;
                      },
                    ),

                    const SizedBox(height: 28),

                    // ── Bouton ──────────────────────────────────────────────────
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_isLoading || expired) ? null : _handleReset,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('METTRE À JOUR',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF718096), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppConstants.primaryRed, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 1.5)),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }
}

// ── Widget hints force du mot de passe ────────────────────────────────────────

class _PasswordHints extends StatelessWidget {
  final String password;
  const _PasswordHints({required this.password});

  @override
  Widget build(BuildContext context) {
    final checks = [
      _Check('8 caractères minimum',          password.length >= 8),
      _Check('Une majuscule (A-Z)',            RegExp(r'[A-Z]').hasMatch(password)),
      _Check('Un chiffre (0-9)',               RegExp(r'[0-9]').hasMatch(password)),
      _Check('Un caractère spécial (!@#...)',  RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: checks
          .map((c) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      c.ok ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 14,
                      color: c.ok ? Colors.green : Colors.grey[400],
                    ),
                    const SizedBox(width: 6),
                    Text(c.label,
                        style: TextStyle(
                            fontSize: 12,
                            color: c.ok ? Colors.green : Colors.grey[500])),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _Check {
  final String label;
  final bool   ok;
  const _Check(this.label, this.ok);
}