// lib/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import '../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const EditProfileScreen({super.key, this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storage = const FlutterSecureStorage();

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  bool _isLoading = false;
  bool _isEmailEditable = true;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _userData = widget.userData;
    _nameController = TextEditingController(text: _userData?['name'] ?? '');
    _emailController = TextEditingController(text: _userData?['email'] ?? '');
    _phoneController = TextEditingController(text: _userData?['phone'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
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
          'Modifier le profil',
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
              padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildProfileHeader(isSmallScreen),
                    const SizedBox(height: 24),
                    _buildFormFields(isSmallScreen),
                    const SizedBox(height: 32),
                    _buildActionButtons(isSmallScreen),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProfileHeader(bool isSmallScreen) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 20 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppConstants.primaryRed,
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: isSmallScreen ? 40 : 50,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _userData?['profile_photo_url'] != null &&
                          _userData!['profile_photo_url'].toString().isNotEmpty
                      ? NetworkImage(_userData!['profile_photo_url'])
                      : null,
                  child: _userData?['profile_photo_url'] == null ||
                          _userData!['profile_photo_url'].toString().isEmpty
                      ? Text(
                          _userData?['name'] != null &&
                                  _userData!['name'].toString().isNotEmpty
                              ? _userData!['name'][0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 32 : 40,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryRed,
                          ),
                        )
                      : null,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context), // Retour à l'écran paramètres pour changer la photo
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.black54,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Pour changer votre photo, allez dans Paramètres',
            style: TextStyle(
              fontSize: isSmallScreen ? 10 : 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            'Informations personnelles',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          
          _buildTextField(
            controller: _nameController,
            label: 'Nom complet',
            icon: Icons.person_outline,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Le nom est requis';
              }
              return null;
            },
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 16),
          
          _buildTextField(
            controller: _emailController,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            enabled: _isEmailEditable,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'L\'email est requis';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Email invalide';
              }
              return null;
            },
            isSmallScreen: isSmallScreen,
          ),
          const SizedBox(height: 8),
          if (!_isEmailEditable)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Pour changer votre email, allez dans Confidentialité & sécurité',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          
          _buildTextField(
            controller: _phoneController,
            label: 'Téléphone',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            isSmallScreen: isSmallScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
    String? Function(String?)? validator,
    required bool isSmallScreen,
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
        Container(
          decoration: BoxDecoration(
            color: enabled ? Colors.grey[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextFormField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            validator: validator,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                size: isSmallScreen ? 18 : 20,
                color: AppConstants.primaryRed,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: isSmallScreen ? 12 : 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isSmallScreen) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              side: BorderSide(color: Colors.grey[300]!),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 14),
            ),
            child: const Text('Annuler'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 14),
            ),
            child: const Text('Enregistrer'),
          ),
        ),
      ],
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'auth_token');
      
      final response = await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/user/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'name': _nameController.text,
          'phone': _phoneController.text.isEmpty ? null : _phoneController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Mettre à jour les données utilisateur
        _userData!['name'] = _nameController.text;
        _userData!['phone'] = _phoneController.text;
        
        await _storage.write(
          key: 'user_data',
          value: jsonEncode(_userData),
        );
        
        if (mounted) {
          _showSuccess('Profil mis à jour avec succès');
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          _showError(data['message'] ?? 'Erreur lors de la mise à jour');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Erreur de connexion');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
}