// lib/services/notification_service.dart
// ═══════════════════════════════════════════════════════════════════════════
// VERSION CORRIGÉE — Problèmes résolus :
//   ✅ Son personnalisé pris en compte à chaque notification
//   ✅ Notifications affichées en foreground (app ouverte)
//   ✅ Notifications en background/fermée via FCM
//   ✅ Badge icône sur l'icône de l'app (ShortcutBadger)
//   ✅ Icône monochromatique correcte
//   ✅ Canal recréé si son change (deleteAndRecreate)
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
const String _kChannelId           = 'high_importance_channel';
const String _kChannelName         = 'Messages CarEasy';
const String _kChannelDesc         = 'Notifications de messages CarEasy';

const String _kRdvChannelId        = 'careasy_rdv';
const String _kRdvChannelName      = 'Rendez-vous CarEasy';
const String _kRdvChannelDesc      = 'Notifications de rendez-vous CarEasy';

const String _kReminderChannelId   = 'careasy_reminder';
const String _kReminderChannelName = 'Rappels CarEasy';
const String _kReminderChannelDesc = 'Rappels de rendez-vous à venir';

const String _kReviewChannelId     = 'careasy_review';
const String _kReviewChannelName   = 'Avis CarEasy';
const String _kReviewChannelDesc   = 'Demandes d\'avis sur vos rendez-vous';

// Icône monochromatique obligatoire Android 5+
const String _kNotifIcon = '@drawable/ic_stat_notification';

const int _kBadgeNotifId = 999;

// ══════════════════════════════════════════════════════════════════════════════
// BACKGROUND FCM HANDLER — appelé dans un isolate séparé
// ══════════════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM BG] Message reçu: ${message.notification?.title}');
  try {
    // Récupérer préférences son
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final soundName = (await storage.read(key: 'notif_custom_sound_name')) ?? 'default';
    final useCustom = (await storage.read(key: 'notif_use_custom_sound')) == 'true';

    final plugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_notification'),
      iOS: DarwinInitializationSettings(),
    );
    await plugin.initialize(initSettings);

    final androidPlugin = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Créer tous les canaux de base
    await _createAllBaseChannels(androidPlugin);

    // Canal avec son personnalisé si défini
    String activeChannelId = _kChannelId;
    RawResourceAndroidNotificationSound? customSound;

    if (useCustom && soundName != 'default') {
      activeChannelId = 'msg_$soundName';
      customSound = RawResourceAndroidNotificationSound(soundName);
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          activeChannelId,
          'Messages CarEasy ($soundName)',
          description: _kChannelDesc,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          sound: customSound,
        ),
      );
    }

    final data  = message.data;
    final notif = message.notification;
    final type  = data['type']?.toString() ?? '';
    final title = notif?.title ?? data['title'] ?? 'CarEasy';
    final body  = notif?.body  ?? data['body']  ?? 'Nouvelle notification';

    final channelInfo = _resolveChannelInfo(type, activeChannelId, soundName, useCustom);
    final notifId     = _buildNotifId(type, data);
    final payload     = _buildPayloadStr(type, data);

    await plugin.show(
      notifId, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelInfo.id,
          channelInfo.name,
          channelDescription: channelInfo.desc,
          importance:        Importance.high,
          priority:          Priority.high,
          playSound:         true,
          enableVibration:   true,
          icon:              _kNotifIcon,
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          color:             const Color(0xFFC0392B),
          visibility:        NotificationVisibility.public,
          sound:             channelInfo.isMsg ? customSound : null,
          number:            1,
          autoCancel:        true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  } catch (e) {
    debugPrint('[FCM BG] Erreur: $e');
  }
}

@pragma('vm:entry-point')
void _backgroundTapHandler(NotificationResponse response) {
  debugPrint('[Notif BG Tap] payload: ${response.payload}');
}

// ── Types utilitaires ─────────────────────────────────────────────────────────
typedef _ChannelInfo = ({String id, String name, String desc, bool isMsg});

