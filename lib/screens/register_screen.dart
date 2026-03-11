import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/screens/login_screen.dart';
import 'package:careasy_app_mobile/screens/home_screen.dart';
import 'package:careasy_app_mobile/screens/google_auth_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  bool _useEmail = true;
  bool _acceptTerms = false;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_acceptTerms) {
      _showSnackBar('Veuillez accepter les conditions d\'utilisation', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> userData = {
        'name': _nameController.text.trim(),
        'password': _passwordController.text,
        'password_confirmation': _confirmPasswordController.text,
      };

      if (_useEmail) {
        userData['email'] = _emailController.text.trim().toLowerCase();
      } else {
        // Nettoyer le numéro de téléphone
        String phone = _phoneController.text.trim().replaceAll(RegExp(r'\s+'), '');
        userData['phone'] = phone;
      }

      print('Envoi des données vers: ${AppConstants.apiBaseUrl}/register');
      print('Données: $userData');

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(userData),
      ).timeout(const Duration(seconds: 15));

      print('Statut: ${response.statusCode}');
      print('Réponse: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Succès de l'inscription
        if (responseData['token'] != null) {
          await _storage.write(key: 'auth_token', value: responseData['token']);
        }
        
        if (responseData['user'] != null) {
          await _storage.write(key: 'user_data', value: jsonEncode(responseData['user']));
        }
        
        if (mounted) {
          _showSnackBar(
            responseData['message'] ?? 'Inscription réussie !', 
            Colors.green
          );
          
          // Rediriger vers l'écran d'accueil
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      } else {
        // Gestion des erreurs
        String errorMessage = _extractErrorMessage(responseData);
        _showSnackBar(errorMessage, Colors.red);
      }
    } catch (e) {
      print('Exception: $e');
      String errorMessage = 'Erreur de connexion au serveur';
      
      if (e.toString().contains('timed out')) {
        errorMessage = 'Délai d\'attente dépassé. Vérifiez votre connexion.';
      } else if (e.toString().contains('SocketException')) {
        errorMessage = 'Impossible de joindre le serveur. Vérifiez que le serveur est démarré.';
      }
      
      if (mounted) {
        _showSnackBar(errorMessage, Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _extractErrorMessage(Map<String, dynamic> responseData) {
    if (responseData['errors'] != null) {
      final errors = responseData['errors'] as Map;
      if (errors['email'] != null) return errors['email'][0];
      if (errors['phone'] != null) return errors['phone'][0];
      if (errors['contact'] != null) return errors['contact'][0];
      if (errors['name'] != null) return errors['name'][0];
      if (errors['password'] != null) return errors['password'][0];
    }
    
    return responseData['message'] ?? 'Erreur lors de l\'inscription';
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

  Future<void> _handleGoogleSignIn() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GoogleAuthScreen()),
    );

    if (result == true && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 360;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Inscription',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: isSmallScreen ? 16 : 18,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppConstants.primaryRed,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back, 
              color: Colors.white, 
              size: isSmallScreen ? 16 : 18,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        height: size.height - MediaQuery.of(context).padding.top - kToolbarHeight - MediaQuery.of(context).padding.bottom,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: size.width * 0.05,
            vertical: isSmallScreen ? 12 : 16,
          ),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo - Correction du chemin d'image
                    Center(
                      child: TweenAnimationBuilder(
                        duration: const Duration(milliseconds: 800),
                        tween: Tween<double>(begin: 0, end: 1),
                        curve: Curves.elasticOut,
                        builder: (context, double value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Container(
                              width: isSmallScreen ? 80 : 100,
                              height: isSmallScreen ? 80 : 100,
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
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Fallback si l'image ne se charge pas
                                    return Center(
                                      child: Text(
                                        'CE',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 36 : 42,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.02),
                    
                    // Message de bienvenue
                    const Center(
                      child: Text(
                        'Rejoignez CarEasy',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.01),
                    
                    const Center(
                      child: Text(
                        'Créez votre compte pour commencer',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.03),
                    
                    // Mode de contact
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildContactToggle(true, 'Email', Icons.email_outlined),
                          ),
                          Expanded(
                            child: _buildContactToggle(false, 'Téléphone', Icons.phone_outlined),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.02),
                    
                    // Nom complet
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration(
                        hintText: 'Nom complet',
                        icon: Icons.person_outline,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Nom requis';
                        }
                        if (value.trim().length < 2) {
                          return 'Nom trop court (minimum 2 caractères)';
                        }
                        return null;
                      },
                    ),
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Champ conditionnel (Email ou Téléphone)
                    if (_useEmail) ...[
                      TextFormField(
                        controller: _emailController,
                        decoration: _inputDecoration(
                          hintText: 'Adresse email',
                          icon: Icons.email_outlined,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email requis';
                          }
                          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Email invalide';
                          }
                          return null;
                        },
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _phoneController,
                        decoration: _inputDecoration(
                          hintText: 'Numéro de téléphone',
                          icon: Icons.phone_outlined,
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Téléphone requis';
                          }
                          String clean = value.replaceAll(RegExp(r'[^0-9+]'), '');
                          if (clean.length < 8) {
                            return 'Minimum 8 chiffres';
                          }
                          if (clean.length > 15) {
                            return 'Maximum 15 chiffres';
                          }
                          return null;
                        },
                      ),
                    ],
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Mot de passe
                    TextFormField(
                      controller: _passwordController,
                      decoration: _inputDecoration(
                        hintText: 'Mot de passe',
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF718096),
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                      ),
                      obscureText: !_isPasswordVisible,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Mot de passe requis';
                        }
                        if (value.length < 6) {
                          return 'Minimum 6 caractères';
                        }
                        return null;
                      },
                    ),
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Confirmer mot de passe
                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: _inputDecoration(
                        hintText: 'Confirmer le mot de passe',
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF718096),
                          ),
                          onPressed: () {
                            setState(() {
                              _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                            });
                          },
                        ),
                      ),
                      obscureText: !_isConfirmPasswordVisible,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirmation requise';
                        }
                        if (value != _passwordController.text) {
                          return 'Les mots de passe ne correspondent pas';
                        }
                        return null;
                      },
                    ),
                    
                    SizedBox(height: size.height * 0.01),
                    
                    // Conditions d'utilisation
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acceptTerms,
                          onChanged: (value) {
                            setState(() {
                              _acceptTerms = value ?? false;
                            });
                          },
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          activeColor: AppConstants.primaryRed,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'J\'accepte les conditions d\'utilisation et la politique de confidentialité',
                              style: TextStyle(
                                color: const Color(0xFF718096),
                                fontSize: isSmallScreen ? 11 : 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: size.height * 0.02),
                    
                    // Bouton d'inscription
                    SizedBox(
                      width: double.infinity,
                      height: isSmallScreen ? 45 : 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'S\'INSCRIRE',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Séparateur
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey[300])),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'ou',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: isSmallScreen ? 12 : 13,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey[300])),
                      ],
                    ),
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Bouton Google - Design amélioré
                    SizedBox(
                      width: double.infinity,
                      height: isSmallScreen ? 45 : 50,
                      child: OutlinedButton(
                        onPressed: _handleGoogleSignIn,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[400]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Logo Google stylisé
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: const Icon(
                                Icons.g_mobiledata,
                                size: 28,
                                color: Color(0xFFDB4437), // Rouge Google
                              ),
                            ),
                            Text(
                              'Continuer avec Google',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 13 : 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF3C4043), // Gris foncé
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.02),
                    
                    // Lien vers connexion
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Déjà un compte ?',
                          style: TextStyle(
                            color: const Color(0xFF718096),
                            fontSize: isSmallScreen ? 12 : 13,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppConstants.primaryRed,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: Text(
                            'Se connecter',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 12 : 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    // Espace supplémentaire pour éviter le scroll inutile
                    SizedBox(height: size.height * 0.02),
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
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF718096), size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppConstants.primaryRed, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );
  }

  Widget _buildContactToggle(bool isEmail, String label, IconData icon) {
    bool isSelected = _useEmail == isEmail;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _useEmail = isEmail;
          // Effacer le champ non utilisé
          if (isEmail) {
            _phoneController.clear();
          } else {
            _emailController.clear();
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppConstants.primaryRed : Colors.grey[500],
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppConstants.primaryRed : Colors.grey[500],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}