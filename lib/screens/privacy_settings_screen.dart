import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import '../theme/app_theme.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _storage = const FlutterSecureStorage();
  
  bool _isLoading = true;
  bool _isSaving = false;
  
  // Paramètres de confidentialité
  String _profileVisibility = 'public'; // public, private, friends_only
  bool _showOnlineStatus = true;
  bool _showLastSeen = true;
  bool _allowMessagesFromEveryone = true;
  bool _allowFriendRequests = true;
  bool _shareLocation = false;
  bool _saveChatHistory = true;
  bool _allowDataCollection = true;
  
  final List<Map<String, dynamic>> _visibilityOptions = [
    {'value': 'public', 'label': 'Public', 'icon': Icons.public, 'description': 'Tout le monde peut voir votre profil'},
    {'value': 'friends_only', 'label': 'Amis uniquement', 'icon': Icons.people, 'description': 'Seuls vos contacts peuvent voir votre profil'},
    {'value': 'private', 'label': 'Privé', 'icon': Icons.lock, 'description': 'Personne ne peut voir votre profil'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'auth_token');
      
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final settings = data['settings'] ?? {};
        final privacy = settings['privacy'] ?? {};
        
        setState(() {
          _profileVisibility = privacy['profile_visibility'] ?? 'public';
          _showOnlineStatus = privacy['show_online_status'] ?? true;
          _showLastSeen = privacy['show_last_seen'] ?? true;
          _allowMessagesFromEveryone = privacy['allow_messages_from_everyone'] ?? true;
          _allowFriendRequests = privacy['allow_friend_requests'] ?? true;
          _shareLocation = privacy['share_location'] ?? false;
          _saveChatHistory = privacy['save_chat_history'] ?? true;
          _allowDataCollection = privacy['allow_data_collection'] ?? true;
        });
      }
    } catch (e) {
      print('Erreur chargement paramètres confidentialité: $e');
      _showError('Erreur de chargement des paramètres');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePrivacySettings() async {
    setState(() => _isSaving = true);

    try {
      final token = await _storage.read(key: 'auth_token');
      
      // D'abord récupérer les paramètres actuels
      final getResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      Map<String, dynamic> currentSettings = {};
      if (getResponse.statusCode == 200) {
        final data = jsonDecode(getResponse.body);
        currentSettings = data['settings'] ?? {};
      }

      // Mettre à jour uniquement les paramètres de confidentialité
      currentSettings['privacy'] = {
        'profile_visibility': _profileVisibility,
        'show_online_status': _showOnlineStatus,
        'show_last_seen': _showLastSeen,
        'allow_messages_from_everyone': _allowMessagesFromEveryone,
        'allow_friend_requests': _allowFriendRequests,
        'share_location': _shareLocation,
        'save_chat_history': _saveChatHistory,
        'allow_data_collection': _allowDataCollection,
      };

      final response = await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/user/settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'settings': currentSettings}),
      );

      if (response.statusCode == 200) {
        _showSuccess('Paramètres de confidentialité mis à jour');
        Navigator.pop(context, true);
      } else {
        _showError('Erreur lors de la sauvegarde');
      }
    } catch (e) {
      print('Erreur sauvegarde paramètres confidentialité: $e');
      _showError('Erreur de connexion');
    } finally {
      setState(() => _isSaving = false);
    }
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
          'Confidentialité',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _savePrivacySettings,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Enregistrer',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              child: Column(
                children: [
                  _buildProfileVisibilitySection(isSmallScreen),
                  const SizedBox(height: 16),
                  _buildOnlineStatusSection(isSmallScreen),
                  const SizedBox(height: 16),
                  _buildInteractionsSection(isSmallScreen),
                  const SizedBox(height: 16),
                  _buildDataSection(isSmallScreen),
                  const SizedBox(height: 16),
                  _buildBlockedUsersSection(isSmallScreen),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileVisibilitySection(bool isSmallScreen) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.visibility,
                  color: AppConstants.primaryRed,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Visibilité du profil',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          ..._visibilityOptions.map((option) {
            final isSelected = _profileVisibility == option['value'];
            return RadioListTile<String>(
              title: Row(
                children: [
                  Icon(
                    option['icon'],
                    size: isSmallScreen ? 18 : 20,
                    color: isSelected ? AppConstants.primaryRed : Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option['label'],
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        Text(
                          option['description'],
                          style: TextStyle(
                            fontSize: isSmallScreen ? 11 : 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              value: option['value'],
              groupValue: _profileVisibility,
              onChanged: (value) {
                setState(() {
                  _profileVisibility = value.toString();
                });
              },
              activeColor: AppConstants.primaryRed,
              contentPadding: EdgeInsets.zero,
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildOnlineStatusSection(bool isSmallScreen) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.circle_outlined,
                  color: AppConstants.primaryRed,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Statut en ligne',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          SwitchListTile(
            secondary: Icon(
              Icons.circle,
              size: isSmallScreen ? 18 : 20,
              color: _showOnlineStatus ? Colors.green : Colors.grey,
            ),
            title: Text(
              'Afficher le statut en ligne',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Les autres utilisateurs verront quand vous êtes en ligne',
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 13,
                color: Colors.grey[600],
              ),
            ),
            value: _showOnlineStatus,
            onChanged: (value) => setState(() => _showOnlineStatus = value),
            activeColor: AppConstants.primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
          
          const Divider(height: 24),
          
          SwitchListTile(
            secondary: Icon(
              Icons.access_time,
              size: isSmallScreen ? 18 : 20,
              color: _showLastSeen ? AppConstants.primaryRed : Colors.grey,
            ),
            title: Text(
              'Afficher "vu(e) pour la dernière fois"',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Les autres utilisateurs verront quand vous étiez en ligne pour la dernière fois',
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 13,
                color: Colors.grey[600],
              ),
            ),
            value: _showLastSeen,
            onChanged: (value) => setState(() => _showLastSeen = value),
            activeColor: AppConstants.primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionsSection(bool isSmallScreen) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.chat_outlined,
                  color: AppConstants.primaryRed,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Interactions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          SwitchListTile(
            secondary: Icon(
              Icons.message,
              size: isSmallScreen ? 18 : 20,
              color: _allowMessagesFromEveryone ? AppConstants.primaryRed : Colors.grey,
            ),
            title: Text(
              'Messages de tous',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Permettre à tout le monde de vous envoyer des messages',
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 13,
                color: Colors.grey[600],
              ),
            ),
            value: _allowMessagesFromEveryone,
            onChanged: (value) => setState(() => _allowMessagesFromEveryone = value),
            activeColor: AppConstants.primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
          
          const Divider(height: 24),
          
          SwitchListTile(
            secondary: Icon(
              Icons.people,
              size: isSmallScreen ? 18 : 20,
              color: _allowFriendRequests ? AppConstants.primaryRed : Colors.grey,
            ),
            title: Text(
              'Demandes d\'amis',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Permettre aux autres de vous envoyer des demandes d\'amis',
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 13,
                color: Colors.grey[600],
              ),
            ),
            value: _allowFriendRequests,
            onChanged: (value) => setState(() => _allowFriendRequests = value),
            activeColor: AppConstants.primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(bool isSmallScreen) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.data_usage,
                  color: AppConstants.primaryRed,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Données',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          SwitchListTile(
            secondary: Icon(
              Icons.location_on,
              size: isSmallScreen ? 18 : 20,
              color: _shareLocation ? AppConstants.primaryRed : Colors.grey,
            ),
            title: Text(
              'Partager ma localisation',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Permettre aux entreprises de voir votre localisation pour des services près de chez vous',
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 13,
                color: Colors.grey[600],
              ),
            ),
            value: _shareLocation,
            onChanged: (value) => setState(() => _shareLocation = value),
            activeColor: AppConstants.primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
          
          const Divider(height: 24),
          
          SwitchListTile(
            secondary: Icon(
              Icons.history,
              size: isSmallScreen ? 18 : 20,
              color: _saveChatHistory ? AppConstants.primaryRed : Colors.grey,
            ),
            title: Text(
              'Sauvegarder l\'historique des conversations',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Conserver l\'historique de vos conversations',
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 13,
                color: Colors.grey[600],
              ),
            ),
            value: _saveChatHistory,
            onChanged: (value) => setState(() => _saveChatHistory = value),
            activeColor: AppConstants.primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
          
          const Divider(height: 24),
          
          SwitchListTile(
            secondary: Icon(
              Icons.analytics,
              size: isSmallScreen ? 18 : 20,
              color: _allowDataCollection ? AppConstants.primaryRed : Colors.grey,
            ),
            title: Text(
              'Collecte de données anonymes',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Aider à améliorer l\'application en envoyant des données d\'utilisation anonymes',
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 13,
                color: Colors.grey[600],
              ),
            ),
            value: _allowDataCollection,
            onChanged: (value) => setState(() => _allowDataCollection = value),
            activeColor: AppConstants.primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedUsersSection(bool isSmallScreen) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.block,
                  color: AppConstants.primaryRed,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Utilisateurs bloqués',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          InkWell(
            onTap: () => _showComingSoon('Gestion des utilisateurs bloqués'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_off,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gérer les blocages',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '0 utilisateur bloqué',
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
          ),
        ],
      ),
    );
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