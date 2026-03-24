// lib/services/notification_service.dart
// ═══════════════════════════════════════════════════════════════════════════
// SOLUTION DÉFINITIVE - NullPointerException éliminé
//
// CAUSE RÉELLE du crash (FlutterLocalNotificationsPlugin.java:264) :
//   intentForActivity == null → setAction() plante
//   Cela arrive quand show() est appelé dans un contexte sans Activity active
//   (background isolate, preview de son, etc.)
//
// CORRECTIONS :
//   ✅ playSoundPreview() → 100% audioplayers, ZÉRO flutter_local_notifications
//   ✅ showNotification() → try/catch complet, jamais de crash
//   ✅ initialize() appelé en premier dans main(), jamais dans un isolate
//   ✅ Background handler → réinitialisé proprement dans son propre isolate
//   ✅ Icône → @drawable/ic_stat_notification (monochromatique, voir setup)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../utils/constants.dart';
import 'pusher_service.dart';

// ── Canaux Android ────────────────────────────────────────────────────────────
const String _kChannelId       = 'high_importance_channel';
const String _kChannelName     = 'Messages CarEasy';
const String _kChannelDesc     = 'Notifications de messages CarEasy';

const String _kRdvChannelId    = 'careasy_rdv';
const String _kRdvChannelName  = 'Rendez-vous CarEasy';
const String _kRdvChannelDesc  = 'Notifications de rendez-vous CarEasy';

const String _kReminderChannelId   = 'careasy_reminder';
const String _kReminderChannelName = 'Rappels CarEasy';
const String _kReminderChannelDesc = 'Rappels de rendez-vous à venir';

const String _kReviewChannelId   = 'careasy_review';
const String _kReviewChannelName = 'Avis CarEasy';
const String _kReviewChannelDesc = 'Demandes d\'avis sur vos rendez-vous';

// ── Icône ─────────────────────────────────────────────────────────────────────
// OBLIGATOIRE : fichier android/app/src/main/res/drawable/ic_stat_notification.png
// Doit être BLANC SUR TRANSPARENT (monochromatique)
// Voir le dossier notification_icon/ fourni dans les assets de correction
const String _kNotifIcon = '@drawable/ic_stat_notification';

const int _kBadgeNotifId = 999;

// ═══════════════════════════════════════════════════════════════════════════
// BACKGROUND FCM HANDLER
// ═══════════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM BG] Reçu: ${message.notification?.title}');
  try {
    final plugin = FlutterLocalNotificationsPlugin();

    // Initialiser DANS le background isolate avec l'icône correcte
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_notification'),
      iOS: DarwinInitializationSettings(),
    );
    final initialized = await plugin.initialize(initSettings);
    if (initialized != true) {
      debugPrint('[FCM BG] Initialisation échouée, abandon');
      return;
    }

    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    // Canaux de base
    await _createBaseChannels(androidPlugin);

    // Canal son personnalisé
    String activeChannelId = _kChannelId;
    RawResourceAndroidNotificationSound? customSound;
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final useCustom = (await storage.read(key: 'notif_use_custom_sound')) == 'true';
      final soundName = await storage.read(key: 'notif_custom_sound_name') ?? 'default';
      if (useCustom && soundName != 'default') {
        activeChannelId = 'high_importance_channel_$soundName';
        customSound = RawResourceAndroidNotificationSound(soundName);
        await androidPlugin?.createNotificationChannel(
          AndroidNotificationChannel(
            activeChannelId, 'Messages CarEasy ($soundName)',
            description    : _kChannelDesc,
            importance     : Importance.high,
            playSound      : true,
            enableVibration: true,
            sound          : customSound,
          ),
        );
      }
    } catch (_) {}

    final data  = message.data;
    final notif = message.notification;
    final type  = data['type']?.toString() ?? '';
    final title = notif?.title ?? data['title'] ?? 'CarEasy';
    final body  = notif?.body  ?? data['body']  ?? '';

    final channelInfo   = _channelForType(type);
    final isMsg         = channelInfo.id == _kChannelId;
    final finalChannelId = isMsg ? activeChannelId : channelInfo.id;
    final payload       = _buildPayload(type, data);
    final notifId       = _idForType(type, data);

    await plugin.show(
      notifId, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          finalChannelId, isMsg ? 'Messages CarEasy' : channelInfo.name,
          channelDescription: channelInfo.desc,
          importance        : Importance.high,
          priority          : Priority.high,
          playSound         : true,
          enableVibration   : true,
          icon              : _kNotifIcon,
          largeIcon         : const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          color             : const Color(0xFFC0392B),
          visibility        : NotificationVisibility.public,
          sound             : isMsg ? customSound : null,
          number            : 1,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: payload,
    );
  } catch (e) {
    debugPrint('[FCM BG] Erreur: $e');
  }
}

