import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/screens/login_screen.dart';
import 'package:careasy_app_mobile/screens/register_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/auth_provider.dart';

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

  void _openQRLoginSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QRLoginSheet(
        onSuccess: (token, userData) async {
          Navigator.pop(context); // fermer la sheet
          await context.read<AuthProvider>().login(token, userData);
          if (mounted) Navigator.pushReplacementNamed(context, '/home');
        },
      ),
    );
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

                    // Logo principal avec effet 3D
                    AnimatedBuilder(
                      animation: _3dController,
                      builder: (context, child) {
                        return Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002)
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

                    // Boutons principaux
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
                                MaterialPageRoute(builder: (_) => const LoginScreen()),
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

                        const SizedBox(height: 14),

                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: OutlinedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RegisterScreen()),
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

                        const SizedBox(height: 14),

                        // ── BOUTON QR LOGIN ──────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: _openQRLoginSheet,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppConstants.primaryRed,
                              side: BorderSide(
                                  color: AppConstants.primaryRed.withOpacity(0.4),
                                  width: 1.5),
                              backgroundColor: AppConstants.primaryRed.withOpacity(0.04),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppConstants.primaryRed.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.qr_code_scanner_rounded,
                                      size: 18),
                                ),
                                const SizedBox(width: 10),
                                const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Connexion rapide via QR code',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      'Scannez depuis un appareil déjà connecté',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w400),
                                    ),
                                  ],
                                ),
                              ],
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

// ════════════════════════════════════════════════════════════════════════════
//  QR LOGIN SHEET — Scanner un QR code généré depuis un autre appareil
// ════════════════════════════════════════════════════════════════════════════

class _QRLoginSheet extends StatefulWidget {
  final Future<void> Function(String token, Map<String, dynamic> userData) onSuccess;

  const _QRLoginSheet({required this.onSuccess});

  @override
  State<_QRLoginSheet> createState() => _QRLoginSheetState();
}

class _QRLoginSheetState extends State<_QRLoginSheet>
    with SingleTickerProviderStateMixin {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
      aOptions: _androidOptions, iOptions: _iOSOptions);

  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  bool _scannerReady = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _success = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _initScanner();
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    setState(() => _scannerReady = true);
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || _success) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final raw = barcode!.rawValue!;

    // Décoder le QR
    Map<String, dynamic>? qrData;
    try {
      qrData = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // QR invalide, ignorer silencieusement
      return;
    }

    // Vérifier que c'est bien un QR CarEasy
    if (qrData['type'] != 'careasy_session_share') return;
    final shareToken = qrData['token']?.toString();
    if (shareToken == null || shareToken.isEmpty) return;

    setState(() => _isProcessing = true);
    await _scannerController?.stop();

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/auth/qr-login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'share_token': shareToken}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token']?.toString();
        final userData = data['user'] as Map<String, dynamic>?;

        if (token != null && userData != null) {
          setState(() => _success = true);
          await Future.delayed(const Duration(milliseconds: 800));
          await widget.onSuccess(token, userData);
          return;
        }
      }

      // Erreur serveur
      final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      setState(() {
        _isProcessing = false;
        _hasError = true;
        _errorMessage = body['message'] ?? 'QR code invalide ou expiré.';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _hasError = true;
        _errorMessage = 'Erreur de connexion. Vérifiez votre réseau.';
      });
    }
  }

  void _resetScan() {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isProcessing = false;
      _success = false;
    });
    _scannerController?.start();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 14, bottom: 6),
            decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppConstants.primaryRed,
                        AppConstants.primaryRed.withOpacity(0.7)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: AppConstants.primaryRed.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connexion rapide',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Scannez le QR code depuis votre autre appareil',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.grey[400]),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: _buildBody(),
          ),

          // Footer info
          if (!_success && !_hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: Colors.blue[600]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sur l\'appareil connecté : Paramètres > Sécurité > Appareils connectés > Ajouter via QR',
                        style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_success) return _buildSuccess();
    if (_hasError) return _buildError();
    if (_isProcessing) return _buildProcessing();
    return _buildScanner();
  }

  Widget _buildScanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Viewfinder avec animation
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Fond flou derrière le scanner
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: _scannerReady
                          ? MobileScanner(
                              controller: _scannerController!,
                              onDetect: _onDetect,
                            )
                          : Container(color: Colors.black),
                    ),
                  ),

                  // Overlay sombre avec découpe centrale
                  _ScannerOverlay(),

                  // Coins animés du viewfinder
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          children: [
                            // Coin haut gauche
                            Positioned(
                              top: 0, left: 0,
                              child: _ScanCorner(topLeft: true),
                            ),
                            // Coin haut droit
                            Positioned(
                              top: 0, right: 0,
                              child: _ScanCorner(topRight: true),
                            ),
                            // Coin bas gauche
                            Positioned(
                              bottom: 0, left: 0,
                              child: _ScanCorner(bottomLeft: true),
                            ),
                            // Coin bas droit
                            Positioned(
                              bottom: 0, right: 0,
                              child: _ScanCorner(bottomRight: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Ligne de scan animée
                  _ScanLine(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Instructions
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text(
                'Caméra active — Pointez vers le QR code',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildProcessing() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppConstants.primaryRed.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: CircularProgressIndicator(
                  color: AppConstants.primaryRed, strokeWidth: 3),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Vérification en cours...',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Connexion sécurisée à votre compte',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green[400]!, Colors.green[600]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8))
              ],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 24),
          const Text('Connexion réussie !',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.green)),
          const SizedBox(height: 8),
          Text('Redirection vers l\'accueil...',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 42, color: Colors.red),
            ),
            const SizedBox(height: 20),
            const Text('Échec de la connexion',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
            const SizedBox(height: 10),
            Text(
              _errorMessage ?? 'QR code invalide ou expiré.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _resetScan,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Retour',
                  style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overlay du scanner ────────────────────────────────────────────────────────

class _ScannerOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _OverlayPainter(),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    const cutoutSize = 220.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final left = cx - cutoutSize / 2;
    final top = cy - cutoutSize / 2;
    final rect = Rect.fromLTWH(left, top, cutoutSize, cutoutSize);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Coins du viewfinder ───────────────────────────────────────────────────────

class _ScanCorner extends StatelessWidget {
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;

  const _ScanCorner({
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(32, 32),
      painter: _CornerPainter(
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool topLeft, topRight, bottomLeft, bottomRight;
  _CornerPainter(
      {required this.topLeft,
      required this.topRight,
      required this.bottomLeft,
      required this.bottomRight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.primaryRed
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 26.0;
    final w = size.width;
    final h = size.height;

    if (topLeft) {
      canvas.drawLine(Offset.zero, Offset(len, 0), paint);
      canvas.drawLine(Offset.zero, Offset(0, len), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset(w, 0), Offset(w - len, 0), paint);
      canvas.drawLine(Offset(w, 0), Offset(w, len), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(Offset(0, h), Offset(len, h), paint);
      canvas.drawLine(Offset(0, h), Offset(0, h - len), paint);
    }
    if (bottomRight) {
      canvas.drawLine(Offset(w, h), Offset(w - len, h), paint);
      canvas.drawLine(Offset(w, h), Offset(w, h - len), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Ligne de scan animée ──────────────────────────────────────────────────────

class _ScanLine extends StatefulWidget {
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: -95, end: 95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: Container(
          width: 210,
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppConstants.primaryRed.withOpacity(0.8),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}