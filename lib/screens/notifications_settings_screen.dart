// lib/screens/notifications_settings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// CORRECTIONS SON:
// 1. playSoundPreview() joue le son AVANT d'envoyer la notification test
// 2. updateNotificationChannel() — correctement appelée et attendue
// 3. Canal Android par son — sélection effective dès la prochaine notif
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
  bool _isPlayingSound = false;

  // Canaux
  bool _emailNotifications = true;
  bool _pushNotifications  = true;
  bool _smsNotifications   = false;

  // Types
  bool _messageNotifications     = true;
  bool _appointmentNotifications = true;
  bool _promoNotifications       = false;

  // Son de notification
  bool   _useCustomSound     = false;
  String _selectedSound      = 'default';
  String _selectedSoundLabel = 'Système (défaut)';

  // Son en cours de prévisualisation dans le picker
  String _previewingSound = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSoundPrefs();
  }

  // ── Chargement son depuis SharedPreferences ──────────────────────────────
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

  // ── Chargement params notif depuis le serveur ────────────────────────────
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
            _pushNotifications  = data['notifications']['push']  ?? true;
            _smsNotifications   = data['notifications']['sms']   ?? false;
          });
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement paramètres notif: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Sauvegarde params notif sur le serveur ───────────────────────────────
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

  // ── Sélection et sauvegarde du son ──────────────────────────────────────
  Future<void> _saveSoundPreference(
      String soundName, String soundLabel, bool useCustom) async {

    setState(() { _isSavingSound = true; });
    try {
      // 1. Sauvegarder la préférence localement (SharedPreferences)
      await NotificationSoundPrefs.setSoundPreference(
        useCustom:  useCustom,
        soundName:  soundName,
        soundLabel: soundLabel,
      );

      // 2. Informer le service (enregistre le canal actif)
      await NotificationService().updateNotificationChannel();

      // 3. Mettre à jour l'UI immédiatement
      if (mounted) {
        setState(() {
          _useCustomSound     = useCustom;
          _selectedSound      = soundName;
          _selectedSoundLabel = soundLabel;
          _isSavingSound      = false;
        });
      }

      // 4. Jouer un aperçu (just_audio depuis assets)
      if (soundName != 'default') {
        setState(() => _isPlayingSound = true);
        await NotificationService().playSoundPreview(soundName);
        if (mounted) setState(() => _isPlayingSound = false);
      }

      // 5. Envoyer une notification de test pour valider l'intégration complète
      await Future.delayed(const Duration(milliseconds: 500));
      await NotificationService().showNotification(
        id:    999,
        title: 'Son de notification',
        body:  'Son sélectionné : $soundLabel',
      );

      _showSuccess('Son mis à jour : $soundLabel');
    } catch (e) {
      debugPrint('[SoundSave] Erreur: $e');
      _showError('Erreur lors du changement de son');
      setState(() { _isSavingSound = false; _isPlayingSound = false; });
    }
  }

  // ── Picker de sons ───────────────────────────────────────────────────────
  void _showSoundPicker() {
    // Initialiser le son en preview avec le son actuel
    _previewingSound = _selectedSound;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poignée
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),

              // Titre
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppConstants.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.music_note, color: AppConstants.primaryRed, size: 20),
                ),
                const SizedBox(width: 10),
                const Text('Son de notification',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              Text('Appuyez sur un son pour l\'écouter, puis confirmez.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 16),

              // Liste des sons
              ...NotificationSoundPrefs.availableSounds.map((sound) {
                final sName     = sound['name']!;
                final sLabel    = sound['label']!;
                final isDefault = sName == 'default';
                final isSelected = _selectedSound == sName;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppConstants.primaryRed.withOpacity(0.06)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? AppConstants.primaryRed.withOpacity(0.4)
                          : Colors.grey[200]!,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    leading: GestureDetector(
                      // Appuyer sur l'icône = jouer l'aperçu
                      onTap: () async {
                        if (isDefault) return;
                        setModalState(() => _previewingSound = sName);
                        await NotificationService().playSoundPreview(sName);
                        setModalState(() => _previewingSound = '');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppConstants.primaryRed.withOpacity(0.1)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _previewingSound == sName
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppConstants.primaryRed))
                            : Icon(
                                isDefault
                                    ? Icons.volume_up_outlined
                                    : Icons.play_circle_outline,
                                size: 20,
                                color: isSelected
                                    ? AppConstants.primaryRed
                                    : Colors.grey[600],
                              ),
                      ),
                    ),
                    title: Text(
                      sLabel,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppConstants.primaryRed : Colors.black87,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: isDefault
                        ? Text('Son par défaut du système',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                        : Text('Appuyez ▶ pour écouter',
                            style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: AppConstants.primaryRed, size: 22)
                        : Icon(Icons.radio_button_unchecked,
                            color: Colors.grey[400], size: 22),
                    onTap: () {
                      // Sélectionner = fermer le picker + sauvegarder
                      Navigator.pop(ctx);
                      _saveSoundPreference(sName, sLabel, !isDefault);
                    },
                  ),
                );
              }).toList(),

              const SizedBox(height: 8),
              // Bouton Annuler
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Annuler'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
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
        title: Text('Notifications',
            style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20, fontWeight: FontWeight.bold)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text('Enregistrer',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed))
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              child: Column(children: [
                // ── Son de notification ──────────────────────────────
                _buildSoundSection(isSmallScreen),
                const SizedBox(height: 16),

                // ── Canaux ───────────────────────────────────────────
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

                // ── Types ─────────────────────────────────────────────
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
                const SizedBox(height: 20),
              ]),
            ),
    );
  }

  // ── Section son ─────────────────────────────────────────────────────────
  Widget _buildSoundSection(bool isSmallScreen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.grey.withOpacity(0.1),
          blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: EdgeInsets.fromLTRB(
              isSmallScreen ? 16 : 20,
              isSmallScreen ? 16 : 20,
              isSmallScreen ? 16 : 20, 12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.music_note,
                  color: AppConstants.primaryRed, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Son de notification',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),

        // Sélecteur actuel
        InkWell(
          onTap: _showSoundPicker,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
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
                child: (_isSavingSound || _isPlayingSound)
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppConstants.primaryRed))
                    : Icon(
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
                  Text('Son actuel',
                      style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 13,
                          color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text(
                    _isPlayingSound
                        ? 'Lecture en cours…'
                        : _isSavingSound
                            ? 'Mise à jour…'
                            : _selectedSoundLabel,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 15,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primaryRed,
                    ),
                  ),
                ]),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: isSmallScreen ? 14 : 16,
                  color: Colors.grey[400]),
            ]),
          ),
        ),

        // Note info
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
              Expanded(
                child: Text(
                  'Sur Android, chaque son utilise un canal distinct. '
                  'Si un son ne change pas après sélection, '
                  'vérifiez les réglages de notification de l\'app dans les paramètres système.',
                  style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Widgets utilitaires ───────────────────────────────────────────────────
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
          color: Colors.grey.withOpacity(0.1),
          blurRadius: 10, offset: const Offset(0, 2))],
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
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
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
        child: Icon(icon,
            size: isSmallScreen ? 18 : 20, color: AppConstants.primaryRed),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: isSmallScreen ? 11 : 13, color: Colors.grey[600])),
      value: value,
      onChanged: onChanged,
      activeColor: AppConstants.primaryRed,
      contentPadding:
          EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 16),
    );
  }

  void _showSuccess(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(message),
        ]),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));

  void _showError(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
}