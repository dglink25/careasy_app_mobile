import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import 'new_password_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String identifier;
  final String identifierType; // 'email' | 'phone'
  final int    expiresIn;      // secondes
  final int    resendAfter;    // secondes

  const OtpVerificationScreen({
    super.key,
    required this.identifier,
    required this.identifierType,
    required this.expiresIn,
    required this.resendAfter,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with TickerProviderStateMixin {
  // ── 6 champs OTP ─────────────────────────────────────────────────────────
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool   _isLoading  = false;
  bool   _isResending = false;
  String _errorMsg   = '';

  // ── Timer expiration ──────────────────────────────────────────────────────
  late int _secondsLeft;
  late int _resendSecondsLeft;
  Timer?  _expiryTimer;
  Timer?  _resendTimer;

  // ── Animation shake pour erreur ───────────────────────────────────────────
  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  @override
  void initState() {
    super.initState();
    _secondsLeft      = widget.expiresIn;
    _resendSecondsLeft = widget.resendAfter;

    _startExpiryTimer();
    _startResendTimer();

    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 24).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );

    // Focus sur le premier champ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
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

  // ── Timers ────────────────────────────────────────────────────────────────

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 0) {
        _expiryTimer?.cancel();
        setState(() {});
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendSecondsLeft = widget.resendAfter;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_resendSecondsLeft <= 0) {
        _resendTimer?.cancel();
        setState(() {});
        return;
      }
      setState(() => _resendSecondsLeft--);
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Lecture OTP saisi ─────────────────────────────────────────────────────

  String get _currentOtp => _controllers.map((c) => c.text).join();

  bool get _isOtpComplete => _currentOtp.length == 6;

  // ── Saisie dans les cases ─────────────────────────────────────────────────

  void _onDigitChanged(int index, String value) {
    if (value.length == 1) {
      // Avancer au champ suivant
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        // Soumettre automatiquement quand le 6e chiffre est saisi
        if (_isOtpComplete) _verifyOtp();
      }
    } else if (value.isEmpty && index > 0) {
      // Reculer au champ précédent
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _errorMsg = '');
  }

  // ── Coller depuis le presse-papiers ──────────────────────────────────────

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

  // ── Vider les champs ──────────────────────────────────────────────────────

  void _clearFields() {
    for (final c in _controllers) c.clear();
    setState(() => _errorMsg = '');
    _focusNodes[0].requestFocus();
  }

  // ── Vérification OTP ──────────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    if (!_isOtpComplete || _isLoading) return;

    if (_secondsLeft <= 0) {
      setState(() => _errorMsg = 'Code expiré. Demandez-en un nouveau.');
      return;
    }

    setState(() { _isLoading = true; _errorMsg = ''; });

    try {
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/forgot-password/otp/verify'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'identifier': widget.identifier,
          'code'       : _currentOtp,
        }),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (!mounted) return;

      if (resp.statusCode == 200 && body['success'] == true) {
        // Naviguer vers l'écran de nouveau mot de passe
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => NewPasswordScreen(
              resetToken: body['reset_token'] as String,
              expiresIn : (body['expires_in'] as num?)?.toInt() ?? 600,
            ),
          ),
        );
      } else {
        final code = body['code'] ?? '';

        if (code == 'OTP_EXPIRED' || code == 'MAX_ATTEMPTS') {
          _clearFields();
        }

        setState(() => _errorMsg = body['message'] ?? 'Code incorrect.');
        _shakeCtrl.forward(from: 0);
      }
    } catch (e) {
      setState(() => _errorMsg = 'Erreur réseau. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Renvoi du code ────────────────────────────────────────────────────────

  Future<void> _resendOtp() async {
    if (_resendSecondsLeft > 0 || _isResending) return;

    setState(() => _isResending = true);

    try {
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/forgot-password/otp/resend'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'identifier': widget.identifier}),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (!mounted) return;

      if (resp.statusCode == 200 && body['success'] == true) {
        // Réinitialiser les timers
        setState(() {
          _secondsLeft = (body['expires_in'] as num?)?.toInt() ?? widget.expiresIn;
          _errorMsg    = '';
        });
        _clearFields();
        _startExpiryTimer();
        _startResendTimer();
        _showSuccess('Un nouveau code a été envoyé !');
      } else if (resp.statusCode == 429) {
        final wait = body['wait_seconds'] ?? 60;
        setState(() {
          _resendSecondsLeft = wait;
          _errorMsg = body['message'] ?? 'Attendez avant de renvoyer.';
        });
        _startResendTimer();
      } else {
        setState(() => _errorMsg = body['message'] ?? 'Erreur lors du renvoi.');
      }
    } catch (e) {
      setState(() => _errorMsg = 'Erreur réseau. Réessayez.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Masquer l'identifiant ─────────────────────────────────────────────────

  String get _maskedIdentifier {
    final id = widget.identifier;
    if (widget.identifierType == 'email') {
      final parts = id.split('@');
      if (parts.length != 2) return id;
      final local = parts[0];
      final domain = parts[1];
      if (local.length <= 3) return '***@$domain';
      return '${local.substring(0, 2)}***@$domain';
    } else {
      if (id.length <= 4) return '****';
      return '${id.substring(0, id.length - 4).replaceAll(RegExp(r'\d'), '*')}${id.substring(id.length - 4)}';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final expired = _secondsLeft <= 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        title: const Text('Vérification',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
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
                  child: Icon(
                    widget.identifierType == 'email'
                        ? Icons.mark_email_read_outlined
                        : Icons.sms_outlined,
                    size: 42, color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                widget.identifierType == 'email'
                    ? 'Vérifiez votre email'
                    : 'Vérifiez vos SMS',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800,
                    color: Color(0xFF2D3436)),
              ),
              const SizedBox(height: 10),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF718096), height: 1.5),
                  children: [
                    const TextSpan(text: 'Nous avons envoyé un code à\n'),
                    TextSpan(
                      text: _maskedIdentifier,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppConstants.primaryRed),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // ── Timer ───────────────────────────────────────────────────────
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: expired
                        ? Colors.red.withOpacity(0.08)
                        : AppConstants.primaryRed.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        expired ? Icons.timer_off_outlined : Icons.timer_outlined,
                        size: 18,
                        color: expired ? Colors.red : AppConstants.primaryRed,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        expired
                            ? 'Code expiré'
                            : 'Expire dans ${_formatTime(_secondsLeft)}',
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: expired ? Colors.red : AppConstants.primaryRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Champs OTP ──────────────────────────────────────────────────
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (ctx, child) => Transform.translate(
                  offset: Offset(
                    _shakeCtrl.isAnimating
                        ? ((_shakeAnim.value % 12 < 6 ? 1 : -1) * (_shakeAnim.value % 6))
                        : 0,
                    0,
                  ),
                  child: child,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (i) => _buildOtpBox(i)),
                ),
              ),

              // ── Message d'erreur ────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _errorMsg.isNotEmpty
                    ? Padding(
                        key: ValueKey(_errorMsg),
                        padding: const EdgeInsets.only(top: 14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_errorMsg,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 24),

              // ── Coller ──────────────────────────────────────────────────────
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

              // ── Bouton Vérifier ─────────────────────────────────────────────
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: (!_isOtpComplete || _isLoading || expired)
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
                  child: _isLoading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('VÉRIFIER LE CODE',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                ),
              ),

              const SizedBox(height: 20),

              // ── Renvoi du code ──────────────────────────────────────────────
              Center(
                child: _resendSecondsLeft > 0
                    ? Text(
                        'Renvoyer dans ${_resendSecondsLeft}s',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFFA0AEC0)),
                      )
                    : TextButton(
                        onPressed: _isResending ? null : _resendOtp,
                        style: TextButton.styleFrom(
                            foregroundColor: AppConstants.primaryRed),
                        child: _isResending
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text(
                                'Je n\'ai pas reçu le code → Renvoyer',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget case OTP ───────────────────────────────────────────────────────

  Widget _buildOtpBox(int index) {
    final hasValue = _controllers[index].text.isNotEmpty;
    final isFocused = _focusNodes[index].hasFocus;

    return SizedBox(
      width: 46, height: 56,
      child: TextFormField(
        controller: _controllers[index],
        focusNode : _focusNodes[index],
        textAlign : TextAlign.center,
        maxLength : 1,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w800,
          color: _errorMsg.isNotEmpty ? Colors.red : const Color(0xFF2D3436),
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
        ),
        onChanged: (v) => _onDigitChanged(index, v),
      ),
    );
  }
}