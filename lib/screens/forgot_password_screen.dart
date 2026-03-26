import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import 'otp_verification_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey       = GlobalKey<FormState>();
  final _inputCtrl     = TextEditingController();
  bool  _isLoading     = false;
  String? _detectedType; // 'email' | 'phone'

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn)
        .drive(Tween(begin: 0.0, end: 1.0));
    _slideAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic)
        .drive(Tween(begin: const Offset(0, 0.08), end: Offset.zero));
    _animCtrl.forward();

    _inputCtrl.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _inputCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final v    = _inputCtrl.text.trim();
    final type = _guessType(v);
    if (type != _detectedType) {
      setState(() => _detectedType = type);
    }
  }

  /// Détecte si la saisie ressemble à un email ou à un téléphone.
  String? _guessType(String v) {
    if (v.isEmpty) return null;
    final emailRx = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$');
    if (emailRx.hasMatch(v)) return 'email';
    final digits = v.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 6) return 'phone';
    return null;
  }

  String _normalizePhone(String v) {
    String clean = v.replaceAll(RegExp(r'[^\d+]'), '');
    if (!clean.startsWith('+') && clean.startsWith('7')) {
      clean = '+229$clean'; // Bénin par défaut — adaptez selon votre marché
    }
    return clean;
  }

  Future<void> _handleSend() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final raw  = _inputCtrl.text.trim();
    final type = _detectedType ?? _guessType(raw);

    String identifier = raw;
    if (type == 'phone') identifier = _normalizePhone(raw);

    try {
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/forgot-password/otp'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'identifier': identifier}),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (!mounted) return;

      if (resp.statusCode == 200 && body['success'] == true) {
        // Naviguer vers l'écran OTP
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              identifier  : identifier,
              identifierType: type ?? 'email',
              expiresIn   : (body['expires_in'] as num?)?.toInt() ?? 300,
              resendAfter : (body['resend_after'] as num?)?.toInt() ?? 60,
            ),
          ),
        );
      } else if (resp.statusCode == 429) {
        final wait = body['wait_seconds'] ?? 60;
        _showError('Attendez $wait secondes avant de renvoyer un code.');
      } else {
        _showError(body['message'] ?? 'Une erreur est survenue.');
      }
    } catch (e) {
      _showError('Impossible de joindre le serveur. Vérifiez votre connexion.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        title: const Text('Mot de passe oublié',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2), shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
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
                    // Illustration
                    Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE63946), Color(0xFFFF6B6B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppConstants.primaryRed.withOpacity(0.25),
                              blurRadius: 24, offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.lock_reset_rounded,
                            size: 48, color: Colors.white),
                      ),
                    ),

                    const SizedBox(height: 28),

                    const Text(
                      'Réinitialisez votre\nmot de passe',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800,
                          color: Color(0xFF2D3436), height: 1.3),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Entrez votre email ou numéro de téléphone.\nNous vous enverrons un code de vérification.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFF718096), height: 1.5),
                    ),

                    const SizedBox(height: 36),

                    // Champ identifiant
                    TextFormField(
                      controller: _inputCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'Email ou numéro de téléphone',
                        hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
                        prefixIcon: Icon(
                          _detectedType == 'phone'
                              ? Icons.phone_outlined
                              : _detectedType == 'email'
                                  ? Icons.email_outlined
                                  : Icons.person_outline,
                          color: _detectedType != null
                              ? AppConstants.primaryRed
                              : const Color(0xFF718096),
                          size: 20,
                        ),
                        suffixIcon: _detectedType != null
                            ? Padding(
                                padding: const EdgeInsets.only(right: 12),
                                
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: AppConstants.primaryRed, width: 1.5)),
                        errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Colors.red, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 16),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ce champ est requis.';
                        }
                        final t = _guessType(v.trim());
                        if (t == null) {
                          return 'Entrez un email valide ou un numéro de téléphone.';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    // Indice type détecté
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _detectedType != null
                          ? Container(
                              key: ValueKey(_detectedType),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppConstants.primaryRed.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _detectedType == 'email'
                                        ? Icons.email_outlined
                                        : Icons.sms_outlined,
                                    size: 16,
                                    color: AppConstants.primaryRed,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _detectedType == 'email'
                                        ? 'Le code sera envoyé par email'
                                        : 'Le code sera envoyé par SMS',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppConstants.primaryRed,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 28),

                    // Bouton Envoyer
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSend,
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
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'ENVOYER LE CODE',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Retour connexion
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF718096)),
                        child: const Text('← Retour à la connexion',
                            style: TextStyle(fontSize: 13)),
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
}