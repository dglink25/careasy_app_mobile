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

  // Configuration correcte avec vos identifiants
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    // Client ID ANDROID
    clientId: '467002761555-ngtlk28b8ltqo50bdgivnkeqvmef47pf.apps.googleusercontent.com',
    // Client ID WEB (pour le backend)
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
      // Déconnexion préalable pour forcer le choix du compte
      await _googleSignIn.signOut();
      
      // Tentative de connexion
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
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

      print('✅ Connexion Google réussie pour: ${googleUser.email}');
      
      // Récupérer l'authentification
      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      // ✅ Envoyer le token au backend (version mobile)
      await _sendTokenToBackend(
        googleAuth.idToken!,
        googleUser.email,
        googleUser.displayName,
      );

    } catch (error) {
      print('❌ Erreur Google Sign-In: $error');
      
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
      return 'Erreur de configuration (CODE 10). Vos empreintes SHA sont bien configurées ?';
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
  ) async {
    try {
      print('Envoi du token au backend mobile...');
      
      // URL vers votre nouvelle route mobile
      final url = '${AppConstants.apiBaseUrl}/google/callback/mobile';
      print('📡 URL: $url');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'id_token': idToken,
          'email': email,
          'name': name,
        }),
      ).timeout(const Duration(seconds: 15));

      print('Statut: ${response.statusCode}');
      print('Body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        // Stockage du token
        if (responseData['token'] != null) {
          await _storage.write(key: 'auth_token', value: responseData['token']);
          print('Token stocké');
        }
        
        // Stockage des données utilisateur
        if (responseData['user'] != null) {
          await _storage.write(
            key: 'user_data', 
            value: jsonEncode(responseData['user'])
          );
          print('Données utilisateur stockées: ${responseData['user']['name']}');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connexion avec Google réussie !'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, true); // Succès
        }
      } else {
        throw Exception(responseData['message'] ?? 'Erreur serveur');
      }
    } 
    catch (e) {
      print('Erreur: $e');
      throw Exception('Impossible de communiquer avec le serveur');
    } 
    finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _retry() {
    setState(() {
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
        const Text(
          'Connexion en cours...',
          style: TextStyle(fontSize: 16, color: Color(0xFF2D3436)),
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
            child: const Icon(Icons.error_outline, color: Colors.red, size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            'Erreur de connexion',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF718096)),
          ),
          const SizedBox(height: 24),
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