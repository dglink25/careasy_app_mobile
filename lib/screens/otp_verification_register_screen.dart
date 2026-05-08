import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/screens/home_screen.dart';

class OtpVerificationRegisterScreen extends StatefulWidget {
  final String identifier;
  final String type; // 'email' | 'phone'
  final String name;
  final String password;
  final String confirmPassword;
  final bool acceptTerms;

  const OtpVerificationRegisterScreen({
    super.key,
    required this.identifier,
    required this.type,
    required this.name,
    required this.password,
    required this.confirmPassword,
    required this.acceptTerms,
  });

  @override
  State<OtpVerificationRegisterScreen> createState() =>
      _OtpVerificationRegisterScreenState();
}

class _OtpVerificationRegisterScreenState
    extends State<OtpVerificationRegisterScreen>
    with SingleTickerProviderStateMixin {
  // ── Stockage sécurisé ─────────────────────────────────────────────────
  static const _aOpts = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOpts =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _storage = const FlutterSecureStorage(aOptions: _aOpts, iOptions: _iOpts);

  // ── Saisie OTP (6 champs) ─────────────────────────────────────────────
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  // ── État général ──────────────────────────────────────────────────────
  bool _isVerifying  = false;
  bool _isSending    = false;
  bool _codeSent     = false;
  String _errorMsg   = '';
  String _maskedId   = '';

  // ── Timers ────────────────────────────────────────────────────────────
  // Durée de validité du code (ex: 300s = 5 min)
  int  _expirySeconds = 300;
  // Délai avant de pouvoir renvoyer (ex: 60s)
  int  _resendSeconds = 60;

  Timer? _expiryTimer;
  Timer? _resendTimer;

  // ── Animation shake ───────────────────────────────────────────────────
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();

    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 20)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));

    // Envoi automatique du code à l'ouverture de l'écran
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendOtp();
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ── Timers ────────────────────────────────────────────────────────────

  void _startExpiryTimer(int seconds) {
    _expiryTimer?.cancel();
    _expirySeconds = seconds;
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_expirySeconds <= 0) {
        _expiryTimer?.cancel();
        setState(() {});
        return;
      }
      setState(() => _expirySeconds--);
    });
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    _resendSeconds = seconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_resendSeconds <= 0) {
        _resendTimer?.cancel();
        setState(() {});
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  String _formatTime(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  // ── Envoi du code OTP ─────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    if (_isSending) return;

    setState(() {
      _isSending = true;
      _errorMsg  = '';
    });

    try {
      // 1. Vérifier si l'identifiant est déjà utilisé (avant d'envoyer le code)
      final alreadyUsed = await _checkIdentifierExists();
      if (alreadyUsed) {
        if (!mounted) return;
        setState(() {
          _errorMsg = widget.type == 'email'
              ? 'Cette adresse email est déjà associée à un compte.'
              : 'Ce numéro de téléphone est déjà associé à un compte.';
          _isSending = false;
        });
        return;
      }

      // 2. Envoyer le code via /verify-contact/send
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/verify-contact/send'),
        headers: {
          'Content-Type': 'application/json',
          'Accept':       'application/json',
        },
        body: jsonEncode({
          'identifier': widget.identifier,
          'type':       widget.type,
        }),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200 && body['success'] == true) {
        final expiresIn  = (body['expires_in']   as num?)?.toInt() ?? 300;
        final resendAfter = (body['resend_after'] as num?)?.toInt() ?? 60;
        final masked      = body['masked']?.toString() ?? '';

        setState(() {
          _codeSent   = true;
          _maskedId   = masked;
          _isSending  = false;
          _errorMsg   = '';
        });

        _startExpiryTimer(expiresIn);
        _startResendTimer(resendAfter);

        _showSnack(body['message'] ?? 'Code envoyé avec succès', Colors.green);

        // Focus sur le premier champ
        Future.delayed(
          const Duration(milliseconds: 300),
          () => _focusNodes[0].requestFocus(),
        );
      } else if (resp.statusCode == 429) {
        // Anti-spam : trop tôt pour renvoyer
        final waitSeconds = (body['wait_seconds'] as num?)?.toInt() ?? 60;
        setState(() {
          _isSending    = false;
          _resendSeconds = waitSeconds;
          _codeSent     = true; // L'écran reste, juste le bouton bloqué
        });
        _startResendTimer(waitSeconds);
        _showSnack(
          body['message'] ?? 'Attendez avant de renvoyer un code.',
          Colors.orange,
        );
      } else {
        final msg = body['message'] ?? 'Impossible d\'envoyer le code.';
        setState(() {
          _isSending = false;
          _errorMsg  = msg;
        });
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMsg  = 'Erreur réseau. Vérifiez votre connexion.';
      });
      debugPrint('[OTP Send] Exception: $e');
    }
  }

  // ── Vérification si le contact existe déjà ────────────────────────────

  Future<bool> _checkIdentifierExists() async {
    try {
      final endpoint = widget.type == 'email'
          ? '${AppConstants.apiBaseUrl}/check-email'
          : '${AppConstants.apiBaseUrl}/check-phone';

      final field = widget.type == 'email' ? 'email' : 'phone';

      final resp = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept':       'application/json',
        },
        body: jsonEncode({field: widget.identifier}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        // Le backend retourne { available: bool }
        // Si available = false → déjà utilisé
        return body['available'] == false;
      }
      return false; // En cas d'erreur, on laisse passer (le register échouera)
    } catch (_) {
      return false;
    }
  }

  // ── Vérification du code OTP ──────────────────────────────────────────

  String get _currentOtp => _controllers.map((c) => c.text).join();
  bool get _isOtpComplete => _currentOtp.length == 6;

  void _onDigitChanged(int index, String value) {
    setState(() => _errorMsg = '');
    if (value.length == 1) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        if (_isOtpComplete) _verifyOtp();
      }
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (text.length >= 6) {
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = text[i];
      }
      setState(() {});
      if (_isOtpComplete) _verifyOtp();
    }
  }

  void _clearFields() {
    for (final c in _controllers) c.clear();
    setState(() => _errorMsg = '');
    _focusNodes[0].requestFocus();
  }

  Future<void> _verifyOtp() async {
    if (!_isOtpComplete || _isVerifying) return;

    if (_expirySeconds <= 0) {
      setState(() => _errorMsg = 'Code expiré. Demandez-en un nouveau.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMsg    = '';
    });

    try {
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/verify-contact/check'),
        headers: {
          'Content-Type': 'application/json',
          'Accept':       'application/json',
        },
        body: jsonEncode({
          'identifier': widget.identifier,
          'type':       widget.type,
          'code':       _currentOtp,
        }),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200 && body['success'] == true) {
        // Code valide → procéder à l'inscription
        final verifyToken = body['verify_token']?.toString() ?? '';
        await _completeRegistration(verifyToken);
      } else {
        final code = body['code']?.toString() ?? '';
        if (code == 'OTP_EXPIRED' || code == 'MAX_ATTEMPTS') {
          _clearFields();
        }
        setState(() {
          _isVerifying = false;
          _errorMsg    = body['message'] ?? 'Code incorrect.';
        });
        _shakeCtrl.forward(from: 0);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMsg    = 'Erreur réseau. Réessayez.';
      });
      debugPrint('[OTP Verify] Exception: $e');
    }
  }

  // ── Inscription finale ────────────────────────────────────────────────

  Future<void> _completeRegistration(String verifyToken) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept':       'application/json',
        },
        body: jsonEncode({
          'name':                  widget.name,
          'password':              widget.password,
          'password_confirmation': widget.confirmPassword,
          'verify_token':          verifyToken,
        }),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        // Sauvegarder le token et les données utilisateur
        if (data['token'] != null) {
          await _storage.write(key: 'auth_token', value: data['token'].toString());
        }
        if (data['user'] != null) {
          await _storage.write(key: 'user_data', value: jsonEncode(data['user']));
        }

        _showSnack(data['message'] ?? 'Inscription réussie !', Colors.green);

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      } else {
        // Extraire le message d'erreur le plus précis possible
        String errorMessage = data['message'] ?? 'Erreur lors de l\'inscription';
        if (data['errors'] != null) {
          final errors = data['errors'] as Map<String, dynamic>;
          final first = errors.values
              .whereType<List>()
              .expand((e) => e)
              .map((e) => e.toString())
              .firstOrNull;
          if (first != null) errorMessage = first;
        }
        setState(() {
          _isVerifying = false;
          _errorMsg    = errorMessage;
        });
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMsg    = 'Erreur de connexion au serveur.';
      });
      debugPrint('[Register] Exception: $e');
    }
  }

  // ── Helpers UI ────────────────────────────────────────────────────────

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String get _maskedDisplay {
    if (_maskedId.isNotEmpty) return _maskedId;
    // Masquage de secours côté client
    final id = widget.identifier;
    if (widget.type == 'email') {
      final parts = id.split('@');
      if (parts.length != 2) return id;
      final local = parts[0];
      return '${local.substring(0, local.length.clamp(2, 2))}***@${parts[1]}';
    } else {
      if (id.length <= 4) return '****';
      return '${id.substring(0, 2)}${'*' * (id.length - 4)}${id.substring(id.length - 2)}';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final expired = _codeSent && _expirySeconds <= 0;
    final canResend = _codeSent && _resendSeconds <= 0 && !_isSending;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        title: const Text(
          'Vérification',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Icône ────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE63946), Color(0xFFFF6B6B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.primaryRed.withOpacity(0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.type == 'email'
                        ? Icons.mark_email_read_outlined
                        : Icons.sms_outlined,
                    size: 42,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                widget.type == 'email'
                    ? 'Vérifiez votre email'
                    : 'Vérifiez votre téléphone',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D3436),
                ),
              ),
              const SizedBox(height: 10),

              if (_isSending && !_codeSent)
                // Envoi en cours
                Column(children: [
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(color: AppConstants.primaryRed),
                  const SizedBox(height: 12),
                  Text(
                    'Envoi du code en cours...',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ])
              else if (!_codeSent && _errorMsg.isNotEmpty)
                // Erreur avant envoi (ex: email déjà utilisé)
                _buildErrorBanner()
              else ...[
                // Description
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF718096), height: 1.5),
                    children: [
                      const TextSpan(text: 'Code envoyé à\n'),
                      TextSpan(
                        text: _maskedDisplay,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppConstants.primaryRed),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Timer expiration ──────────────────────────────────
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: expired
                          ? Colors.red.withOpacity(0.08)
                          : AppConstants.primaryRed.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          expired
                              ? Icons.timer_off_outlined
                              : Icons.timer_outlined,
                          size: 16,
                          color: expired
                              ? Colors.red
                              : AppConstants.primaryRed,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          expired
                              ? 'Code expiré'
                              : 'Expire dans ${_formatTime(_expirySeconds)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: expired
                                ? Colors.red
                                : AppConstants.primaryRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Champs OTP ────────────────────────────────────────
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(
                      _shakeCtrl.isAnimating
                          ? (_shakeAnim.value % 10 < 5 ? 1 : -1) *
                              (_shakeAnim.value % 5)
                          : 0,
                      0,
                    ),
                    child: child,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, _buildOtpBox),
                  ),
                ),

                // ── Erreur ────────────────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _errorMsg.isNotEmpty
                      ? Padding(
                          key: ValueKey(_errorMsg),
                          padding: const EdgeInsets.only(top: 14),
                          child: _buildErrorBanner(),
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 20),

                // ── Coller ────────────────────────────────────────────
                Center(
                  child: TextButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste, size: 16),
                    label: const Text('Coller le code'),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF718096)),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Bouton Vérifier ───────────────────────────────────
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        (!_isOtpComplete || _isVerifying || expired || !_codeSent)
                            ? null
                            : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'VÉRIFIER LE CODE',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Renvoyer le code ──────────────────────────────────
                Center(
                  child: canResend
                      ? TextButton(
                          onPressed: _sendOtp,
                          style: TextButton.styleFrom(
                              foregroundColor: AppConstants.primaryRed),
                          child: const Text(
                            'Je n\'ai pas reçu le code → Renvoyer',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        )
                      : Text(
                          _isSending
                              ? 'Envoi en cours...'
                              : 'Renvoyer dans ${_formatTime(_resendSeconds)}',
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFA0AEC0)),
                        ),
                ),

                const SizedBox(height: 16),

                // ── Modifier les informations ──────────────────────────
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[600]),
                    child: const Text(
                      'Modifier mes informations',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget case OTP ───────────────────────────────────────────────────

  Widget _buildOtpBox(int index) {
    final hasValue = _controllers[index].text.isNotEmpty;

    return SizedBox(
      width: 46,
      height: 56,
      child: TextFormField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        maxLength: 1,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        enabled: _codeSent && !_isVerifying,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: _errorMsg.isNotEmpty
              ? Colors.red
              : const Color(0xFF2D3436),
        ),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: hasValue
              ? AppConstants.primaryRed.withOpacity(0.06)
              : const Color(0xFFF8F9FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _errorMsg.isNotEmpty
                  ? Colors.red.withOpacity(0.5)
                  : hasValue
                      ? AppConstants.primaryRed.withOpacity(0.4)
                      : Colors.transparent,
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _errorMsg.isNotEmpty
                  ? Colors.red
                  : AppConstants.primaryRed,
              width: 2,
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        onChanged: (v) => _onDigitChanged(index, v),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMsg,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}