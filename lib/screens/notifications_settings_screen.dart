// lib/screens/notifications_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import '../theme/app_theme.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );
  
  bool _isLoading = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _smsNotifications = false;
  bool _messageNotifications = true;
  bool _appointmentNotifications = true;
  bool _promoNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/notification-settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['notifications'] != null) {
          setState(() {
            _emailNotifications = data['notifications']['email'] ?? true;
            _pushNotifications = data['notifications']['push'] ?? true;
            _smsNotifications = data['notifications']['sms'] ?? false;
          });
        }
      }
    } catch (e) {
      print('Erreur chargement paramètres: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'auth_token');
      
      final response = await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/user/notification-settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'notifications': {
            'email': _emailNotifications,
            'push': _pushNotifications,
            'sms': _smsNotifications,
          },
        }),
      );

      if (response.statusCode == 200) {
        _showSuccess('Paramètres mis à jour');
      } else {
        _showError('Erreur lors de la sauvegarde');
      }
    } catch (e) {
      _showError('Erreur de connexion');
    } finally {
      setState(() => _isLoading = false);
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
          'Notifications',
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
          TextButton(
            onPressed: _saveSettings,
            child: const Text(
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
                  _buildSection(
                    'Canaux de notification',
                    [
                      _buildSwitchTile(
                        icon: Icons.email_outlined,
                        title: 'Notifications par email',
                        subtitle: 'Recevoir les notifications par email',
                        value: _emailNotifications,
                        onChanged: (value) => setState(() => _emailNotifications = value),
                        isSmallScreen: isSmallScreen,
                      ),
                      _buildSwitchTile(
                        icon: Icons.notifications_outlined,
                        title: 'Notifications push',
                        subtitle: 'Recevoir les notifications sur votre appareil',
                        value: _pushNotifications,
                        onChanged: (value) => setState(() => _pushNotifications = value),
                        isSmallScreen: isSmallScreen,
                      ),
                      _buildSwitchTile(
                        icon: Icons.sms_outlined,
                        title: 'Notifications par SMS',
                        subtitle: 'Recevoir les notifications par SMS',
                        value: _smsNotifications,
                        onChanged: (value) => setState(() => _smsNotifications = value),
                        isSmallScreen: isSmallScreen,
                      ),
                    ],
                    isSmallScreen,
                  ),
                  const SizedBox(height: 16),
                  
                  _buildSection(
                    'Types de notifications',
                    [
                      _buildSwitchTile(
                        icon: Icons.message_outlined,
                        title: 'Messages',
                        subtitle: 'Nouveaux messages reçus',
                        value: _messageNotifications,
                        onChanged: (value) => setState(() => _messageNotifications = value),
                        isSmallScreen: isSmallScreen,
                      ),
                      _buildSwitchTile(
                        icon: Icons.calendar_today_outlined,
                        title: 'Rendez-vous',
                        subtitle: 'Rappels et confirmations de rendez-vous',
                        value: _appointmentNotifications,
                        onChanged: (value) => setState(() => _appointmentNotifications = value),
                        isSmallScreen: isSmallScreen,
                      ),
                      _buildSwitchTile(
                        icon: Icons.local_offer_outlined,
                        title: 'Promotions',
                        subtitle: 'Offres spéciales et réductions',
                        value: _promoNotifications,
                        onChanged: (value) => setState(() => _promoNotifications = value),
                        isSmallScreen: isSmallScreen,
                      ),
                    ],
                    isSmallScreen,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children, bool isSmallScreen) {
    return Container(
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
          Padding(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
            child: Text(
              title,
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required bool isSmallScreen,
  }) {
    return SwitchListTile(
      secondary: Container(
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
      title: Text(
        title,
        style: TextStyle(
          fontSize: isSmallScreen ? 14 : 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: isSmallScreen ? 11 : 13,
          color: Colors.grey[600],
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: AppConstants.primaryRed,
      contentPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 12 : 16,
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
}