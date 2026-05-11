// lib/screens/notifications_settings_screen.dart
// ═══════════════════════════════════════════════════════════════════════════
// Écran Paramètres Notifications — VERSION FONCTIONNELLE
//
// Canaux : Email · SMS · WhatsApp · Push
// Types  : Message · Rendez-vous · Rappel · Nouveau service
//
// Chaque toggle est lié à l'API (GET + PUT /user/notification-settings).
// Les préférences sont persistées côté serveur ET en cache local.
// Le push FCM est géré nativement (demande de permission si activé).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../utils/constants.dart';
import '../services/notification_service.dart';

// ─── Modèle local des préférences ─────────────────────────────────────────
class _NotifPrefs {
  // Canaux
  bool email    = true;
  bool sms      = false;
  bool whatsapp = true;
  bool push     = true;

  // Types
  bool message    = true;
  bool rdv        = true;
  bool reminder   = true;
  bool newService = true;

  Map<String, dynamic> toChannelsMap() => {
    'email':    email,
    'sms':      sms,
    'whatsapp': whatsapp,
    'push':     push,
  };

  Map<String, dynamic> toTypesMap() => {
    'message':     message,
    'rdv':         rdv,
    'reminder':    reminder,
    'new_service': newService,
  };

  void fromJson(Map<String, dynamic> json) {
    final ch = json['channels'] as Map<String, dynamic>? ?? {};
    final ty = json['types']   as Map<String, dynamic>? ?? {};

    // Rétro-compat ancienne structure plate
    if (ch.isEmpty && json.containsKey('email')) {
      email    = json['email']    as bool? ?? true;
      sms      = json['sms']      as bool? ?? false;
      push     = json['push']     as bool? ?? true;
      whatsapp = json['whatsapp'] as bool? ?? true;
    } else {
      email    = ch['email']    as bool? ?? true;
      sms      = ch['sms']      as bool? ?? false;
      whatsapp = ch['whatsapp'] as bool? ?? true;
      push     = ch['push']     as bool? ?? true;
    }

    message    = ty['message']     as bool? ?? true;
    rdv        = ty['rdv']         as bool? ?? true;
    reminder   = ty['reminder']    as bool? ?? true;
    newService = ty['new_service'] as bool? ?? true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  static const _aOpts = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOpts =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _storage =
      const FlutterSecureStorage(aOptions: _aOpts, iOptions: _iOpts);

  final _prefs = _NotifPrefs();

  bool   _isLoading     = true;
  bool   _isSaving      = false;
  bool   _isSavingSound = false;
  String _playingSound  = '';
  String? _customMp3Path;

  String _selectedSound = 'default';
  String _selectedLabel = 'Système (défaut)';
  String _selectedEmoji = '';

  // ─── Permissions push ──────────────────────────────────────────────────
  bool _pushPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ─── Chargement initial ────────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() => _isLoading = true);

