import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/screens/login_screen.dart';
import 'package:careasy_app_mobile/screens/register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  late AnimationController _3dController;
  late AnimationController _pulseController;
  late AnimationController _slideController;
  
  late Animation<double> _rotationX;
  late Animation<double> _rotationY;
  late Animation<double> _rotationZ;
  late Animation<double> _scale3d;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Contrôleur 3D sophistiqué pour CarEasy
    _3dController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    // Animation 3D complexe mais élégante
    _rotationX = Tween<double>(begin: -0.06, end: 0.06).animate(
      CurvedAnimation(parent: _3dController, curve: Curves.easeInOutSine),
    );

    _rotationY = Tween<double>(begin: -0.1, end: 0.1).animate(
      CurvedAnimation(parent: _3dController, curve: Curves.easeInOutQuart),
    );

    _rotationZ = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(parent: _3dController, curve: Curves.easeInOutSine),
    );

    _scale3d = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _3dController, curve: Curves.easeInOutSine),
    );

    // Animation pulse subtile pour les boutons
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Animation slide pour les éléments
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutQuint,
    ));
  }

  @override
  void dispose() {
    _3dController.dispose();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Effets de lumière sophistiqués
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppConstants.primaryRed.withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppConstants.primaryRed.withOpacity(0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Contenu principal
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    
                    // Logo STATIQUE avec design premium
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            Color(0xFFFAFAFA),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 30,
                            spreadRadius: 0,
                            offset: const Offset(0, 15),
                          ),
                          BoxShadow(
                            color: AppConstants.primaryRed.withOpacity(0.15),
                            blurRadius: 25,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppConstants.primaryRed,
                                    AppConstants.primaryRed.withOpacity(0.8),
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'CE',
                                  style: TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Nom CarEasy en 3D animé sophistiqué
                    AnimatedBuilder(
                      animation: _3dController,
                      builder: (context, child) {
                        return Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.003)
                            ..rotateX(_rotationX.value)
                            ..rotateY(_rotationY.value)
                            ..rotateZ(_rotationZ.value)
                            ..scale(_scale3d.value),
                          alignment: Alignment.center,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Ombres multiples pour effet de profondeur
                              Positioned(
                                left: 6,
                                top: 6,
                                child: Text(
                                  'CarEasy',
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 3
                                      ..color = Colors.black.withOpacity(0.1),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 3,
                                top: 3,
                                child: Text(
                                  'CarEasy',
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 2
                                      ..color = Colors.black.withOpacity(0.15),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                              
                              // Texte principal avec effet métallique
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: const [
                                    Color(0xFFE63946),
                                    Color(0xFFFF8A8A),
                                    Color(0xFFC92A3A),
                                    Color(0xFFE63946),
                                  ],
                                  stops: const [0.0, 0.3, 0.7, 1.0],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds),
                                child: Text(
                                  'CarEasy',
                                  style: const TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                    shadows: [
                                      Shadow(
                                        color: Color(0x33E63946),
                                        blurRadius: 20,
                                        offset: Offset(4, 4),
                                      ),
                                      Shadow(
                                        color: Color(0x1AE63946),
                                        blurRadius: 30,
                                        offset: Offset(8, 8),
                                      ),
                                      Shadow(
                                        color: Color(0x0DE63946),
                                        blurRadius: 40,
                                        offset: Offset(12, 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              // Reflet lumineux
                              Positioned(
                                top: -10,
                                left: 0,
                                child: Text(
                                  'CarEasy',
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 0.5
                                      ..color = Colors.white.withOpacity(0.5),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Sous-titre avec design moderne
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFF8F9FA),
                            const Color(0xFFEDF2F7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Text(
                        'La mobilité intelligente',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4A5568),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    
                    const Spacer(flex: 3),
                    
                    // Boutons avec effet de pulse
                    Column(
                      children: [
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConstants.primaryRed,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shadowColor: AppConstants.primaryRed.withOpacity(0.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Text(
                                    'Se connecter',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const RegisterScreen()),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2D3748),
                              side: BorderSide(
                                color: const Color(0xFFE2E8F0),
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  'Créer un compte',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.person_add_outlined, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const Spacer(),
                    
                    // Lien CGU
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF718096),
                      ),
                      child: const Text(
                        'Conditions générales d\'utilisation',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFFCBD5E0),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
