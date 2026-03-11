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

    _3dController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _rotationX = Tween<double>(begin: -0.05, end: 0.05).animate(
      CurvedAnimation(parent: _3dController, curve: Curves.easeInOutSine),
    );

    _rotationY = Tween<double>(begin: -0.15, end: 0.15).animate(
      CurvedAnimation(parent: _3dController, curve: Curves.easeInOutQuart),
    );

    _rotationZ = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(parent: _3dController, curve: Curves.easeInOutSine),
    );

    _scale3d = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _3dController, curve: Curves.easeInOutSine),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

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
          // Arrière-plan avec dégradés de lumière
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppConstants.primaryRed.withOpacity(0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    
                    // Logo principal avec l'effet 3D
                    AnimatedBuilder(
                      animation: _3dController,
                      builder: (context, child) {
                        return Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002) // Perspective
                            ..rotateX(_rotationX.value)
                            ..rotateY(_rotationY.value)
                            ..rotateZ(_rotationZ.value)
                            ..scale(_scale3d.value),
                          alignment: Alignment.center,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Image.asset(
                              'assets/images/logo1.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 10),
                    
                    // Sous-titre
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAFC),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xFFEDF2F7)),
                      ),
                      child: const Text(
                        'Votre Automobile, Notre Expertise',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4A5568),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Petite description en italique
                    const Text(
                      'Des professionnels à votre service pour un entretien de qualité',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF718096),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    
                    const Spacer(flex: 3),
                    
                    // Boutons
                    Column(
                      children: [
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: ElevatedButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const LoginScreen()),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConstants.primaryRed,
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: AppConstants.primaryRed.withOpacity(0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Se connecter',
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(width: 10),
                                  Icon(Icons.arrow_forward_rounded),
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
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const RegisterScreen()),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2D3748),
                              side: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Créer un compte',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const Spacer(),
                    
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        'Conditions générales d\'utilisation',
                        style: TextStyle(
                          color: Color(0xFF718096),
                          decoration: TextDecoration.underline,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
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