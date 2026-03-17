// lib/screens/security_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import '../theme/app_theme.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Confidentialité & sécurité',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildChangePasswordSection(isSmallScreen),
                    const SizedBox(height: 16),
                    _buildPrivacySection(isSmallScreen),
                    const SizedBox(height: 16),
                    _buildSecuritySection(isSmallScreen),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildChangePasswordSection(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Changer le mot de passe',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          
          _buildPasswordField(
            controller: _currentPasswordController,
            label: 'Mot de passe actuel',
            obscureText: !_showCurrentPassword,
            onToggleVisibility: () => setState(() => _showCurrentPassword = !_showCurrentPassword),
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 16),
          
          _buildPasswordField(
            controller: _newPasswordController,
            label: 'Nouveau mot de passe',
            obscureText: !_showNewPassword,
            onToggleVisibility: () => setState(() => _showNewPassword = !_showNewPassword),
            isSmallScreen: isSmallScreen,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Le nouveau mot de passe est requis';
              }
              if (value.length < 8) {
                return 'Le mot de passe doit contenir au moins 8 caractères';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          _buildPasswordField(
            controller: _confirmPasswordController,
            label: 'Confirmer le nouveau mot de passe',
            obscureText: !_showConfirmPassword,
            onToggleVisibility: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
            isSmallScreen: isSmallScreen,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Veuillez confirmer le mot de passe';
              }
              if (value != _newPasswordController.text) {
                return 'Les mots de passe ne correspondent pas';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Mettre à jour le mot de passe'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required bool isSmallScreen,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isSmallScreen ? 12 : 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.lock_outline,
              size: isSmallScreen ? 18 : 20,
              color: AppConstants.primaryRed,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                size: isSmallScreen ? 16 : 18,
                color: Colors.grey[600],
              ),
              onPressed: onToggleVisibility,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppConstants.primaryRed),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isSmallScreen ? 12 : 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacySection(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confidentialité',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildPrivacyOption(
            icon: Icons.visibility_outlined,
            title: 'Visibilité du profil',
            subtitle: 'Qui peut voir votre profil',
            value: 'Public',
            onTap: () => _showComingSoon('Visibilité du profil'),
            isSmallScreen: isSmallScreen,
          ),
          const Divider(height: 1),
          
          _buildPrivacyOption(
            icon: Icons.circle_outlined,
            title: 'Statut en ligne',
            subtitle: 'Afficher quand vous êtes en ligne',
            value: 'Activé',
            onTap: () => _showComingSoon('Statut en ligne'),
            isSmallScreen: isSmallScreen,
          ),
          const Divider(height: 1),
          
          _buildPrivacyOption(
            icon: Icons.block_outlined,
            title: 'Utilisateurs bloqués',
            subtitle: 'Gérer les utilisateurs bloqués',
            value: '0',
            onTap: () => _showComingSoon('Utilisateurs bloqués'),
            isSmallScreen: isSmallScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required VoidCallback onTap,
    required bool isSmallScreen,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 12 : 16,
          vertical: isSmallScreen ? 12 : 14,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppConstants.primaryRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: isSmallScreen ? 18 : 20,
                color: AppConstants.primaryRed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: isSmallScreen ? 10 : 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: isSmallScreen ? 12 : 14,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecuritySection(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sécurité',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildSecurityOption(
            icon: Icons.devices_outlined,
            title: 'Appareils connectés',
            subtitle: 'Gérer les appareils connectés à votre compte',
            onTap: () => _showComingSoon('Appareils connectés'),
            isSmallScreen: isSmallScreen,
          ),
          const Divider(height: 1),
          
          _buildSecurityOption(
            icon: Icons.history_outlined,
            title: 'Historique des connexions',
            subtitle: 'Voir les dernières connexions',
            onTap: () => _showComingSoon('Historique des connexions'),
            isSmallScreen: isSmallScreen,
          ),
          const Divider(height: 1),
          
          _buildSecurityOption(
            icon: Icons.security_outlined,
            title: 'Authentification à deux facteurs',
            subtitle: 'Renforcer la sécurité de votre compte',
            onTap: () => _showComingSoon('2FA'),
            isSmallScreen: isSmallScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isSmallScreen,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 12 : 16,
          vertical: isSmallScreen ? 12 : 14,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppConstants.primaryRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: isSmallScreen ? 18 : 20,
                color: AppConstants.primaryRed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: isSmallScreen ? 12 : 14,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'auth_token');
      
      final response = await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/user/password'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'current_password': _currentPasswordController.text,
          'new_password': _newPasswordController.text,
          'new_password_confirmation': _confirmPasswordController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _clearPasswordFields();
        _showSuccess('Mot de passe mis à jour avec succès');
      } else {
        String errorMessage = 'Erreur lors du changement de mot de passe';
        if (data['errors'] != null && data['errors']['current_password'] != null) {
          errorMessage = data['errors']['current_password'][0];
        } else if (data['message'] != null) {
          errorMessage = data['message'];
        }
        _showError(errorMessage);
      }
    } catch (e) {
      _showError('Erreur de connexion');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _clearPasswordFields() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Bientôt disponible'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}