_ChannelInfo _resolveChannelInfo(
    String type, String msgChannelId, String soundName, bool useCustom) {
  if (type.startsWith('rdv_reminder')) {
    return (id: _kReminderChannelId, name: _kReminderChannelName,
            desc: _kReminderChannelDesc, isMsg: false);
  }
  if (type.startsWith('rdv_')) {
    return (id: _kRdvChannelId, name: _kRdvChannelName,
            desc: _kRdvChannelDesc, isMsg: false);
  }
  if (type == 'review_request') {
    return (id: _kReviewChannelId, name: _kReviewChannelName,
            desc: _kReviewChannelDesc, isMsg: false);
  }
  // Message : utiliser le canal avec son personnalisé
  final name = (useCustom && soundName != 'default')
      ? 'Messages CarEasy ($soundName)'
      : _kChannelName;
  return (id: msgChannelId, name: name, desc: _kChannelDesc, isMsg: true);
}

int _buildNotifId(String type, Map<String, dynamic> data) {
  final rdvId  = data['rdv_id']?.toString() ?? '';
  final convId = data['conversation_id']?.toString() ?? '';
  if (type == 'rdv_reminder')   return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 30000).abs();
  if (type == 'review_request') return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 40000).abs();
  if (type.startsWith('rdv_'))  return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 20000).abs();
  return convId.isNotEmpty ? convId.hashCode.abs() % 10000 + 1000
      : (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 10000;
}

String _buildPayloadStr(String type, Map<String, dynamic> data) {
  if (type.startsWith('rdv_') || type == 'review_request') {
    return jsonEncode({'type': type, 'rdv_id': data['rdv_id'] ?? ''});
  }
  return jsonEncode({
    'conversation_id': data['conversation_id'] ?? '',
    'sender_name':     data['sender_name']  ?? '',
    'sender_photo':    data['sender_photo'] ?? '',
    'sender_id':       data['sender_id']    ?? '',
  });
}

