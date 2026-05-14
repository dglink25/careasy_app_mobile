// lib/screens/change_contact_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';

enum ContactType { email, phone }

class ChangeContactScreen extends StatefulWidget {
  final ContactType type;
  final String? currentValue;

  const ChangeContactScreen({
    super.key,
    required this.type,
    this.currentValue,
  });

  @override
  State<ChangeContactScreen> createState() => _ChangeContactScreenState();
}

class _ChangeContactScreenState extends State<ChangeContactScreen>
    with SingleTickerProviderStateMixin {
  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

 
  int _step = 0;

  // Formulaire
  final _formKey   = GlobalKey<FormState>();
  final _inputCtrl = TextEditingController();

  // OTP
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List.generate(6, (_) => FocusNode());

  String?  _maskedContact;
  String?  _verifyToken;
  int      _resendAfter   = 60;
  int      _expiresIn     = 300;
  int      _countdown     = 0;
  Timer?   _timer;
  bool     _isLoading     = false;
  String?  _errorMessage;
  int?     _attemptsLeft;

  String _normalizeIdentifier(String raw) {
    if (widget.type == ContactType.email) return raw.trim().toLowerCase();
    
    String digits = raw.replaceAll(RegExp(r'\D'), '');
    // Retirer le code pays Bénin si présent
    if (digits.startsWith('229')) digits = digits.substring(3);
   
    if (RegExp(r'^0\d{9}$').hasMatch(digits)) return '+229$digits';
    // Format 8 chiffres → +22901XXXXXXXX
    if (RegExp(r'^\d{8}$').hasMatch(digits)) return '+22901$digits';
    return raw.trim();
  }

  // Animation
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    for (final c in _otpCtrls) { c.dispose(); }
    for (final n in _otpNodes)  { n.dispose(); }
    _timer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  // Helpers
  String get _typeLabel =>
      widget.type == ContactType.email ? 'email' : 'téléphone';

  String get _typeLabelCap =>
      widget.type == ContactType.email ? 'Email' : 'Téléphone';

  IconData get _typeIcon =>
      widget.type == ContactType.email ? Icons.email_outlined : Icons.phone_outlined;

  TextInputType get _keyboardType =>
      widget.type == ContactType.email
          ? TextInputType.emailAddress
          : TextInputType.phone;

  String? _validateInput(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ce champ est requis';
    if (widget.type == ContactType.email) {
      if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(v.trim())) {
        return 'Adresse email invalide';
      }
    } else {
      final digits = v.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8) return 'Numéro trop court (8 chiffres minimum)';
    }
    return null;
  }

  // Countdown
  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _countdown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _countdown--;
        if (_countdown <= 0) { t.cancel(); _countdown = 0; }
      });
    });
  }

  // Étape 1 : Envoyer l'OTP
  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final body = jsonEncode({
        'identifier': _normalizeIdentifier(_inputCtrl.text),
        'type': widget.type == ContactType.email ? 'email' : 'phone',
      });

      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/verify-contact/send'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200 && data['success'] == true) {
        _maskedContact  = data['masked']       as String?;
        _resendAfter    = (data['resend_after'] as num?)?.toInt() ?? 60;
        _expiresIn      = (data['expires_in']   as num?)?.toInt() ?? 300;
        _startCountdown(_resendAfter);

        await _animCtrl.reverse();
        setState(() => _step = 1);
        await _animCtrl.forward(from: 0);
        
        // Focus sur le premier champ OTP
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _otpNodes.isNotEmpty) {
            _otpNodes.first.requestFocus();
          }
        });
      } else {
        setState(() => _errorMessage =
            data['message'] as String? ?? 'Erreur lors de l\'envoi du code');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Erreur de connexion. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Étape 2 : Vérifier le code
  Future<void> _verifyOtp() async {
    final code = _otpCtrls.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Entrez les 6 chiffres du code');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/verify-contact/check'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'identifier': _normalizeIdentifier(_inputCtrl.text),
          'type': widget.type == ContactType.email ? 'email' : 'phone',
          'code': code,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200 && data['success'] == true) {
        _verifyToken = data['verify_token'] as String?;
        await _applyContactChange();
      } else {
        setState(() {
          _attemptsLeft = data['attempts_remaining'] as int?;
          _errorMessage = data['message'] as String? ?? 'Code invalide';
          // Vider les champs OTP
          for (final c in _otpCtrls) { c.clear(); }
          if (_otpNodes.isNotEmpty) _otpNodes.first.requestFocus();
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Erreur de connexion. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Étape 3 : Mettre à jour le contact
  Future<void> _applyContactChange() async {
    if (_verifyToken == null) return;
    setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'auth_token');
      
      Map<String, dynamic> requestBody;
      Uri url;
      
      if (widget.type == ContactType.email) {
        url = Uri.parse('${AppConstants.apiBaseUrl}/user/email');
        requestBody = {
          'email': _inputCtrl.text.trim(),
          'verify_token': _verifyToken,
        };
      } 
      else {
        url = Uri.parse('${AppConstants.apiBaseUrl}/user/phone');
        requestBody = {
          'phone': _normalizeIdentifier(_inputCtrl.text),
          'verify_token': _verifyToken,
        };
      }

      final resp = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        // Mettre à jour le cache local
        final stored = await _storage.read(key: 'user_data');
        if (stored != null) {
          final userData = jsonDecode(stored) as Map<String, dynamic>;
          if (widget.type == ContactType.email) {
            userData['email'] = _inputCtrl.text.trim();
          } else {
            userData['phone'] = _inputCtrl.text.trim();
          }
          await _storage.write(key: 'user_data', value: jsonEncode(userData));
        }

        await _animCtrl.reverse();
        setState(() => _step = 2);
        await _animCtrl.forward(from: 0);

        // Retourner true pour indiquer le succès à l'écran parent
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      } else {
        String msg = 'Erreur lors de la mise à jour';
        if (data['errors'] != null) {
          final errors = data['errors'] as Map<String, dynamic>;
          msg = errors.values.first[0]?.toString() ?? msg;
        } else if (data['message'] != null) {
          msg = data['message'] as String;
        }
        setState(() => _errorMessage = msg);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Erreur de connexion. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // OTP field handler
  void _onOtpChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _otpNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _otpNodes[index - 1].requestFocus();
    }
    // Auto-submit quand les 6 chiffres sont saisis
    if (_otpCtrls.every((c) => c.text.length == 1) && !_isLoading) {
      _verifyOtp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Modifier le $_typeLabel',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step == 1) {
              // Revenir à la saisie
              _animCtrl.reverse().then((_) {
                setState(() { _step = 0; _errorMessage = null; });
                _animCtrl.forward(from: 0);
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProgressIndicator(),
              const SizedBox(height: 32),
              if (_step == 0) _buildStepInput(),
              if (_step == 1) _buildStepOtp(),
              if (_step == 2) _buildStepSuccess(),
            ],
          ),
        ),
      ),
    );
  }

  // Indicateur de progression
  Widget _buildProgressIndicator() {
    return Row(
      children: List.generate(3, (i) {
        final active   = i <= _step;
        final current  = i == _step;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: current ? 6 : 4,
                  decoration: BoxDecoration(
                    color: active
                        ? AppConstants.primaryRed
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 4),
            ],
          ),
        );
      }),
    );
  }

  // Étape 0 : Saisie du nouveau contact
  Widget _buildStepInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(
          icon: _typeIcon,
          title: 'Nouveau $_typeLabel',
          subtitle: 'Entrez votre nouveau $_typeLabel.\nUn code de vérification vous sera envoyé.',
        ),
        const SizedBox(height: 32),
        Form(
          key: _formKey,
          child: _buildTextField(
            controller: _inputCtrl,
            label: _typeLabelCap,
            icon: _typeIcon,
            keyboardType: _keyboardType,
            validator: _validateInput,
          ),
        ),
        if (_errorMessage != null) _buildError(_errorMessage!),
        const SizedBox(height: 28),
        _buildPrimaryButton(
          label: 'Envoyer le code',
          icon: Icons.send_rounded,
          onPressed: _isLoading ? null : _sendOtp,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  // Étape 1 : Saisie du code OTP
  Widget _buildStepOtp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(
          icon: Icons.lock_outline,
          title: 'Code de vérification',
          subtitle: _maskedContact != null
              ? 'Un code à 6 chiffres a été envoyé à\n$_maskedContact'
              : 'Un code à 6 chiffres a été envoyé',
        ),
        const SizedBox(height: 36),
        _buildOtpFields(),
        if (_attemptsLeft != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$_attemptsLeft tentative(s) restante(s)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        if (_errorMessage != null) _buildError(_errorMessage!),
        const SizedBox(height: 28),
        _buildPrimaryButton(
          label: 'Vérifier le code',
          icon: Icons.check_circle_outline,
          onPressed: _isLoading ? null : _verifyOtp,
          isLoading: _isLoading,
        ),
        const SizedBox(height: 16),
        _buildResendButton(),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            _animCtrl.reverse().then((_) {
              setState(() { _step = 0; _errorMessage = null; });
              _animCtrl.forward(from: 0);
            });
          },
          child: Text(
            'Changer de $_typeLabel',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildResendButton() {
    if (_countdown > 0) {
      return Center(
        child: Text(
          'Renvoyer dans ${_countdown}s',
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
        ),
      );
    }
    return Center(
      child: TextButton.icon(
        onPressed: _isLoading ? null : _sendOtp,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Renvoyer le code'),
        style: TextButton.styleFrom(foregroundColor: AppConstants.primaryRed),
      ),
    );
  }

  // Étape 2 : Succès
  Widget _buildStepSuccess() {
    return Column(
      children: [
        const SizedBox(height: 40),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green[50],
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 64),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '$_typeLabelCap mis à jour !',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Votre $_typeLabel a été modifié avec succès.',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Redirection en cours…',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  // Widgets de construction
  Widget _buildHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppConstants.primaryRed.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: AppConstants.primaryRed, size: 28),
        ),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.5)),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.07),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            validator: validator,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              prefixIcon:
                  Icon(icon, color: AppConstants.primaryRed, size: 20),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              hintText: 'Entrez votre nouveau $label',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpFields() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(6, (i) {
        return SizedBox(
          width: 46,
          height: 58,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _otpCtrls[i].text.isNotEmpty
                    ? AppConstants.primaryRed
                    : Colors.grey[300]!,
                width: _otpCtrls[i].text.isNotEmpty ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.07),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextFormField(
              controller: _otpCtrls[i],
              focusNode: _otpNodes[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                setState(() {});
                _onOtpChanged(v, i);
              },
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey[300],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}