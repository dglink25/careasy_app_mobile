import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/constants.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';

class GoogleAuthScreen extends StatefulWidget {
  const GoogleAuthScreen({super.key});

  @override
  State<GoogleAuthScreen> createState() => _GoogleAuthScreenState();
}

class _GoogleAuthScreenState extends State<GoogleAuthScreen> {
  final _storage = const FlutterSecureStorage();
  bool _isLoading = true;
  String? _errorMessage;

  // Configuration Google Sign In
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    clientId: '467002761555-ngtlk28b8ltqo50bdgivnkeqvmef47pf.apps.googleusercontent.com',
    serverClientId: '467002761555-iqqft5l3n5d2b9kv5hdaka4kivvkkhp3.apps.googleusercontent.com',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signInWithGoogle();
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Tentative de déconnexion pour forcer le choix
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        // Ignorer l'erreur si pas de session
      }
      
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

      if (googleAuth.idToken == null) {
        throw Exception('ID Token manquant');
      }

      // Envoyer le token au backend
      await _sendTokenToBackend(
        googleAuth.idToken!,
        googleUser.email,
        googleUser.displayName ?? googleUser.email.split('@').first,
      );

    } catch (error) {
      print('❌ Erreur Google Sign-In: $error');
      
      String userMessage = _getUserFriendlyErrorMessage(error);
      
      if (mounted) {
        setState(() {
          _errorMessage = userMessage;
          _isLoading = false;
        });
      }
    }
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('network_error') || errorString.contains('socket')) {
      return 'Erreur réseau. Vérifiez votre connexion internet.';
    } else if (errorString.contains('sign_in_canceled') || errorString.contains('canceled')) {
      return 'Connexion annulée.';
    } else if (errorString.contains('sign_in_required') || errorString.contains('no account')) {
      return 'Aucun compte Google trouvé sur cet appareil.';
    } else if (errorString.contains('developer_error') || errorString.contains('10')) {
      return 'Erreur de configuration. Veuillez contacter le support.';
    } else if (errorString.contains('timeout')) {
      return 'Délai d\'attente dépassé. Vérifiez votre connexion.';
    } else {
      return 'Erreur inattendue. Veuillez réessayer.';
    }
  }

  Future<void> _sendTokenToBackend(String idToken, String email, String name) async {
    try {
      print('Envoi du token au backend...');
      
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
          'provider': 'google',
        }),
      ).timeout(const Duration(seconds: 15));

      print('Statut: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        if (responseData['success'] == true || responseData['token'] != null) {
          final token = responseData['token'] ?? responseData['access_token'];
          final userData = responseData['user'] ?? responseData['data'];
          
          if (token != null) {
            // Stockage du token
            await _storage.write(key: 'auth_token', value: token);
            
            // Stockage des données utilisateur
            if (userData != null) {
              await _storage.write(
                key: 'user_data', 
                value: jsonEncode(userData)
              );
            }
            
            // Mettre à jour le provider
            if (mounted) {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              await authProvider.login(token, userData ?? {});
              
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
            throw Exception('Token non reçu');
          }
        } else {
          throw Exception(responseData['message'] ?? 'Erreur serveur');
        }
      } else {
        String errorMsg = 'Erreur serveur (${response.statusCode})';
        try {
          final errorData = jsonDecode(response.body);
          errorMsg = errorData['message'] ?? errorMsg;
        } catch (_) {}
        throw Exception(errorMsg);
      }
    } catch (e) {
      print('Erreur envoi token: $e');
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
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
      body: SafeArea(
        child: Center(
          child: _errorMessage != null
              ? _buildErrorView()
              : _buildLoadingView(),
        ),
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
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          'Veuillez patienter',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
            style: const TextStyle(fontSize: 14, color: Colors.grey),
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