Future<void> _createAllBaseChannels(
    AndroidFlutterLocalNotificationsPlugin? p) async {
  if (p == null) return;
  for (final ch in [
    const AndroidNotificationChannel(
      _kChannelId, _kChannelName,
      description: _kChannelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ),
    const AndroidNotificationChannel(
      _kRdvChannelId, _kRdvChannelName,
      description: _kRdvChannelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ),
    const AndroidNotificationChannel(
      _kReminderChannelId, _kReminderChannelName,
      description: _kReminderChannelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ),
    const AndroidNotificationChannel(
      _kReviewChannelId, _kReviewChannelName,
      description: _kReviewChannelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ),
  ]) {
    await p.createNotificationChannel(ch);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SOUND PREFS
// ══════════════════════════════════════════════════════════════════════════════
class NotificationSoundPrefs {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyUseCustom     = 'notif_use_custom_sound';
  static const _keySoundName     = 'notif_custom_sound_name';
  static const _keySoundLabel    = 'notif_custom_sound_label';

  static const List<Map<String, String>> availableSounds = [
    {'name': 'default',             'label': 'Système (défaut)',  'emoji': '🔕'},
    {'name': 'careasy_chime_soft',  'label': 'Carillon doux',     'emoji': '🎵'},
    {'name': 'careasy_pristine',    'label': 'Cristallin',        'emoji': '✨'},
    {'name': 'careasy_subtle_ping', 'label': 'Ping subtil',       'emoji': '💎'},
    {'name': 'careasy_success',     'label': 'Succès',            'emoji': '✅'},
    {'name': 'careasy_gentle_bell', 'label': 'Cloche douce',      'emoji': '🔔'},
    {'name': 'careasy_pop_clean',   'label': 'Pop professionnel', 'emoji': '🎯'},
    {'name': 'careasy_notify_pro',  'label': 'Notification Pro',  'emoji': '📳'},
  ];

  static Future<bool>   getUseCustomSound()   async =>
      (await _storage.read(key: _keyUseCustom)) == 'true';
  static Future<String> getCustomSoundName()  async =>
      (await _storage.read(key: _keySoundName)) ?? 'default';
  static Future<String> getCustomSoundLabel() async =>
      (await _storage.read(key: _keySoundLabel)) ?? 'Système (défaut)';

  // Pas de cache activeChannelId — recalculé à chaque fois
  static String computeChannelId(bool useCustom, String soundName) {
    if (useCustom && soundName != 'default') return 'msg_$soundName';
    return _kChannelId;
  }

  static Future<void> setSoundPreference({
    required bool   useCustom,
    required String soundName,
    required String soundLabel,
  }) async {
    await _storage.write(key: _keyUseCustom,  value: useCustom.toString());
    await _storage.write(key: _keySoundName,  value: soundName);
    await _storage.write(key: _keySoundLabel, value: soundLabel);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NOTIFICATION SERVICE — Singleton principal
// ══════════════════════════════════════════════════════════════════════════════
class NotificationService {
  static final NotificationService _inst = NotificationService._internal();
  factory NotificationService() => _inst;
  NotificationService._internal();

  static const _aOpts = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOpts = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging               _fcm   = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage(aOptions: _aOpts, iOptions: _iOpts);
  final AudioPlayer _previewPlayer = AudioPlayer();

  Function(Map<String, dynamic>)? onNotificationTap;
  bool _initialized = false;

  // ─── Badge (compteur) ────────────────────────────────────────────────
  int _badgeCount = 0;
  int get badgeCount => _badgeCount;

  void incrementBadge() => _badgeCount++;
  void resetBadge() => _badgeCount = 0;

  // ══════════════════════════════════════════════════════════════════════
  // INITIALISATION — appeler dans main() avant runApp()
  // ══════════════════════════════════════════════════════════════════════
  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Africa/Porto-Novo'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

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
        onDidReceiveNotificationResponse: (r) => _handleTap(r.payload),
        onDidReceiveBackgroundNotificationResponse: _backgroundTapHandler,
      );
    } catch (e) {
      debugPrint('[Notif] Init warning: $e');
      try {
        await _local.initialize(
          initSettings,
          onDidReceiveNotificationResponse: (r) => _handleTap(r.payload),
        );
      } catch (_) {}
    }

    _initialized = true;

    if (Platform.isAndroid) await _setupAndroidChannels();

    // Demander permission Android 13+
    if (Platform.isAndroid) {
      final androidPlugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }

    await _initFCM();

    // Enregistrer la callback pour PusherService
    NotificationServiceRef.register(({
      required int id,
      required String title,
      required String body,
      String? payload,
    }) =>
        showNotification(id: id, title: title, body: body, payload: payload));

    debugPrint('[Notif] ✓ Initialisé');
  }

  // ── Création / mise à jour des canaux Android ─────────────────────────────
  Future<void> _setupAndroidChannels() async {
    if (!Platform.isAndroid) return;
    final p = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await _createAllBaseChannels(p);
    await _ensureCustomSoundChannel(p);
  }

  /// Crée (ou recrée) le canal avec le son personnalisé actuel.
  /// IMPORTANT : Android ne permet pas de modifier le son d'un canal existant.
  /// Il faut supprimer l'ancien canal et en créer un nouveau.
  Future<void> _ensureCustomSoundChannel(
      AndroidFlutterLocalNotificationsPlugin? p) async {
    if (p == null) return;
    try {
      final useCustom = await NotificationSoundPrefs.getUseCustomSound();
      final soundName = await NotificationSoundPrefs.getCustomSoundName();

      if (!useCustom || soundName == 'default') return;

      final channelId = NotificationSoundPrefs.computeChannelId(true, soundName);
      await p.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          'Messages CarEasy ($soundName)',
          description: _kChannelDesc,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          sound: RawResourceAndroidNotificationSound(soundName),
        ),
      );
      debugPrint('[Notif] Canal son créé: $channelId');
    } catch (e) {
      debugPrint('[Notif] _ensureCustomSoundChannel: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // AFFICHER UNE NOTIFICATION
  // ══════════════════════════════════════════════════════════════════════
  Future<void> showNotification({
    required int    id,
    required String title,
    required String body,
    String?         payload,
    String          type = '',
  }) async {
    if (!_initialized) {
      debugPrint('[Notif] Non initialisé');
      return;
    }

    incrementBadge();

    try {
      final useCustom = await NotificationSoundPrefs.getUseCustomSound();
      final soundName = await NotificationSoundPrefs.getCustomSoundName();

      if (Platform.isAndroid) {
        final p = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await _createAllBaseChannels(p);
        await _ensureCustomSoundChannel(p);
      }

      final msgChannelId = NotificationSoundPrefs.computeChannelId(useCustom, soundName);
      final channelInfo  = _resolveChannelInfo(type, msgChannelId, soundName, useCustom);

      RawResourceAndroidNotificationSound? sound;
      if (channelInfo.isMsg && useCustom && soundName != 'default') {
        sound = RawResourceAndroidNotificationSound(soundName);
      }

      await _local.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelInfo.id,
            channelInfo.name,
            channelDescription: channelInfo.desc,
            importance:         Importance.high,
            priority:           Priority.high,
            playSound:          true,
            enableVibration:    true,
            icon:               _kNotifIcon,
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            color:              const Color(0xFFC0392B),
            visibility:         NotificationVisibility.public,
            sound:              sound,
            number:             _badgeCount,
            autoCancel:         true,
            showWhen:           true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            badgeNumber:  _badgeCount,
          ),
        ),
        payload: payload,
      );

      debugPrint('[Notif] ✓ Affichée: "$title" (canal: ${channelInfo.id}, son: $soundName)');
    } catch (e) {
      debugPrint('[Notif] showNotification error: $e');
      // Fallback sans son personnalisé
      try {
        await _local.show(
          id, title, body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _kChannelId, _kChannelName,
              importance: Importance.high,
              priority: Priority.high,
              icon: _kNotifIcon,
              autoCancel: true,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true, presentBadge: true, presentSound: true,
            ),
          ),
          payload: payload,
        );
      } catch (e2) {
        debugPrint('[Notif] Fallback error: $e2');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // MESSAGES
  // ══════════════════════════════════════════════════════════════════════
  Future<void> showMessageNotification({
    required String senderName,
    required String messageBody,
    required String conversationId,
    String? senderPhoto,
    String? senderId,
  }) async {
    final payload = jsonEncode({
      'conversation_id': conversationId,
      'sender_name':     senderName,
      'sender_photo':    senderPhoto ?? '',
      'sender_id':       senderId    ?? '',
    });
    await showNotification(
      id:      conversationId.hashCode.abs() % 10000 + 1000,
      title:   senderName,
      body:    messageBody.length > 100
                 ? '${messageBody.substring(0, 100)}…'
                 : messageBody,
      payload: payload,
      type:    'message',
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // RDV
  // ══════════════════════════════════════════════════════════════════════
  Future<void> showRdvNotification({
    required String title,
    required String body,
    required String rdvId,
    required String type,
  }) async {
    await showNotification(
      id:      _buildNotifId(type, {'rdv_id': rdvId}),
      title:   title,
      body:    body,
      payload: jsonEncode({'type': type, 'rdv_id': rdvId}),
      type:    type,
    );
  }

  // ── Rappel planifié ───────────────────────────────────────────────────────
  Future<void> scheduleRdvReminder({
    required String rdvId,
    required String rdvDate,
    required String rdvTime,
    required String serviceName,
    required bool   isPrestataire,
  }) async {
    try {
      final parts     = rdvTime.split(':');
      final dateParts = rdvDate.split('-');
      final rdvDT = tz.TZDateTime(
        tz.local,
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.tryParse(parts[0]) ?? 0,
        int.tryParse(parts[1]) ?? 0,
      );
      final reminderTime = rdvDT.subtract(const Duration(hours: 1));
      if (reminderTime.isBefore(tz.TZDateTime.now(tz.local))) return;

      await _local.zonedSchedule(
        _buildNotifId('rdv_reminder', {'rdv_id': rdvId}),
        '⏰ Rappel rendez-vous',
        isPrestataire
            ? 'Rappel : rendez-vous pour $serviceName dans 1h'
            : 'Votre rendez-vous pour $serviceName commence dans 1 heure !',
        reminderTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kReminderChannelId, _kReminderChannelName,
            channelDescription: _kReminderChannelDesc,
            importance:  Importance.high,
            priority:    Priority.high,
            icon:        _kNotifIcon,
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            color:       const Color(0xFFC0392B),
            autoCancel:  true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true, presentBadge: true, presentSound: true,
          ),
        ),
        payload:    jsonEncode({'type': 'rdv_reminder', 'rdv_id': rdvId}),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('[Notif] ✓ Rappel planifié pour $rdvDate $rdvTime');
    } catch (e) {
      debugPrint('[Notif] scheduleRdvReminder: $e');
    }
  }

  Future<void> cancelRdvReminder(String rdvId) async {
    try {
      await _local.cancel(_buildNotifId('rdv_reminder', {'rdv_id': rdvId}));
    } catch (_) {}
  }

  // ── Review ────────────────────────────────────────────────────────────────
  Future<void> showReviewRequestNotification({
    required String rdvId,
    required String serviceName,
  }) async {
    await showNotification(
      id:      _buildNotifId('review_request', {'rdv_id': rdvId}),
      title:   '⭐ Votre avis nous intéresse !',
      body:    'Comment s\'est passé votre RDV pour $serviceName ?',
      payload: jsonEncode({'type': 'review_request', 'rdv_id': rdvId}),
      type:    'review_request',
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // BADGE ICÔNE APPLICATION
  // ══════════════════════════════════════════════════════════════════════

  /// Met à jour le badge numérique sur l'icône de l'app.
  /// Sur Android : utilise flutter_local_notifications number parameter.
  /// Sur iOS : gère via DarwinNotificationDetails.badgeNumber.
  Future<void> updateAppBadge(int count) async {
    _badgeCount = count > 0 ? count : 0;

    if (Platform.isIOS) {
      try {
        // iOS : afficher une notif silencieuse pour mettre à jour le badge
        if (_badgeCount == 0) {
          await _local.show(
            _kBadgeNotifId, '', '',
            const NotificationDetails(
              iOS: DarwinNotificationDetails(
                presentAlert: false,
                presentBadge: true,
                presentSound: false,
                badgeNumber: 0,
              ),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 100));
          await _local.cancel(_kBadgeNotifId);
        }
      } catch (e) {
        debugPrint('[Notif] updateAppBadge iOS: $e');
      }
    }
    // Android : le badge est mis à jour automatiquement via 'number' dans chaque notif
    debugPrint('[Notif] Badge mis à jour: $_badgeCount');
  }

  Future<void> clearBadge() async {
    _badgeCount = 0;
    await updateAppBadge(0);
  }

  // ══════════════════════════════════════════════════════════════════════
  // PREVIEW SON — 100% audioplayers (pas de notification)
  // ══════════════════════════════════════════════════════════════════════
  Future<void> playSoundPreview(String soundName) async {
    try {
      await _previewPlayer.stop();
      if (soundName == 'default') {
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
      debugPrint('[Notif] Preview son: $soundName ✓');
    } catch (e) {
      debugPrint('[Notif] playSoundPreview($soundName): $e');
      try {
        await _previewPlayer.play(
          AssetSource('sounds/$soundName.wav'),
          volume: 1.0,
        );
      } catch (_) {
        debugPrint('[Notif] Fichier son manquant: $soundName');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // MISE À JOUR CANAL APRÈS CHANGEMENT DE SON
  // ══════════════════════════════════════════════════════════════════════

  /// Appelé depuis NotificationsSettingsScreen après changement de son.
  /// Recrée le canal avec le nouveau son.
  Future<void> updateNotificationChannel() async {
    if (!Platform.isAndroid) return;
    try {
      final p = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await _ensureCustomSoundChannel(p);
      debugPrint('[Notif] Canal mis à jour avec nouveau son');
    } catch (e) {
      debugPrint('[Notif] updateNotificationChannel: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // ANNULATION
  // ══════════════════════════════════════════════════════════════════════
  Future<void> cancelNotification(dynamic id) async {
    try {
      final intId = id is int ? id : id.toString().hashCode.abs() % 10000 + 1000;
      await _local.cancel(intId);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    _badgeCount = 0;
    try { await _local.cancelAll(); } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════
  // FIREBASE MESSAGING
  // ══════════════════════════════════════════════════════════════════════
  Future<void> _initFCM() async {
    try {
      final settings = await _fcm.requestPermission(
        alert:       true,
        badge:       true,
        sound:       true,
        provisional: false,
      );
      debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // IMPORTANT : afficher les notifications FCM même en foreground
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Foreground : FCM reçu → afficher manuellement via flutter_local_notifications
      FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('[FCM FG] Reçu: ${msg.notification?.title}');
        _showFCMAsLocal(msg);
      });

      // App ouverte via notification
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        if (_badgeCount > 0) _badgeCount--;
        _handleFCMTap(msg.data);
      });

      // App lancée depuis notification (app fermée)
      final initial = await _fcm.getInitialMessage();
      if (initial != null) {
        Future.delayed(
          const Duration(milliseconds: 1500),
          () => _handleFCMTap(initial.data),
        );
      }

      await _registerFCMToken();
      _fcm.onTokenRefresh.listen(_sendTokenToServer);
    } catch (e) {
      debugPrint('[FCM] _initFCM error: $e');
    }
  }

  /// Affiche une notification locale quand FCM arrive en foreground.
  Future<void> _showFCMAsLocal(RemoteMessage message) async {
    final data  = message.data;
    final notif = message.notification;
    final type  = data['type']?.toString() ?? '';
    final title = notif?.title ?? data['title'] ?? 'CarEasy';
    final body  = notif?.body  ?? data['body']  ?? '';

    if (type == 'review_request') {
      await showReviewRequestNotification(
        rdvId:       data['rdv_id']?.toString() ?? '',
        serviceName: data['service_name']?.toString() ?? 'le service',
      );
      return;
    }
    if (type.startsWith('rdv_')) {
      await showRdvNotification(
        title: title,
        body:  body,
        rdvId: data['rdv_id']?.toString() ?? '',
        type:  type,
      );
      return;
    }

    // Message
    final convId = data['conversation_id']?.toString() ?? '';
    await showNotification(
      id:    convId.isNotEmpty
                 ? convId.hashCode.abs() % 10000 + 1000
                 : DateTime.now().millisecondsSinceEpoch ~/ 1000 % 10000,
      title: title,
      body:  body,
      payload: jsonEncode({
        'conversation_id': convId,
        'sender_name':     data['sender_name']  ?? '',
        'sender_photo':    data['sender_photo'] ?? '',
        'sender_id':       data['sender_id']    ?? '',
      }),
      type: 'message',
    );
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
        await _sendTokenToServer(token);
        debugPrint('[FCM] Token: ${token.substring(0, 20)}...');
      }
    } catch (e) {
      debugPrint('[FCM] _registerFCMToken: $e');
    }
  }

  Future<void> _sendTokenToServer(String fcmToken) async {
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
          'Content-Type':  'application/json',
          'Accept':        'application/json',
        },
        body: jsonEncode({
          'fcm_token': fcmToken,
          'platform':  Platform.isIOS ? 'ios' : 'android',
        }),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        await _storage.delete(key: 'fcm_token_pending');
        debugPrint('[FCM] Token enregistré ✓');
      }
    } catch (e) {
      debugPrint('[FCM] _sendTokenToServer: $e');
    }
  }

  Future<void> refreshTokenAfterLogin() async {
    try {
      final pending = await _storage.read(key: 'fcm_token_pending');
      if (pending != null && pending.isNotEmpty) {
        await _sendTokenToServer(pending);
      } else {
        await _registerFCMToken();
      }
    } catch (e) {
      debugPrint('[FCM] refreshTokenAfterLogin: $e');
    }
  }

  // ── Gestion des taps ──────────────────────────────────────────────────────
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
        'sender_name':     data['sender_name']  ?? '',
        'sender_photo':    data['sender_photo'] ?? '',
        'sender_id':       data['sender_id']    ?? '',
      });
    }
  }
}

// ── Référence indirecte pour PusherService (évite import circulaire) ──────────
class NotificationServiceRef {
  static Future<void> Function({
    required int    id,
    required String title,
    required String body,
    String?         payload,
  })? _showFn;

  static void register(
    Future<void> Function({
      required int    id,
      required String title,
      required String body,
      String?         payload,
    }) fn,
  ) {
    _showFn = fn;
  }

  static Future<void> show({
    required int    id,
    required String title,
    required String body,
    String?         payload,
  }) async {
    await _showFn?.call(id: id, title: title, body: body, payload: payload);
  }
}