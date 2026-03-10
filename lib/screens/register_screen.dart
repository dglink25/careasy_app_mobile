import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/screens/login_screen.dart';
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
    if (_formKey.currentState!.validate() && _acceptTerms) {
      setState(() {
        _isLoading = true;
      });

      try {
        Map<String, dynamic> userData = {
          'name': _nameController.text,
          'password': _passwordController.text,
          'password_confirmation': _confirmPasswordController.text,
        };

        if (_useEmail) {
          userData['email'] = _emailController.text;
        } else {
          userData['phone'] = _phoneController.text;
        }

        final response = await http.post(
          Uri.parse('${AppConstants.apiBaseUrl}/register'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(userData),
        ).timeout(const Duration(seconds: 15));

        final responseData = jsonDecode(response.body);

        if (response.statusCode == 201) {
          await _storage.write(key: 'auth_token', value: responseData['token']);
          await _storage.write(key: 'user_data', value: jsonEncode(responseData['user']));
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(responseData['message'] ?? 'Inscription réussie'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
            
            Navigator.pushReplacementNamed(context, '/home');
          }
        } else {
          String errorMessage = 'Erreur lors de l\'inscription';
          if (responseData['errors'] != null) {
            final errors = responseData['errors'] as Map;
            if (errors['email'] != null) {
              errorMessage = errors['email'][0];
            } else if (errors['phone'] != null) {
              errorMessage = errors['phone'][0];
            } else if (errors['contact'] != null) {
              errorMessage = errors['contact'][0];
            } else if (errors['name'] != null) {
              errorMessage = errors['name'][0];
            } else if (errors['password'] != null) {
              errorMessage = errors['password'][0];
            }
          } else if (responseData['message'] != null) {
            errorMessage = responseData['message'];
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur de connexion: ${e.toString()}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez accepter les conditions d\'utilisation'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
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
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back, 
              color: const Color(0xFF2D3436), 
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
                              width: isSmallScreen ? 60 : 80,
                              height: isSmallScreen ? 60 : 80,
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
                                          fontSize: isSmallScreen ? 24 : 32,
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
                    Center(
                      child: Text(
                        'Rejoignez CarEasy',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2D3436),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.01),
                    
                    Center(
                      child: Text(
                        'Créez votre compte',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 13,
                          color: const Color(0xFF718096),
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
                            child: _buildContactToggle(
                              true,
                              'Email',
                              Icons.email_outlined,
                              isSmallScreen,
                            ),
                          ),
                          Expanded(
                            child: _buildContactToggle(
                              false,
                              'Téléphone',
                              Icons.phone_outlined,
                              isSmallScreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: size.height * 0.02),
                    
                    // Nom complet
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Nom complet',
                        hintStyle: TextStyle(
                          color: const Color(0xFFA0AEC0), 
                          fontSize: isSmallScreen ? 13 : 14,
                        ),
                        prefixIcon: Icon(
                          Icons.person_outline, 
                          color: const Color(0xFF718096), 
                          size: isSmallScreen ? 18 : 20,
                        ),
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
                        contentPadding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 12 : 14, 
                          horizontal: 16,
                        ),
                      ),
                      style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Nom requis';
                        }
                        if (value.length < 2) {
                          return 'Nom trop court';
                        }
                        return null;
                      },
                    ),
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Champ conditionnel (Email ou Téléphone)
                    if (_useEmail) ...[
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          hintText: 'Adresse email',
                          hintStyle: TextStyle(
                            color: const Color(0xFFA0AEC0), 
                            fontSize: isSmallScreen ? 13 : 14,
                          ),
                          prefixIcon: Icon(
                            Icons.email_outlined, 
                            color: const Color(0xFF718096), 
                            size: isSmallScreen ? 18 : 20,
                          ),
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
                          contentPadding: EdgeInsets.symmetric(
                            vertical: isSmallScreen ? 12 : 14, 
                            horizontal: 16,
                          ),
                        ),
                        style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Email requis';
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Email invalide';
                          }
                          return null;
                        },
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          hintText: 'Numéro de téléphone',
                          hintStyle: TextStyle(
                            color: const Color(0xFFA0AEC0), 
                            fontSize: isSmallScreen ? 13 : 14,
                          ),
                          prefixIcon: Icon(
                            Icons.phone_outlined, 
                            color: const Color(0xFF718096), 
                            size: isSmallScreen ? 18 : 20,
                          ),
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
                          contentPadding: EdgeInsets.symmetric(
                            vertical: isSmallScreen ? 12 : 14, 
                            horizontal: 16,
                          ),
                        ),
                        style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Téléphone requis';
                          }
                          String clean = value.replaceAll(RegExp(r'[^0-9+]'), '');
                          if (clean.length < 8) {
                            return '8 chiffres minimum';
                          }
                          return null;
                        },
                      ),
                    ],
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Mot de passe
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        hintText: 'Mot de passe',
                        hintStyle: TextStyle(
                          color: const Color(0xFFA0AEC0), 
                          fontSize: isSmallScreen ? 13 : 14,
                        ),
                        prefixIcon: Icon(
                          Icons.lock_outline, 
                          color: const Color(0xFF718096), 
                          size: isSmallScreen ? 18 : 20,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF718096),
                            size: isSmallScreen ? 16 : 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
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
                        contentPadding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 12 : 14, 
                          horizontal: 16,
                        ),
                      ),
                      style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                      obscureText: !_isPasswordVisible,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Mot de passe requis';
                        }
                        if (value.length < 6) {
                          return '6 caractères minimum';
                        }
                        return null;
                      },
                    ),
                    
                    SizedBox(height: size.height * 0.015),
                    
                    // Confirmer mot de passe
                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: InputDecoration(
                        hintText: 'Confirmer mot de passe',
                        hintStyle: TextStyle(
                          color: const Color(0xFFA0AEC0), 
                          fontSize: isSmallScreen ? 13 : 14,
                        ),
                        prefixIcon: Icon(
                          Icons.lock_outline, 
                          color: const Color(0xFF718096), 
                          size: isSmallScreen ? 18 : 20,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF718096),
                            size: isSmallScreen ? 16 : 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                            });
                          },
                        ),
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
                        contentPadding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 12 : 14, 
                          horizontal: 16,
                        ),
                      ),
                      style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                      obscureText: !_isConfirmPasswordVisible,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirmation requise';
                        }
                        if (value != _passwordController.text) {
                          return 'Mots de passe différents';
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
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'J\'accepte les conditions d\'utilisation',
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
                            ? SizedBox(
                                height: isSmallScreen ? 18 : 20,
                                width: isSmallScreen ? 18 : 20,
                                child: const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'S\'INSCRIRE',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 14 : 15,
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
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Google bientôt disponible'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: Image.asset(
                          'assets/images/google_logo.png',
                          height: isSmallScreen ? 18 : 20,
                          width: isSmallScreen ? 18 : 20,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.g_mobiledata, 
                              size: isSmallScreen ? 20 : 22, 
                              color: Colors.grey,
                            );
                          },
                        ),
                        label: Text(
                          'Continuer avec Google',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 13 : 14,
                            color: const Color(0xFF2D3436),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

  Widget _buildContactToggle(bool isEmail, String label, IconData icon, bool isSmallScreen) {
    bool isSelected = _useEmail == isEmail;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _useEmail = isEmail;
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
              size: isSmallScreen ? 14 : 16,
              color: isSelected ? AppConstants.primaryRed : Colors.grey[500],
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppConstants.primaryRed : Colors.grey[500],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: isSmallScreen ? 12 : 13,
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