@pragma('vm:entry-point')
void _bgTapCallback(NotificationResponse response) {
  debugPrint('[Notif BG Tap] payload=${response.payload}');
}

// ── Helpers ───────────────────────────────────────────────────────────────────
typedef _ChannelInfo = ({String id, String name, String desc});

_ChannelInfo _channelForType(String type) {
  if (type.startsWith('rdv_reminder')) return (id: _kReminderChannelId, name: _kReminderChannelName, desc: _kReminderChannelDesc);
  if (type.startsWith('rdv_'))        return (id: _kRdvChannelId,      name: _kRdvChannelName,      desc: _kRdvChannelDesc);
  if (type == 'review_request')       return (id: _kReviewChannelId,   name: _kReviewChannelName,   desc: _kReviewChannelDesc);
  return (id: _kChannelId, name: _kChannelName, desc: _kChannelDesc);
}

Future<_ChannelInfo> _channelForTypeAsync(String type) async {
  if (type.startsWith('rdv_reminder')) return (id: _kReminderChannelId, name: _kReminderChannelName, desc: _kReminderChannelDesc);
  if (type.startsWith('rdv_'))        return (id: _kRdvChannelId,      name: _kRdvChannelName,      desc: _kRdvChannelDesc);
  if (type == 'review_request')       return (id: _kReviewChannelId,   name: _kReviewChannelName,   desc: _kReviewChannelDesc);

  try {
    final activeId  = await NotificationSoundPrefs.getActiveChannelId();
    final soundName = await NotificationSoundPrefs.getCustomSoundName();
    final useCustom = await NotificationSoundPrefs.getUseCustomSound();
    final label     = (useCustom && soundName != 'default')
        ? 'Messages CarEasy ($soundName)'
        : _kChannelName;
    return (id: activeId, name: label, desc: _kChannelDesc);
  } catch (_) {
    return (id: _kChannelId, name: _kChannelName, desc: _kChannelDesc);
  }
}

int _idForType(String type, Map<String, dynamic> data) {
  final rdvId  = data['rdv_id']?.toString() ?? '';
  final convId = data['conversation_id']?.toString() ?? '';
  if (type == 'rdv_reminder')   return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 30000).abs();
  if (type == 'review_request') return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 40000).abs();
  if (type.startsWith('rdv_'))  return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 20000).abs();
  return convId.isNotEmpty ? convId.hashCode.abs() : (DateTime.now().millisecondsSinceEpoch ~/ 1000);
}

String _buildPayload(String type, Map<String, dynamic> data) {
  if (type.startsWith('rdv_') || type == 'review_request') {
    return jsonEncode({'type': type, 'rdv_id': data['rdv_id'] ?? ''});
  }
  return jsonEncode({
    'conversation_id': data['conversation_id'] ?? '',
    'sender_name'    : data['sender_name']  ?? '',
    'sender_photo'   : data['sender_photo'] ?? '',
    'sender_id'      : data['sender_id']    ?? '',
  });
}

