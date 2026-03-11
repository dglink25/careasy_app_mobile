import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/screens/register_screen.dart';
import 'package:careasy_app_mobile/screens/home_screen.dart';
import 'package:careasy_app_mobile/screens/google_auth_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController(); // Un seul controller pour email/téléphone
  final _passwordController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _rememberMe = false;
  
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
    
    _checkRememberMe();
  }

  Future<void> _checkRememberMe() async {
    try {
      final rememberMe = await _storage.read(key: 'remember_me');
      if (rememberMe == 'true') {
        setState(() {
          _rememberMe = true;
        });
      }
    } catch (e) {
      print('Erreur lors de la vérification de remember_me: $e');
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Fonction pour détecter si l'entrée est un email ou un téléphone
  Map<String, String> _detectLoginType(String input) {
    String cleanInput = input.trim();
    
    // Regex pour email
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    
    if (emailRegex.hasMatch(cleanInput)) {
      // C'est un email
      return {
        'type': 'email',
        'value': cleanInput.toLowerCase(),
      };
    } else {
      // C'est probablement un téléphone - on nettoie
      String cleanPhone = cleanInput.replaceAll(RegExp(r'[^\d+]'), '');
      
      // Ajouter +221 si pas d'indicateur et commence par 7 (Sénégal)
      if (!cleanPhone.startsWith('+') && cleanPhone.isNotEmpty) {
        if (cleanPhone.startsWith('7')) {
          cleanPhone = '+221$cleanPhone';
        }
      }
      
      return {
        'type': 'phone',
        'value': cleanPhone,
      };
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Détecter le type de login (email ou téléphone)
      final loginInfo = _detectLoginType(_loginController.text);
      
      // Préparer les données pour l'API
      Map<String, dynamic> loginData = {
        'password': _passwordController.text,
      };
      
      // Ajouter le champ approprié selon le type détecté
      if (loginInfo['type'] == 'email') {
        loginData['email'] = loginInfo['value'];
      } else {
        loginData['phone'] = loginInfo['value'];
      }

      print('Tentative de connexion avec: ${loginInfo['type']} - ${loginInfo['value']}');

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(loginData),
      ).timeout(const Duration(seconds: 15));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Connexion réussie
        if (responseData['token'] != null) {
          await _storage.write(key: 'auth_token', value: responseData['token']);
          
          final now = DateTime.now().toIso8601String();
          await _storage.write(key: 'login_time', value: now);
          
          if (_rememberMe) {
            await _storage.write(key: 'remember_me', value: 'true');
          } else {
            await _storage.delete(key: 'remember_me');
          }
        }
        
        if (responseData['user'] != null) {
          await _storage.write(key: 'user_data', value: jsonEncode(responseData['user']));
        }
        
        if (mounted) {
          _showSnackBar('Connexion réussie !', Colors.green);
          
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      } else {
        String errorMessage = responseData['message'] ?? 
            'Email/Téléphone ou mot de passe incorrect';
        _showSnackBar(errorMessage, Colors.red);
      }
    } catch (e) {
      print('Erreur de connexion: $e');
      String errorMessage = 'Erreur de connexion au serveur';
      if (e.toString().contains('timed out')) {
        errorMessage = 'Délai d\'attente dépassé. Vérifiez votre connexion.';
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

  void _showForgotPasswordDialog() {
    final TextEditingController emailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Mot de passe oublié',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Entrez votre email pour recevoir un lien de réinitialisation',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  hintText: 'Votre email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (emailController.text.isNotEmpty) {
                  Navigator.pop(context);
                  _showSnackBar('Email envoyé ! Vérifiez votre boîte de réception', Colors.green);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Envoyer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 360;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Connexion',
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
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
                    // Logo
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
                        'Content de vous revoir !',
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
                        'Connectez-vous à votre compte',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.03),
                    
                    // Champ unique pour Email ou Téléphone
                    TextFormField(
                      controller: _loginController,
                      decoration: _inputDecoration(
                        hintText: 'Email ou numéro de téléphone',
                        icon: Icons.person_outline,
                      ),
                      keyboardType: TextInputType.emailAddress, // Accepte les deux
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Email ou téléphone requis';
                        }
                        
                        final loginInfo = _detectLoginType(value);
                        
                        if (loginInfo['type'] == 'email') {
                          // Validation email déjà faite par la regex
                          if (loginInfo['value']!.isEmpty) {
                            return 'Email invalide';
                          }
                        } else {
                          // Validation téléphone
                          if (loginInfo['value']!.length < 9) {
                            return 'Téléphone invalide (minimum 9 chiffres)';
                          }
                        }
                        
                        return null;
                      },
                    ),
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Champ Mot de passe
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
                    
                    SizedBox(height: size.height * 0.01),
                    
                    // Options: Se souvenir de moi et Mot de passe oublié
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Se souvenir de moi
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value ?? false;
                                });
                              },
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              activeColor: AppConstants.primaryRed,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            Text(
                              'Se souvenir de moi',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 11 : 12,
                                color: const Color(0xFF718096),
                              ),
                            ),
                          ],
                        ),
                        
                        // Mot de passe oublié
                        TextButton(
                          onPressed: _showForgotPasswordDialog,
                          style: TextButton.styleFrom(
                            foregroundColor: AppConstants.primaryRed,
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            'Mot de passe oublié ?',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 11 : 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: size.height * 0.02),
                    
                    // Bouton Connexion
                    SizedBox(
                      width: double.infinity,
                      height: isSmallScreen ? 45 : 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
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
                                'SE CONNECTER',
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
                    
                    // Bouton Google
                    SizedBox(
                      width: double.infinity,
                      height: isSmallScreen ? 45 : 50,
                      child: OutlinedButton(
                        onPressed: _handleGoogleSignIn,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 12),
                              child: const Icon(
                                Icons.g_mobiledata,
                                size: 28,
                                color: Color(0xFFDB4437),
                              ),
                            ),
                            Text(
                              'Continuer avec Google',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 13 : 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF3C4043),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.02),
                    
                    // Lien vers inscription
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Pas encore de compte ?',
                          style: TextStyle(
                            color: const Color(0xFF718096),
                            fontSize: isSmallScreen ? 12 : 13,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const RegisterScreen()),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppConstants.primaryRed,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: Text(
                            'S\'inscrire',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 12 : 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
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
}