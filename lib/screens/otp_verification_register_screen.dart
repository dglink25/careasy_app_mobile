// screens/otp_verification_screen.dart
import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/services/otp_service.dart';
import 'package:careasy_app_mobile/screens/home_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';  // ← AJOUTER CET IMPORT

class OtpVerificationRegisterScreen extends StatefulWidget {
  final String identifier;
  final String type;
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
  State<OtpVerificationRegisterScreen> createState() => _OtpVerificationRegisterScreenState();
}

class _OtpVerificationRegisterScreenState extends State<OtpVerificationRegisterScreen> {
  final _otpController = TextEditingController();
  final _otpService = OtpService();
  final _storage = const FlutterSecureStorage();  // ← AJOUTER CETTE LIGNE
  bool _isLoading = false;
  bool _isResending = false;
  int _resendCooldown = 0;
  String? _errorMessage;
  String? _maskedIdentifier;

  @override
  void initState() {
    super.initState();
    _sendOtpCode();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtpCode() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    final result = await _otpService.sendOtp(
      identifier: widget.identifier,
      type: widget.type,
    );

    if (mounted) {
      setState(() {
        _isResending = false;
        if (result['success']) {
          _maskedIdentifier = result['data']['masked'];
          _startResendCooldown(result['data']['resend_after'] ?? 60);
          _showSnackBar(result['data']['message'], Colors.green);
        } else {
          _errorMessage = result['message'];
        }
      });
    }
  }

  void _startResendCooldown(int seconds) {
    _resendCooldown = seconds;
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resendCooldown > 0) {
        setState(() {
          _resendCooldown--;
        });
        _startResendCooldown(_resendCooldown);
      }
    });
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Le code doit contenir 6 chiffres';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _otpService.verifyOtp(
      identifier: widget.identifier,
      type: widget.type,
      code: code,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (result['success']) {
        // Procéder à l'inscription avec le verify_token
        await _completeRegistration(result['verifyToken']);
      } else {
        setState(() {
          _errorMessage = result['message'];
        });
        if (result['attemptsRemaining'] != null) {
          _showSnackBar(
            '${result['message']} (${result['attemptsRemaining']} tentative(s) restante(s))',
            Colors.orange,
          );
        }
      }
    }
  }

  Future<void> _completeRegistration(String verifyToken) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': widget.name,
          'password': widget.password,
          'password_confirmation': widget.confirmPassword,
          'verify_token': verifyToken,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (responseData['token'] != null) {
          await _storage.write(key: 'auth_token', value: responseData['token']);
        }
        
        if (responseData['user'] != null) {
          await _storage.write(key: 'user_data', value: jsonEncode(responseData['user']));
        }
        
        if (mounted) {
          _showSnackBar(responseData['message'] ?? 'Inscription réussie !', Colors.green);
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      } else {
        String errorMessage = responseData['message'] ?? 'Erreur lors de l\'inscription';
        if (mounted) {
          _showSnackBar(errorMessage, Colors.red);
        }
      }
    } catch (e) {
      print('Erreur inscription: $e');
      if (mounted) {
        _showSnackBar('Erreur de connexion au serveur', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Vérification'),
        backgroundColor: AppConstants.primaryRed,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.05,
          vertical: size.height * 0.05,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon
            Icon(
              Icons.verified_user_outlined,
              size: 80,
              color: AppConstants.primaryRed,
            ),
            SizedBox(height: size.height * 0.03),
            
            // Title
            const Text(
              'Vérification en deux étapes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: size.height * 0.01),
            
            // Description
            Text(
              _maskedIdentifier != null
                  ? 'Un code de vérification à 6 chiffres a été envoyé à\n$_maskedIdentifier'
                  : 'Envoi du code de vérification...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: size.height * 0.05),
            
            // OTP Input
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: 'Entrez le code à 6 chiffres',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
                errorText: _errorMessage,
                errorStyle: const TextStyle(fontSize: 12),
              ),
            ),
            SizedBox(height: size.height * 0.03),
            
            // Verify Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'VÉRIFIER',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            SizedBox(height: size.height * 0.02),
            
            // Resend Button
            TextButton(
              onPressed: _resendCooldown > 0 || _isResending ? null : _sendOtpCode,
              child: Text(
                _resendCooldown > 0
                    ? 'Renvoyer le code (${_resendCooldown}s)'
                    : 'Renvoyer le code',
                style: TextStyle(
                  color: _resendCooldown > 0 ? Colors.grey : AppConstants.primaryRed,
                  fontSize: 14,
                ),
              ),
            ),
            
            // Back to register
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Modifier les informations',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}