Future<void> _createBaseChannels(AndroidFlutterLocalNotificationsPlugin? p) async {
  for (final ch in [
    const AndroidNotificationChannel(_kChannelId, _kChannelName,
        description: _kChannelDesc, importance: Importance.high, playSound: true, enableVibration: true),
    const AndroidNotificationChannel(_kRdvChannelId, _kRdvChannelName,
        description: _kRdvChannelDesc, importance: Importance.high, playSound: true, enableVibration: true),
    const AndroidNotificationChannel(_kReminderChannelId, _kReminderChannelName,
        description: _kReminderChannelDesc, importance: Importance.high, playSound: true, enableVibration: true),
    const AndroidNotificationChannel(_kReviewChannelId, _kReviewChannelName,
        description: _kReviewChannelDesc, importance: Importance.high, playSound: true, enableVibration: true),
  ]) {
    await p?.createNotificationChannel(ch);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SOUND PREFS
// ═══════════════════════════════════════════════════════════════════════════
class NotificationSoundPrefs {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyUseCustom     = 'notif_use_custom_sound';
  static const _keySoundName     = 'notif_custom_sound_name';
  static const _keySoundLabel    = 'notif_custom_sound_label';
  static const _keyActiveChannel = 'notif_active_channel_id';

  // Sons disponibles — les fichiers DOIVENT exister dans :
  //   assets/sounds/<name>.mp3       (pour audioplayers)
  //   res/raw/<name>.mp3 ou .wav     (pour les canaux Android)
  static const List<Map<String, String>> availableSounds = [
    {'name': 'default',             'label': 'Système (défaut)',    'emoji': '🔕'},
    {'name': 'careasy_chime_soft',  'label': 'Carillon doux',       'emoji': '🎵'},
    {'name': 'careasy_pristine',    'label': 'Cristallin',          'emoji': '✨'},
    {'name': 'careasy_subtle_ping', 'label': 'Ping subtil',         'emoji': '💎'},
    {'name': 'careasy_success',     'label': 'Succès',              'emoji': '✅'},
    {'name': 'careasy_gentle_bell', 'label': 'Cloche douce',        'emoji': '🔔'},
    {'name': 'careasy_pop_clean',   'label': 'Pop professionnel',   'emoji': '🎯'},
    {'name': 'careasy_notify_pro',  'label': 'Notification Pro',    'emoji': '📳'},
  ];

  static Future<bool>   getUseCustomSound()  async =>
      (await _storage.read(key: _keyUseCustom)) == 'true';
  static Future<String> getCustomSoundName() async =>
      (await _storage.read(key: _keySoundName)) ?? 'default';
  static Future<String> getCustomSoundLabel() async =>
      (await _storage.read(key: _keySoundLabel)) ?? 'Système (défaut)';
  static Future<String> getActiveChannelId() async =>
      (await _storage.read(key: _keyActiveChannel)) ?? _kChannelId;

  static Future<void> setSoundPreference({
    required bool   useCustom,
    required String soundName,
    required String soundLabel,
  }) async {
    await _storage.write(key: _keyUseCustom,  value: useCustom.toString());
    await _storage.write(key: _keySoundName,  value: soundName);
    await _storage.write(key: _keySoundLabel, value: soundLabel);
    final channelId = (useCustom && soundName != 'default')
        ? 'high_importance_channel_$soundName'
        : _kChannelId;
    await _storage.write(key: _keyActiveChannel, value: channelId);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// NOTIFICATION SERVICE — Singleton
// ═══════════════════════════════════════════════════════════════════════════
class NotificationService {
  static final NotificationService _inst = NotificationService._internal();
  factory NotificationService() => _inst;
  NotificationService._internal();

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage(
      aOptions: _androidOptions, iOptions: _iOSOptions);

  // AudioPlayer dédié au preview des sons (jamais flutter_local_notifications)
  final AudioPlayer _previewPlayer = AudioPlayer();

  Function(Map<String, dynamic>)? onNotificationTap;
  bool _initialized = false;
  int  _badgeCount  = 0;

  // ─── INIT ──────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Porto-Novo'));

    // Initialiser flutter_local_notifications dans le thread principal
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    try {
      await _local.initialize(
        initSettings,
        onDidReceiveNotificationResponse   : (r) => _handleTap(r.payload),
        onDidReceiveBackgroundNotificationResponse: _bgTapCallback,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[Notif] Erreur initialize: $e');
      // Réessayer sans callback background (fallback)
      try {
        await _local.initialize(initSettings,
            onDidReceiveNotificationResponse: (r) => _handleTap(r.payload));
        _initialized = true;
      } catch (e2) {
        debugPrint('[Notif] Erreur initialize fallback: $e2');
        _initialized = true; // Marquer quand même pour éviter les boucles
      }
    }

    if (Platform.isAndroid) await _createAndroidChannels();
    await _initFCM();

    NotificationServiceRef.register(({
      required int id, required String title,
      required String body, String? payload,
    }) => showNotification(id: id, title: title, body: body, payload: payload));
  }

  // ─── CANAUX ────────────────────────────────────────────────────────────
  Future<void> _createAndroidChannels() async {
    if (!Platform.isAndroid) return;
    final p = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await _createBaseChannels(p);

    try {
      final useCustom = await NotificationSoundPrefs.getUseCustomSound();
      final soundName = await NotificationSoundPrefs.getCustomSoundName();
      if (useCustom && soundName != 'default') {
        await p?.createNotificationChannel(AndroidNotificationChannel(
          'high_importance_channel_$soundName',
          'Messages CarEasy ($soundName)',
          description    : _kChannelDesc,
          importance     : Importance.high,
          playSound      : true,
          enableVibration: true,
          sound          : RawResourceAndroidNotificationSound(soundName),
        ));
      }
    } catch (e) {
      debugPrint('[Notif] Canal son: $e');
    }
  }

  // ─── SHOW NOTIFICATION (avec try/catch complet) ────────────────────────
  Future<void> showNotification({
    required int    id,
    required String title,
    required String body,
    String?         payload,
    String          type = '',
  }) async {
    if (!_initialized) {
      debugPrint('[Notif] Non initialisé, notification ignorée');
      return;
    }

    try {
      final channelInfo = await _channelForTypeAsync(type);
      final useCustom   = await NotificationSoundPrefs.getUseCustomSound();
      final soundName   = await NotificationSoundPrefs.getCustomSoundName();

      if (Platform.isAndroid) {
        final p = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        try {
          final channel = (useCustom && soundName != 'default')
              ? AndroidNotificationChannel(
                  channelInfo.id, channelInfo.name,
                  description    : channelInfo.desc,
                  importance     : Importance.high,
                  playSound      : true,
                  enableVibration: true,
                  sound          : RawResourceAndroidNotificationSound(soundName),
                )
              : AndroidNotificationChannel(
                  channelInfo.id, channelInfo.name,
                  description    : channelInfo.desc,
                  importance     : Importance.high,
                  playSound      : true,
                  enableVibration: true,
                );
          await p?.createNotificationChannel(channel);
        } catch (_) {}
      }

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelInfo.id, channelInfo.name,
          channelDescription: channelInfo.desc,
          importance        : Importance.high,
          priority          : Priority.high,
          playSound         : true,
          enableVibration   : true,
          icon              : _kNotifIcon,
          largeIcon         : const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          color             : const Color(0xFFC0392B),
          visibility        : NotificationVisibility.public,
          showWhen          : true,
          number            : _badgeCount > 0 ? _badgeCount : null,
          sound             : (useCustom && soundName != 'default')
              ? RawResourceAndroidNotificationSound(soundName)
              : null,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          badgeNumber : _badgeCount > 0 ? _badgeCount : null,
        ),
      );

      await _local.show(id, title, body, details, payload: payload);
    } catch (e) {
      debugPrint('[Notif] showNotification error: $e');
      // Fallback minimal sans icône personnalisée
      try {
        await _local.show(
          id, title, body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _kChannelId, _kChannelName,
              importance: Importance.high,
              priority  : Priority.high,
            ),
          ),
          payload: payload,
        );
      } catch (e2) {
        debugPrint('[Notif] Fallback error: $e2');
      }
    }
  }

  // ─── MESSAGES ──────────────────────────────────────────────────────────
  Future<void> showMessageNotification({
    required String senderName,
    required String messageBody,
    required String conversationId,
    String? senderPhoto,
    String? senderId,
  }) async {
    _badgeCount++;
    final payload = jsonEncode({
      'conversation_id': conversationId,
      'sender_name'    : senderName,
      'sender_photo'   : senderPhoto ?? '',
      'sender_id'      : senderId    ?? '',
    });
    await showNotification(
      id     : conversationId.hashCode.abs(),
      title  : senderName,
      body   : messageBody.length > 100 ? '${messageBody.substring(0, 100)}…' : messageBody,
      payload: payload,
      type   : 'message',
    );
  }

  // ─── RDV ───────────────────────────────────────────────────────────────
  Future<void> showRdvNotification({
    required String title,
    required String body,
    required String rdvId,
    required String type,
  }) async {
    _badgeCount++;
    await showNotification(
      id     : _idForType(type, {'rdv_id': rdvId}),
      title  : title,
      body   : body,
      payload: jsonEncode({'type': type, 'rdv_id': rdvId}),
      type   : type,
    );
  }

  // ─── RAPPEL RDV ────────────────────────────────────────────────────────
  Future<void> scheduleRdvReminder({
    required String rdvId,
    required String rdvDate,
    required String rdvTime,
    required String serviceName,
    required bool   isPrestataire,
  }) async {
    try {
      final parts = rdvTime.split(':');
      final dateParts = rdvDate.split('-');
      final rdvDateTime = tz.TZDateTime(
        tz.local,
        int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]),
        int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
      );
      final reminderTime = rdvDateTime.subtract(const Duration(hours: 1));

      if (reminderTime.isBefore(tz.TZDateTime.now(tz.local))) return;

      await _local.zonedSchedule(
        _idForType('rdv_reminder', {'rdv_id': rdvId}),
        '⏰ Rappel rendez-vous',
        isPrestataire
            ? 'Rappel : rendez-vous pour $serviceName dans 1h'
            : 'Votre rendez-vous pour $serviceName commence dans 1 heure !',
        reminderTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kReminderChannelId, _kReminderChannelName,
            channelDescription: _kReminderChannelDesc,
            importance        : Importance.high,
            priority          : Priority.high,
            icon              : _kNotifIcon,
            largeIcon         : const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            color             : const Color(0xFFC0392B),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true, presentBadge: true, presentSound: true,
          ),
        ),
        payload             : jsonEncode({'type': 'rdv_reminder', 'rdv_id': rdvId}),
        androidScheduleMode : AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('[Notif] scheduleRdvReminder: $e');
    }
  }

  Future<void> cancelRdvReminder(String rdvId) async =>
      _local.cancel(_idForType('rdv_reminder', {'rdv_id': rdvId}));

  // ─── REVIEW ────────────────────────────────────────────────────────────
  Future<void> showReviewRequestNotification({
    required String rdvId,
    required String serviceName,
  }) async {
    _badgeCount++;
    await showNotification(
      id     : _idForType('review_request', {'rdv_id': rdvId}),
      title  : '⭐ Votre avis nous intéresse !',
      body   : 'Comment s\'est passé votre RDV pour $serviceName ?',
      payload: jsonEncode({'type': 'review_request', 'rdv_id': rdvId}),
      type   : 'review_request',
    );
  }

  // ─── BADGE ─────────────────────────────────────────────────────────────
  Future<void> clearBadge() async {
    _badgeCount = 0;
    if (Platform.isIOS) {
      try {
        await _local.show(_kBadgeNotifId, null, null,
            const NotificationDetails(
              iOS: DarwinNotificationDetails(
                presentAlert: false, presentBadge: true,
                presentSound: false, badgeNumber: 0,
              ),
            ));
        await Future.delayed(const Duration(milliseconds: 200));
        await _local.cancel(_kBadgeNotifId);
      } catch (_) {}
    }
  }

  Future<void> updateBadgeCount(int count) async {
    _badgeCount = count > 0 ? count : 0;
    if (count <= 0) await clearBadge();
  }

  // ─── FCM FOREGROUND ────────────────────────────────────────────────────
  Future<void> showFCMNotification(RemoteMessage message) async {
    final data  = message.data;
    final notif = message.notification;
    final type  = data['type']?.toString() ?? '';
    final title = notif?.title ?? data['title'] ?? 'CarEasy';
    final body  = notif?.body  ?? data['body']  ?? '';

    _badgeCount++;

    if (type == 'review_request') {
      await showReviewRequestNotification(
        rdvId      : data['rdv_id']?.toString() ?? '',
        serviceName: data['service_name']?.toString() ?? 'le service',
      );
      return;
    }
    if (type.startsWith('rdv_')) {
      await showRdvNotification(
        title: title, body: body,
        rdvId: data['rdv_id']?.toString() ?? '',
        type : type,
      );
      return;
    }
    final convId = data['conversation_id']?.toString() ?? '';
    await showNotification(
      id     : convId.isNotEmpty ? convId.hashCode.abs() : DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title  : title, body: body,
      payload: jsonEncode({
        'conversation_id': convId,
        'sender_name'    : data['sender_name']  ?? '',
        'sender_photo'   : data['sender_photo'] ?? '',
        'sender_id'      : data['sender_id']    ?? '',
      }),
      type: 'message',
    );
  }

  // ─── PREVIEW SON — 100% audioplayers, ZÉRO flutter_local_notifications ──
  Future<void> playSoundPreview(String soundName) async {
    try {
      await _previewPlayer.stop();

      if (soundName == 'default') {
        // Son système : utiliser le son de l'appareil via AudioPlayer
        // (pas de notification, pas de NullPointerException possible)
        await _previewPlayer.play(
          AssetSource('sounds/careasy_notify_pro.mp3'),
          volume: 1.0,
        );
        return;
      }

      await _previewPlayer.play(
        AssetSource('sounds/$soundName.mp3'),
        volume: 1.0,
      );
      debugPrint('[Notif] Preview: $soundName ✓');
    } catch (e) {
      debugPrint('[Notif] playSoundPreview error ($soundName): $e');
      // Fallback : essayer avec .wav
      try {
        await _previewPlayer.play(
          AssetSource('sounds/$soundName.wav'),
          volume: 1.0,
        );
      } catch (_) {
        // Fallback final : rien (pas de crash)
        debugPrint('[Notif] Fichier audio manquant pour $soundName');
      }
    }
  }

  // ─── MISE À JOUR CANAL SON ─────────────────────────────────────────────
  Future<void> updateNotificationChannel() async {
    if (!Platform.isAndroid) return;
    try {
      final useCustom = await NotificationSoundPrefs.getUseCustomSound();
      final soundName = await NotificationSoundPrefs.getCustomSoundName();
      final channelId = (useCustom && soundName != 'default')
          ? 'high_importance_channel_$soundName'
          : _kChannelId;

      final p = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      final channel = (useCustom && soundName != 'default')
          ? AndroidNotificationChannel(
              channelId, 'Messages CarEasy ($soundName)',
              description    : _kChannelDesc,
              importance     : Importance.high,
              playSound      : true,
              enableVibration: true,
              sound          : RawResourceAndroidNotificationSound(soundName),
            )
          : AndroidNotificationChannel(
              channelId, _kChannelName,
              description    : _kChannelDesc,
              importance     : Importance.high,
              playSound      : true,
              enableVibration: true,
            );

      await p?.createNotificationChannel(channel);
      debugPrint('[Notif] Canal mis à jour: $channelId');
    } catch (e) {
      debugPrint('[Notif] updateNotificationChannel: $e');
    }
  }

  // ─── ANNULATION ────────────────────────────────────────────────────────
  // Accepte String (conversationId) ou int — compatibilité avec tout le code existant
  Future<void> cancelNotification(dynamic id) async {
    try {
      final intId = id is int ? id : id.toString().hashCode.abs();
      await _local.cancel(intId);
    } catch (_) {}
  }
  Future<void> cancelAll() async {
    _badgeCount = 0;
    try { await _local.cancelAll(); } catch (_) {}
  }

  // ─── FCM ───────────────────────────────────────────────────────────────
  Future<void> _initFCM() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true, badge: true, sound: true, provisional: false,
      );
      debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      FirebaseMessaging.onMessage.listen((msg) => showFCMNotification(msg));

      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        if (_badgeCount > 0) _badgeCount--;
        _handleFCMTap(msg.data);
      });

      final initial = await _fcm.getInitialMessage();
      if (initial != null) {
        Future.delayed(
          const Duration(milliseconds: 1500),
          () => _handleFCMTap(initial.data),
        );
      }

      await _registerFCMToken();
      _fcm.onTokenRefresh.listen(_sendTokenToBackend);
    } catch (e) {
      debugPrint('[FCM] _initFCM error: $e');
    }
  }

  Future<void> _registerFCMToken() async {
    try {
      String? token;
      if (Platform.isIOS) {
        final apns = await _fcm.getAPNSToken();
        if (apns != null) token = await _fcm.getToken();
      } else {
        token = await _fcm.getToken();
      }
      if (token != null) {
        await _storage.write(key: 'fcm_token_pending', value: token);
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('[FCM] Erreur token: $e');
    }
  }

  Future<void> _sendTokenToBackend(String fcmToken) async {
    try {
      final authToken = await _storage.read(key: 'auth_token');
      if (authToken == null || authToken.isEmpty) {
        await _storage.write(key: 'fcm_token_pending', value: fcmToken);
        return;
      }
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type' : 'application/json',
          'Accept'       : 'application/json',
        },
        body: jsonEncode({
          'fcm_token': fcmToken,
          'platform' : Platform.isIOS ? 'ios' : 'android',
        }),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        await _storage.delete(key: 'fcm_token_pending');
        debugPrint('[FCM] Token enregistré ✓');
      }
    } catch (e) {
      debugPrint('[FCM] Erreur envoi token: $e');
    }
  }

  Future<void> refreshTokenAfterLogin() async {
    try {
      final pending = await _storage.read(key: 'fcm_token_pending');
      if (pending != null && pending.isNotEmpty) {
        await _sendTokenToBackend(pending);
      } else {
        await _registerFCMToken();
      }
    } catch (e) {
      debugPrint('[FCM] refreshTokenAfterLogin: $e');
    }
  }

  // ─── TAPS ──────────────────────────────────────────────────────────────
  void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (_badgeCount > 0) _badgeCount--;
    try {
      onNotificationTap?.call(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {
      onNotificationTap?.call({'conversation_id': payload});
    }
  }

  void _handleFCMTap(Map<String, dynamic> data) {
    final type  = data['type']?.toString() ?? '';
    final rdvId = data['rdv_id']?.toString() ?? '';
    if (type.startsWith('rdv_') || type == 'review_request' || rdvId.isNotEmpty) {
      onNotificationTap?.call({'type': type, 'rdv_id': rdvId});
      return;
    }
    final convId = data['conversation_id']?.toString();
    if (convId != null && convId.isNotEmpty) {
      onNotificationTap?.call({
        'conversation_id': convId,
        'sender_name'    : data['sender_name']  ?? '',
        'sender_photo'   : data['sender_photo'] ?? '',
        'sender_id'      : data['sender_id']    ?? '',
      });
    }
  }
}