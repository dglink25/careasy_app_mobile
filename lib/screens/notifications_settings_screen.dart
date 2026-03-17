// lib/screens/notifications_settings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VERSION COMPLÈTE — Configuration notifications + sons personnalisables
// ═══════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import '../services/notification_service.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );

  bool _isLoading     = true;
  bool _isSavingSound = false;

  // Canaux
  bool _emailNotifications = true;
  bool _pushNotifications  = true;
  bool _smsNotifications   = false;

  // Types
  bool _messageNotifications     = true;
  bool _appointmentNotifications = true;
  bool _promoNotifications       = false;

  // Son de notification
  bool   _useCustomSound  = false;
  String _selectedSound   = 'default';
  String _selectedSoundLabel = 'Système (défaut)';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSoundPrefs();
  }

  Future<void> _loadSoundPrefs() async {
    final useCustom  = await NotificationSoundPrefs.getUseCustomSound();
    final soundName  = await NotificationSoundPrefs.getCustomSoundName();
    final soundLabel = await NotificationSoundPrefs.getCustomSoundLabel();
    if (mounted) {
      setState(() {
        _useCustomSound     = useCustom;
        _selectedSound      = soundName;
        _selectedSoundLabel = soundLabel;
      });
    }
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
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['notifications'] != null) {
          setState(() {
            _emailNotifications = data['notifications']['email'] ?? true;
            _pushNotifications  = data['notifications']['push'] ?? true;
            _smsNotifications   = data['notifications']['sms'] ?? false;
          });
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement paramètres notif: $e');
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
            'push':  _pushNotifications,
            'sms':   _smsNotifications,
          },
        }),
      ).timeout(const Duration(seconds: 10));

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

  Future<void> _saveSoundPreference(String soundName, String soundLabel, bool useCustom) async {
    setState(() => _isSavingSound = true);
    try {
      await NotificationSoundPrefs.setSoundPreference(
        useCustom:   useCustom,
        soundName:   soundName,
        soundLabel:  soundLabel,
      );
      // Recréer le canal Android avec le nouveau son
      await NotificationService().updateNotificationChannel();
      
      setState(() {
        _useCustomSound     = useCustom;
        _selectedSound      = soundName;
        _selectedSoundLabel = soundLabel;
      });
      
      // Envoyer une notification de test
      await NotificationService().showNotification(
        id:    999,
        title: 'Son de notification',
        body:  'Ceci est un aperçu du son sélectionné : $soundLabel',
      );
      
      _showSuccess('Son mis à jour : $soundLabel');
    } catch (e) {
      _showError('Erreur lors du changement de son');
    } finally {
      setState(() => _isSavingSound = false);
    }
  }

  void _showSoundPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.music_note, color: AppConstants.primaryRed, size: 22),
                const SizedBox(width: 10),
                const Text('Son de notification',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              Text('Choisissez le son joué à la réception d\'un message.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 16),
              ...NotificationSoundPrefs.availableSounds.map((sound) {
                final isSelected = _selectedSound == sound['name'];
                final isDefault  = sound['name'] == 'default';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppConstants.primaryRed.withOpacity(0.1)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isDefault ? Icons.volume_up : Icons.music_note_outlined,
                      size: 20,
                      color: isSelected ? AppConstants.primaryRed : Colors.grey[600],
                    ),
                  ),
                  title: Text(
                    sound['label']!,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? AppConstants.primaryRed : Colors.black87,
                    ),
                  ),
                  subtitle: isDefault
                      ? Text('Son par défaut du système',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                      : null,
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: AppConstants.primaryRed, size: 22)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _saveSoundPreference(
                      sound['name']!,
                      sound['label']!,
                      !isDefault,
                    );
                  },
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
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
            child: const Text('Enregistrer',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              child: Column(
                children: [
                  // ── Son de notification ──────────────────────────
                  _buildSoundSection(isSmallScreen),
                  const SizedBox(height: 16),

                  // ── Canaux ────────────────────────────────────────
                  _buildSection(
                    title:    'Canaux de notification',
                    iconData: Icons.notifications_outlined,
                    children: [
                      _buildSwitchTile(
                        icon: Icons.email_outlined,
                        title: 'Email',
                        subtitle: 'Recevoir les notifications par email',
                        value: _emailNotifications,
                        onChanged: (v) => setState(() => _emailNotifications = v),
                        isSmallScreen: isSmallScreen,
                      ),
                      _buildSwitchTile(
                        icon: Icons.notifications_outlined,
                        title: 'Push (application)',
                        subtitle: 'Notifications sur votre appareil',
                        value: _pushNotifications,
                        onChanged: (v) => setState(() => _pushNotifications = v),
                        isSmallScreen: isSmallScreen,
                      ),
                      _buildSwitchTile(
                        icon: Icons.sms_outlined,
                        title: 'SMS',
                        subtitle: 'Recevoir les notifications par SMS',
                        value: _smsNotifications,
                        onChanged: (v) => setState(() => _smsNotifications = v),
                        isSmallScreen: isSmallScreen,
                      ),
                    ],
                    isSmallScreen: isSmallScreen,
                  ),
                  const SizedBox(height: 16),

                  // ── Types ─────────────────────────────────────────
                  _buildSection(
                    title:    'Types de notifications',
                    iconData: Icons.tune,
                    children: [
                      _buildSwitchTile(
                        icon: Icons.message_outlined,
                        title: 'Messages',
                        subtitle: 'Nouveaux messages reçus',
                        value: _messageNotifications,
                        onChanged: (v) => setState(() => _messageNotifications = v),
                        isSmallScreen: isSmallScreen,
                      ),
                      _buildSwitchTile(
                        icon: Icons.calendar_today_outlined,
                        title: 'Rendez-vous',
                        subtitle: 'Rappels et confirmations',
                        value: _appointmentNotifications,
                        onChanged: (v) => setState(() => _appointmentNotifications = v),
                        isSmallScreen: isSmallScreen,
                      ),
                      _buildSwitchTile(
                        icon: Icons.local_offer_outlined,
                        title: 'Promotions',
                        subtitle: 'Offres spéciales et réductions',
                        value: _promoNotifications,
                        onChanged: (v) => setState(() => _promoNotifications = v),
                        isSmallScreen: isSmallScreen,
                      ),
                    ],
                    isSmallScreen: isSmallScreen,
                  ),
                ],
              ),
            ),
    );
  }

  // ── Section Son ──────────────────────────────────────────────────
  Widget _buildSoundSection(bool isSmallScreen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section
          Padding(
            padding: EdgeInsets.fromLTRB(
                isSmallScreen ? 16 : 20, isSmallScreen ? 16 : 20,
                isSmallScreen ? 16 : 20, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppConstants.primaryRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.music_note, color: AppConstants.primaryRed, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Son de notification',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
          ),

          // Sélecteur de son
          InkWell(
            onTap: _showSoundPicker,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 16 : 20, vertical: 12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _selectedSound == 'default'
                        ? Icons.volume_up_outlined
                        : Icons.music_note_outlined,
                    size: isSmallScreen ? 20 : 22,
                    color: AppConstants.primaryRed,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'Son actuel',
                      style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 13,
                          color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedSoundLabel,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 15,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.primaryRed,
                      ),
                    ),
                  ]),
                ),
                if (_isSavingSound)
                  const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppConstants.primaryRed),
                  )
                else
                  Icon(Icons.arrow_forward_ios,
                      size: isSmallScreen ? 14 : 16, color: Colors.grey[400]),
              ]),
            ),
          ),

          // Info
          Padding(
            padding: EdgeInsets.fromLTRB(
                isSmallScreen ? 16 : 20, 0,
                isSmallScreen ? 16 : 20, isSmallScreen ? 12 : 16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, size: 15, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Un aperçu sera joué lors du changement. '
                  'Sur Android, le son est lié au canal — si le son ne change pas, '
                  'désinstallez et réinstallez l\'app ou modifiez le canal dans les réglages système.',
                  style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                )),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData iconData,
    required List<Widget> children,
    required bool isSmallScreen,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(iconData, color: AppConstants.primaryRed, size: 20),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(height: 1),
        ...children,
      ]),
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
        child: Icon(icon, size: isSmallScreen ? 18 : 20, color: AppConstants.primaryRed),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: isSmallScreen ? 11 : 13, color: Colors.grey[600])),
      value: value,
      onChanged: onChanged,
      activeColor: AppConstants.primaryRed,
      contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 16),
    );
  }

  void _showSuccess(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(message),
      ]),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}