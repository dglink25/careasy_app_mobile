// lib/screens/notifications_settings_screen.dart
// ═══════════════════════════════════════════════════════════════════════════
// CORRECTIONS :
//   ✅ Après changement de son → canal Android recréé IMMÉDIATEMENT
//   ✅ Test du son via audioplayers (pas de notification)
//   ✅ Enregistrement persistant des préférences
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  static const _aOpts = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOpts = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _storage = const FlutterSecureStorage(aOptions: _aOpts, iOptions: _iOpts);

  bool   _isLoading     = true;
  bool   _isSavingSound = false;
  String _playingSound  = '';

  bool _emailNotif  = true;
  bool _pushNotif   = true;
  bool _smsNotif    = false;
  bool _messageNotif    = true;
  bool _appointmentNotif = true;
  bool _promoNotif      = false;

  String _selectedSound  = 'default';
  String _selectedLabel  = 'Système (défaut)';
  String _selectedEmoji  = '🔕';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final soundName  = await NotificationSoundPrefs.getCustomSoundName();
    final soundLabel = await NotificationSoundPrefs.getCustomSoundLabel();
    final soundInfo  = NotificationSoundPrefs.availableSounds
        .firstWhere((s) => s['name'] == soundName,
            orElse: () => NotificationSoundPrefs.availableSounds.first);

    try {
      final token = await _storage.read(key: 'auth_token');
      final resp = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/user/notification-settings'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json'
            },
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['notifications'] != null && mounted) {
          setState(() {
            _emailNotif = data['notifications']['email'] ?? true;
            _pushNotif  = data['notifications']['push']  ?? true;
            _smsNotif   = data['notifications']['sms']   ?? false;
          });
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _selectedSound = soundName;
        _selectedLabel = soundLabel;
        _selectedEmoji = soundInfo['emoji'] ?? '🔕';
        _isLoading     = false;
      });
    }
  }

  Future<void> _saveServerSettings() async {
    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      await http
          .put(
            Uri.parse('${AppConstants.apiBaseUrl}/user/notification-settings'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type':  'application/json',
              'Accept':        'application/json',
            },
            body: jsonEncode({
              'notifications': {
                'email': _emailNotif,
                'push':  _pushNotif,
                'sms':   _smsNotif,
              },
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (mounted) _snack('Paramètres enregistrés', Colors.green);
    } catch (_) {
      if (mounted) _snack('Erreur de connexion', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Enregistre le son ET recrée le canal Android — appelé quand l'utilisateur
  /// choisit un son dans le picker.
  Future<void> _applySound(String name, String label, String emoji) async {
    if (!mounted) return;
    setState(() => _isSavingSound = true);

    // 1. Sauvegarder les préférences
    await NotificationSoundPrefs.setSoundPreference(
      useCustom:  name != 'default',
      soundName:  name,
      soundLabel: label,
    );

    // 2. Recréer le canal Android avec le nouveau son
    await NotificationService().updateNotificationChannel();

    // 3. Mettre à jour l'UI
    if (mounted) {
      setState(() {
        _selectedSound = name;
        _selectedLabel = label;
        _selectedEmoji = emoji;
        _isSavingSound = false;
      });
    }

    // 4. Jouer un aperçu
    await Future.delayed(const Duration(milliseconds: 200));
    await NotificationService().playSoundPreview(name);

    if (mounted) _snack('Son mis à jour : $label', Colors.green);
  }

  Future<void> _previewSound(String name, StateSetter setM) async {
    if (_playingSound == name) return;
    setM(() => _playingSound = name);
    setState(() => _playingSound = name);
    await NotificationService().playSoundPreview(name);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setM(() => _playingSound = '');
      setState(() => _playingSound = '');
    }
  }

  void _showSoundPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setM) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, sc) => Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(children: [
                    const Icon(Icons.music_note,
                        color: AppConstants.primaryRed, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Son de notification',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            Text('Appuyer ▶ pour écouter',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500])),
                          ]),
                    ),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: sc,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount:
                        NotificationSoundPrefs.availableSounds.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final s     = NotificationSoundPrefs.availableSounds[i];
                      final name  = s['name']!;
                      final label = s['label']!;
                      final emoji = s['emoji'] ?? '🔔';
                      final isSel = _selectedSound == name;
                      final isPla = _playingSound  == name;

                      return Material(
                        color: isSel
                            ? AppConstants.primaryRed.withOpacity(0.07)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _previewSound(name, setM),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                    color: isSel
                                        ? AppConstants.primaryRed
                                            .withOpacity(0.15)
                                        : Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: isSel
                                            ? AppConstants.primaryRed
                                                .withOpacity(0.4)
                                            : Colors.grey[200]!)),
                                child: isPla
                                    ? const Center(
                                        child: SizedBox(
                                          width: 18, height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color:
                                                  AppConstants.primaryRed),
                                        ))
                                    : Center(
                                        child: Text(emoji,
                                            style: const TextStyle(
                                                fontSize: 18))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSel
                                        ? AppConstants.primaryRed
                                        : Colors.grey[800],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                    isPla
                                        ? Icons.stop_circle_outlined
                                        : Icons.play_circle_outline,
                                    size: 26,
                                    color: isPla
                                        ? AppConstants.primaryRed
                                        : Colors.grey[400]),
                                onPressed: () =>
                                    _previewSound(name, setM),
                                tooltip: 'Écouter',
                              ),
                              if (isSel)
                                const Icon(Icons.check_circle,
                                    color: AppConstants.primaryRed,
                                    size: 22)
                              else
                                TextButton(
                                  style: TextButton.styleFrom(
                                    backgroundColor:
                                        AppConstants.primaryRed,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _applySound(name, label, emoji);
                                  },
                                  child: const Text('Choisir',
                                      style: TextStyle(fontSize: 12)),
                                ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: _saveServerSettings,
            child: const Text('Enregistrer',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppConstants.primaryRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSoundCard(),
                const SizedBox(height: 14),
                _buildSectionCard(
                  title: 'Canaux',
                  icon: Icons.notifications_outlined,
                  tiles: [
                    _tile(Icons.email_outlined, 'Email',
                        'Notifications par email', _emailNotif,
                        (v) => setState(() => _emailNotif = v)),
                    _tile(Icons.phone_android, 'Push',
                        'Notifications sur l\'appareil', _pushNotif,
                        (v) => setState(() => _pushNotif = v)),
                    _tile(Icons.sms_outlined, 'SMS',
                        'Notifications par SMS', _smsNotif,
                        (v) => setState(() => _smsNotif = v)),
                  ],
                ),
                const SizedBox(height: 14),
                _buildSectionCard(
                  title: 'Types',
                  icon: Icons.tune,
                  tiles: [
                    _tile(Icons.message_outlined, 'Messages',
                        'Nouveaux messages', _messageNotif,
                        (v) => setState(() => _messageNotif = v)),
                    _tile(Icons.calendar_today_outlined, 'Rendez-vous',
                        'Rappels et confirmations', _appointmentNotif,
                        (v) => setState(() => _appointmentNotif = v)),
                    _tile(Icons.local_offer_outlined, 'Promotions',
                        'Offres spéciales', _promoNotif,
                        (v) => setState(() => _promoNotif = v)),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _buildSoundCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.music_note,
                  color: AppConstants.primaryRed, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Son de notification',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(height: 1),
        InkWell(
          onTap: _showSoundPicker,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color:
                        AppConstants.primaryRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: _isSavingSound
                    ? const Center(
                        child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppConstants.primaryRed)))
                    : Center(
                        child: Text(_selectedEmoji,
                            style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Son actuel',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text(
                    _isSavingSound
                        ? 'Mise à jour…'
                        : _selectedLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primaryRed,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right,
                  color: AppConstants.primaryRed, size: 20),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> tiles,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon,
                  color: AppConstants.primaryRed, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(height: 1),
        ...tiles,
      ]),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle,
      bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      secondary: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: AppConstants.primaryRed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child:
            Icon(icon, size: 18, color: AppConstants.primaryRed),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      value: value,
      onChanged: onChanged,
      activeColor: AppConstants.primaryRed,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }
}