    await Future.wait([
      _loadServerPrefs(),
      _loadSoundPrefs(),
      _checkPushPermission(),
    ]);

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadServerPrefs() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      final resp = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/user/notification-settings'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _prefs.fromJson(data);
      }
    } catch (e) {
      debugPrint('[NotifSettings] _loadServerPrefs: $e');
    }
  }

  Future<void> _loadSoundPrefs() async {
    final soundName  = await NotificationSoundPrefs.getCustomSoundName();
    final soundLabel = await NotificationSoundPrefs.getCustomSoundLabel();
    final customMp3  = await NotificationSoundPrefs.getCustomMp3Path();
    final soundInfo  = NotificationSoundPrefs.availableSounds.firstWhere(
      (s) => s['name'] == soundName,
      orElse: () => NotificationSoundPrefs.availableSounds.first,
    );

    if (mounted) {
      setState(() {
        _selectedSound = soundName;
        _selectedLabel = soundLabel;
        _selectedEmoji = soundInfo['emoji'] ?? '📱';
        _customMp3Path = customMp3;
      });
    }
  }

  Future<void> _checkPushPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (mounted) {
        setState(() {
          _pushPermissionGranted =
              settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
        });
      }
    } catch (_) {}
  }

  // ─── Sauvegarde ───────────────────────────────────────────────────────
  Future<void> _save() async {
    setState(() => _isSaving = true);

    // Si push activé → demander la permission
    if (_prefs.push && !_pushPermissionGranted) {
      await _requestPushPermission();
    }

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      final resp = await http
          .put(
            Uri.parse('${AppConstants.apiBaseUrl}/user/notification-settings'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'channels': _prefs.toChannelsMap(),
              'types':    _prefs.toTypesMap(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        _snack('Préférences enregistrées', Colors.green);

        // Si push désactivé → retirer les permissions localement (Android)
        if (!_prefs.push) {
          await NotificationService().cancelAll();
        }
      } else {
        _snack('Erreur lors de la sauvegarde', Colors.red);
      }
    } catch (e) {
      _snack('Erreur de connexion', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _requestPushPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      setState(() {
        _pushPermissionGranted =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      });
      if (!_pushPermissionGranted) {
        // L'utilisateur a refusé → désactiver le toggle
        setState(() => _prefs.push = false);
        _snack(
          'Permission refusée. Activez les notifications dans les paramètres système.',
          Colors.orange,
        );
      }
    } catch (_) {}
  }

  // ─── Son ──────────────────────────────────────────────────────────────
  Future<void> _applySound(String name, String label, String emoji,
      {String? mp3Path}) async {
    if (!mounted) return;
    setState(() => _isSavingSound = true);

    await NotificationSoundPrefs.setSoundPreference(
      useCustom:    name != 'default',
      soundName:    name,
      soundLabel:   label,
      customMp3Path: mp3Path,
    );
    await NotificationService().updateNotificationChannel();

    if (mounted) {
      setState(() {
        _selectedSound = name;
        _selectedLabel = label;
        _selectedEmoji = emoji;
        _customMp3Path = mp3Path;
        _isSavingSound = false;
      });
    }

    await Future.delayed(const Duration(milliseconds: 200));
    await NotificationService().playSoundPreview(name);
    if (mounted) _snack('Son mis à jour : $label', Colors.green);
  }

  Future<void> _pickCustomMp3() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      final sourcePath = pickedFile.path;
      if (sourcePath == null) return;

      setState(() => _isSavingSound = true);

      final appDir   = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${appDir.path}/custom_sounds');
      if (!await soundsDir.exists()) await soundsDir.create(recursive: true);

      final fileName = 'custom_notif_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final destPath = '${soundsDir.path}/$fileName';
      await File(sourcePath).copy(destPath);

      if (_customMp3Path != null && _customMp3Path != destPath) {
        try { await File(_customMp3Path!).delete(); } catch (_) {}
      }

      final label = p.basenameWithoutExtension(pickedFile.name);
      await _applySound(destPath, label, '🎵', mp3Path: destPath);
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingSound = false);
        _snack('Erreur lors de l\'import du fichier', Colors.red);
      }
    }
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

  // ─── BUILD ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'Enregistrer',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
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
                // ── Canaux ─────────────────────────────────────────────────
                _buildSectionCard(
                  title: 'Canaux de notification',
                  subtitle: 'Choisissez comment vous souhaitez être notifié',
                  icon: Icons.campaign_outlined,
                  tiles: [
                    _channelTile(
                      icon: Icons.email_outlined,
                      iconColor: const Color(0xFF3B82F6),
                      title: 'Email',
                      subtitle: 'Notifications par email',
                      value: _prefs.email,
                      onChanged: (v) => setState(() => _prefs.email = v),
                    ),
                    _channelTile(
                      icon: Icons.sms_outlined,
                      iconColor: const Color(0xFF22C55E),
                      title: 'SMS',
                      subtitle: 'Notifications par SMS',
                      value: _prefs.sms,
                      onChanged: (v) => setState(() => _prefs.sms = v),
                    ),
                    _channelTile(
                      icon: Icons.chat_outlined,
                      iconColor: const Color(0xFF25D366),
                      title: 'WhatsApp',
                      subtitle: 'Notifications via WhatsApp',
                      value: _prefs.whatsapp,
                      onChanged: (v) => setState(() => _prefs.whatsapp = v),
                      emoji: '💬',
                    ),
                    _channelTile(
                      icon: Icons.phone_android,
                      iconColor: AppConstants.primaryRed,
                      title: 'Push (application)',
                      subtitle: _pushPermissionGranted
                          ? 'Notifications sur cet appareil'
                          : 'Permission requise — appuyez pour activer',
                      value: _prefs.push,
                      onChanged: (v) async {
                        if (v && !_pushPermissionGranted) {
                          // Demander permission avant d'activer
                          await _requestPushPermission();
                        } else {
                          setState(() => _prefs.push = v);
                        }
                      },
                      warning: !_pushPermissionGranted && _prefs.push
                          ? 'Permission non accordée'
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Types ──────────────────────────────────────────────────
                _buildSectionCard(
                  title: 'Types de notification',
                  subtitle: 'Filtrez par catégorie ce que vous recevez',
                  icon: Icons.tune_outlined,
                  tiles: [
                    _typeTile(
                      icon: Icons.message_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                      title: 'Messages',
                      subtitle: 'Nouveaux messages reçus',
                      value: _prefs.message,
                      onChanged: (v) => setState(() => _prefs.message = v),
                    ),
                    _typeTile(
                      icon: Icons.calendar_month_outlined,
                      iconColor: const Color(0xFFF59E0B),
                      title: 'Rendez-vous',
                      subtitle: 'Confirmations, annulations, statuts RDV',
                      value: _prefs.rdv,
                      onChanged: (v) => setState(() => _prefs.rdv = v),
                    ),
                    _typeTile(
                      icon: Icons.alarm_outlined,
                      iconColor: const Color(0xFFEF4444),
                      title: 'Rappels',
                      subtitle: 'Rappels J-1 et relances d\'inactivité',
                      value: _prefs.reminder,
                      onChanged: (v) => setState(() => _prefs.reminder = v),
                    ),
                    _typeTile(
                      icon: Icons.storefront_outlined,
                      iconColor: const Color(0xFF06B6D4),
                      title: 'Nouveaux services',
                      subtitle: 'Quand un nouveau service est disponible',
                      value: _prefs.newService,
                      onChanged: (v) => setState(() => _prefs.newService = v),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Aperçu visuel des préférences actives ──────────────────
                _buildPreviewCard(),
                const SizedBox(height: 14),

                // ── Son ───────────────────────────────────────────────────
                _buildSoundCard(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  // ─── Carte section générique ──────────────────────────────────────────
  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> tiles,
  }) {
    return Container(
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: AppConstants.primaryRed, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500])),
              ]),
            ),
          ]),
        ),
        const Divider(height: 1),
        ...tiles,
      ]),
    );
  }

  // ─── Tile canal ───────────────────────────────────────────────────────
  Widget _channelTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? emoji,
    String? warning,
  }) {
    return _tile(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
      emoji: emoji,
      warning: warning,
      badge: null,
    );
  }

  // ─── Tile type ────────────────────────────────────────────────────────
  Widget _typeTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _tile(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? emoji,
    String? warning,
    Widget? badge,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          // Icône
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: emoji != null
                ? Center(child: Text(emoji, style: const TextStyle(fontSize: 20)))
                : Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),

          // Texte
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const SizedBox(height: 8),
              Row(children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: value ? Colors.black87 : Colors.grey[500],
                    )),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  badge,
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                warning ?? subtitle,
                style: TextStyle(
                    fontSize: 11,
                    color: warning != null
                        ? Colors.orange
                        : Colors.grey[500]),
              ),
              const SizedBox(height: 8),
            ]),
          ),

          // Toggle
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppConstants.primaryRed,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ]),
      ),
    );
  }

  // ─── Carte aperçu des préférences actives ─────────────────────────────
  Widget _buildPreviewCard() {
    final activeChannels = <String>[];
    if (_prefs.email)    activeChannels.add('Email');
    if (_prefs.sms)      activeChannels.add('SMS');
    if (_prefs.whatsapp) activeChannels.add('WhatsApp');
    if (_prefs.push)     activeChannels.add('Push');

    final activeTypes = <String>[];
    if (_prefs.message)    activeTypes.add('Messages');
    if (_prefs.rdv)        activeTypes.add('RDV');
    if (_prefs.reminder)   activeTypes.add('Rappels');
    if (_prefs.newService) activeTypes.add('Nouveaux services');

    final allOff = activeChannels.isEmpty;

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            allOff ? Icons.notifications_off_outlined : Icons.check_circle_outline,
            color: allOff ? Colors.grey : Colors.green,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            allOff ? 'Aucune notification active' : 'Configuration active',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: allOff ? Colors.grey : Colors.black87,
            ),
          ),
        ]),
        if (!allOff) ...[
          const SizedBox(height: 12),
          _previewRow('📡 Canaux', activeChannels),
          const SizedBox(height: 6),
          _previewRow('🏷️ Types', activeTypes),
        ] else ...[
          const SizedBox(height: 6),
          Text(
            'Activez au moins un canal pour recevoir des notifications.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ]),
    );
  }

  Widget _previewRow(String label, List<String> items) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 90,
        child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      Expanded(
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: items
              .map((item) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppConstants.primaryRed,
                            fontWeight: FontWeight.w600)),
                  ))
              .toList(),
        ),
      ),
    ]);
  }

  // ─── Carte son ────────────────────────────────────────────────────────
  Widget _buildSoundCard() {
    return Container(
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.music_note,
                  color: AppConstants.primaryRed, size: 18),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Son de notification',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text('Son joué à la réception',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ]),
        ),
        const Divider(height: 1),
        InkWell(
          onTap: _showSoundPicker,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                    color: AppConstants.primaryRed.withOpacity(0.08),
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
                            style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Son actuel',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text(
                    _isSavingSound ? 'Mise à jour…' : _selectedLabel,
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

  // ─── Picker son ───────────────────────────────────────────────────────
  void _showSoundPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setM) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, sc) => Column(children: [
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
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('▶ pour écouter',
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
                    NotificationSoundPrefs.availableSounds.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  if (i == NotificationSoundPrefs.availableSounds.length) {
                    return Column(children: [
                      const Divider(height: 20),
                      Material(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.pop(ctx);
                            _pickCustomMp3();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            child: Row(children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                    color: AppConstants.primaryRed
                                        .withOpacity(0.1),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.upload_file_rounded,
                                    color: AppConstants.primaryRed,
                                    size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  const Text('Importer un fichier MP3',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                    _customMp3Path != null
                                        ? 'Actuel : $_selectedLabel'
                                        : 'Choisir depuis le téléphone',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ]),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppConstants.primaryRed),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ]);
                  }

                  final s     = NotificationSoundPrefs.availableSounds[i];
                  final name  = s['name']!;
                  final label = s['label']!;
                  final emoji = s['emoji'] ?? '';
                  final isSel = _selectedSound == name &&
                      !(_selectedSound.startsWith('/'));
                  final isPla = _playingSound == name;

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
                            onPressed: () => _previewSound(name, setM),
                            tooltip: 'Écouter',
                          ),
                          if (isSel)
                            const Icon(Icons.check_circle,
                                color: AppConstants.primaryRed,
                                size: 22)
                          else
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: AppConstants.primaryRed,
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
          ]),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2))
      ],
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }
}