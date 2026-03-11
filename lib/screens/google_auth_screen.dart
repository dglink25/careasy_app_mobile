import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class GoogleAuthScreen extends StatefulWidget {
  const GoogleAuthScreen({super.key});

  @override
  State<GoogleAuthScreen> createState() => _GoogleAuthScreenState();
}

class _GoogleAuthScreenState extends State<GoogleAuthScreen> {
  final _storage = const FlutterSecureStorage();
  bool _isLoading = true;
  String? _errorMessage;
  bool _isRetrying = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    // Utilisez le Client ID Web (pas celui Android)
    clientId: '467002761555-iqqft5l3n5d2b9kv5hdaka4kivvkkhp3.apps.googleusercontent.com',
    serverClientId: '467002761555-iqqft5l3n5d2b9kv5hdaka4kivvkkhp3.apps.googleusercontent.com',
  );

  @override
  void initState() {
    super.initState();
    _signInWithGoogle();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Forcer la déconnexion pour permettre le choix du compte
      await _googleSignIn.signOut();
      
      // Tentative de connexion
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // L'utilisateur a annulé
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connexion annulée'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context, false);
        }
        return;
      }

      // Authentification réussie
      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      // Envoi au backend
      await _sendTokenToBackend(
        googleAuth.idToken!,
        googleUser.email,
        googleUser.displayName,
        googleUser.photoUrl,
      );

    } catch (error) {
      print('Erreur Google Sign-In: $error');
      
      String userMessage = _getUserFriendlyErrorMessage(error);
      
      setState(() {
        _errorMessage = userMessage;
        _isLoading = false;
      });
    }
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString();
    
    if (errorString.contains('ApiException: 10')) {
      return 'Erreur de configuration (CODE 10). Veuillez contacter le support.';
    } else if (errorString.contains('network_error')) {
      return 'Erreur réseau. Vérifiez votre connexion internet.';
    } else if (errorString.contains('sign_in_canceled')) {
      return 'Connexion annulée.';
    } else if (errorString.contains('sign_in_required')) {
      return 'Aucun compte Google trouvé sur cet appareil.';
    } else {
      return 'Erreur inattendue: ${error.toString().split(',').first}';
    }
  }

  Future<void> _sendTokenToBackend(
    String idToken, 
    String email, 
    String? name,
    String? photoUrl,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/auth/google/callback'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'id_token': idToken,
          'email': email,
          'name': name,
          'photo_url': photoUrl,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseData['token'] != null) {
          await _storage.write(key: 'auth_token', value: responseData['token']);
        }
        
        if (responseData['user'] != null) {
          await _storage.write(
            key: 'user_data', 
            value: jsonEncode(responseData['user'])
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connexion avec Google réussie !'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(responseData['message'] ?? 'Erreur serveur');
      }
    } catch (e) {
      print('Erreur envoi token: $e');
      throw Exception('Impossible de communiquer avec le serveur');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _retry() {
    setState(() {
      _isRetrying = true;
      _errorMessage = null;
    });
    _signInWithGoogle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connexion avec Google'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: _errorMessage != null
            ? _buildErrorView()
            : _buildLoadingView(),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppConstants.primaryRed),
        ),
        const SizedBox(height: 24),
        Text(
          _isRetrying ? 'Nouvelle tentative...' : 'Connexion en cours...',
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF2D3436),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
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
            child: const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Erreur de connexion',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3436),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF718096),
            ),
          ),
          const SizedBox(height: 24),
          if (_errorMessage!.contains('CODE 10'))
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Text(
                    'Solution rapide :',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ajoutez les empreintes SHA1 et SHA256 de votre application dans Firebase Console',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Réessayer'),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: AppConstants.primaryRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}