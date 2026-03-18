// lib/services/notification_service.dart
// ═══════════════════════════════════════════════════════════════════════
// CORRECTION DÉFINITIVE — Son de notification personnalisable
//
// POURQUOI LE SON NE CHANGEAIT PAS:
//  - Le fichier contenait DEUX classes NotificationService en double.
//    Dart utilise la PREMIÈRE déclaration → la deuxième (avec multi-canaux)
//    était ignorée.
//  - La première classe utilisait toujours 'high_importance_channel'
//    (canal unique). Android interdit de changer le son d'un canal existant
//    après sa création → le son restait figé sur le défaut.
//
// SOLUTION: Un canal Android PAR son (Android exige cela depuis API 26).
//  careasy_messages_default          → son système
//  careasy_messages_notification_bell → cloche
//  careasy_messages_chime             → carillon
//  careasy_messages_ding              → ding
//  careasy_messages_message_pop       → pop message
//
// Tous les canaux sont créés au démarrage. showNotification() lit le son
// choisi dans SharedPreferences et utilise le canal correspondant.
// ═══════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz_data;
import '../utils/constants.dart';

// ═══════════════════════════════════════════════════════════════════════
// Préférences de son — uniquement SharedPreferences (pas de serveur)
// ═══════════════════════════════════════════════════════════════════════
class NotificationSoundPrefs {
  static const _keyUseCustom  = 'notif_use_custom_sound';
  static const _keySoundName  = 'notif_sound_name';
  static const _keySoundLabel = 'notif_sound_label';

  /// Sons disponibles.
  /// 'name' = nom du fichier SANS extension dans:
  ///   Android → android/app/src/main/res/raw/
  ///   iOS     → Runner/ (en .aiff ou .caf)
  ///   Assets  → assets/sounds/ (pour l'aperçu just_audio)
  static const List<Map<String, String>> availableSounds = [
    {'name': 'default',           'label': 'Système (défaut)'},
    {'name': 'notification_bell', 'label': 'Cloche'},
    {'name': 'chime',             'label': 'Carillon'},
    {'name': 'ding',              'label': 'Ding'},
    {'name': 'message_pop',       'label': 'Pop message'},
  ];

  static Future<bool>   getUseCustomSound()  async =>
      (await SharedPreferences.getInstance()).getBool(_keyUseCustom) ?? false;

  static Future<String> getCustomSoundName() async =>
      (await SharedPreferences.getInstance()).getString(_keySoundName) ?? 'default';

  static Future<String> getCustomSoundLabel() async =>
      (await SharedPreferences.getInstance()).getString(_keySoundLabel) ?? 'Système (défaut)';

  static Future<void> setSoundPreference({
    required bool   useCustom,
    required String soundName,
    required String soundLabel,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyUseCustom,   useCustom);
    await p.setString(_keySoundName,  soundName);
    await p.setString(_keySoundLabel, soundLabel);
    debugPrint('[SoundPrefs] ✅ Son sauvegardé: $soundName (custom=$useCustom)');
  }

  /// Chaque son a son propre canal Android — obligatoire pour changer le son.
  static String channelIdFor(String soundName) =>
      soundName == 'default' ? 'careasy_msg_default' : 'careasy_msg_$soundName';

  static String channelNameFor(String soundName) {
    final e = availableSounds.firstWhere(
      (s) => s['name'] == soundName,
      orElse: () => {'name': soundName, 'label': soundName},
    );
    return 'Messages — ${e['label']}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Handler FCM Background — top-level, PAS de singleton, PAS de SharedPrefs
// ═══════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM BG] id=${message.messageId}');
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));

    // Canal de secours (background ne peut pas lire SharedPrefs facilement)
    const fallbackChannelId = 'careasy_msg_notification_bell';
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          fallbackChannelId, 'Messages — Cloche',
          description: 'Notifications CarEasy',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          sound: RawResourceAndroidNotificationSound('notification_bell'),
        ));

    final notif  = message.notification;
    final data   = message.data;
    final title  = notif?.title ?? data['title'] ?? 'Nouveau message';
    final body   = notif?.body  ?? data['body']  ?? '';
    final convId = data['conversation_id']?.toString();

    final payload = jsonEncode({
      'conversation_id': convId ?? '',
      'sender_name':     data['sender_name']  ?? '',
      'sender_photo':    data['sender_photo'] ?? '',
      'sender_id':       data['sender_id']    ?? '',
    });

    await plugin.show(
      convId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          fallbackChannelId, 'Messages — Cloche',
          channelDescription: 'Notifications CarEasy',
          importance: Importance.high, priority: Priority.high,
          enableVibration: true, playSound: true,
          sound: RawResourceAndroidNotificationSound('notification_bell'),
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          sound: 'notification_bell.aiff',
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: payload,
    );
  } catch (e) {
    debugPrint('[FCM BG] Erreur: $e');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NotificationService — singleton principal
// ═══════════════════════════════════════════════════════════════════════
class NotificationService {
  static final NotificationService _inst = NotificationService._internal();
  factory NotificationService() => _inst;
  NotificationService._internal();

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );

  /// Callback appelé quand l'utilisateur tape sur une notification.
  /// Reçoit un Map avec: conversation_id, sender_name, sender_photo, sender_id
  Function(Map<String, dynamic> data)? onNotificationTap;

  bool _initialized = false;

  // ─── Initialisation ────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    tz_data.initializeTimeZones();

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse:           (d) => _handleTap(d.payload),
      onDidReceiveBackgroundNotificationResponse: _bgTapCallback,
    );

    // ⭐ Créer TOUS les canaux dès le démarrage
    await _createAllChannels();
    await _initFCM();
  }

  // ─── Crée un canal Android pour chaque son disponible ──────────────────────
  // Android interdit de changer le son d'un canal existant.
  // La seule solution est d'utiliser un canal différent par son.
  Future<void> _createAllChannels() async {
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return; // iOS ou Web — pas de canaux

    for (final sound in NotificationSoundPrefs.availableSounds) {
      final sName     = sound['name']!;
      final channelId = NotificationSoundPrefs.channelIdFor(sName);
      final chanName  = NotificationSoundPrefs.channelNameFor(sName);

      // Son Android: null = son défaut du système
      AndroidNotificationSound? androidSound;
      if (sName != 'default') {
        androidSound = RawResourceAndroidNotificationSound(sName);
      }

      await androidPlugin.createNotificationChannel(AndroidNotificationChannel(
        channelId, chanName,
        description: 'Notifications CarEasy — $chanName',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        sound: androidSound,
      ));
      debugPrint('[Canaux] ✅ $channelId créé');
    }
  }

  // ─── Appelé par notifications_settings_screen après changement de son ───────
  // Rien à faire : tous les canaux sont déjà créés dans _createAllChannels().
  // showNotification() lit le canal depuis SharedPrefs à chaque appel.
  Future<void> updateNotificationChannel() async {
    final soundName = await NotificationSoundPrefs.getCustomSoundName();
    debugPrint('[Canaux] Canal actif: ${NotificationSoundPrefs.channelIdFor(soundName)}');
    // Re-créer les canaux si l'app vient d'être installée ou mise à jour
    await _createAllChannels();
  }

  // ─── Aperçu sonore via just_audio (assets) ──────────────────────────────────
  Future<void> playSoundPreview(String soundName) async {
    if (soundName == 'default') return;
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setAsset('assets/sounds/$soundName.mp3');
      await player.play();
      // Attendre la fin de la lecture
      await player.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[SoundPreview] Erreur $soundName: $e');
    } finally {
      await player?.dispose();
    }
  }

  // ─── Affichage d'une notification locale ────────────────────────────────────
  Future<void> showNotification({
    required int    id,
    required String title,
    required String body,
    String?         payload,
  }) async {
    // ⭐ Lire le son CHOISI par l'utilisateur à chaque notification
    final soundName = await NotificationSoundPrefs.getCustomSoundName();
    final useCustom = await NotificationSoundPrefs.getUseCustomSound();
    final channelId = NotificationSoundPrefs.channelIdFor(soundName);
    final chanName  = NotificationSoundPrefs.channelNameFor(soundName);

    // Son Android: null = utilise le son défini dans le canal (défaut système)
    AndroidNotificationSound? androidSound;
    if (useCustom && soundName != 'default' && soundName.isNotEmpty) {
      androidSound = RawResourceAndroidNotificationSound(soundName);
    }

    // Son iOS: 'default' = son système, sinon nom du fichier .aiff
    final iosSound = (useCustom && soundName != 'default')
        ? '$soundName.aiff'
        : 'default';

    debugPrint('[Notif] → canal=$channelId son=${androidSound == null ? "défaut" : soundName}');

    await _local.show(
      id, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId, chanName,
          channelDescription: 'Notifications CarEasy',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          sound: androidSound,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: DarwinNotificationDetails(
          sound: iosSound,
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ─── Wrappers ───────────────────────────────────────────────────────────────
  Future<void> showFCMNotification(RemoteMessage message) async {
    final notif  = message.notification;
    final data   = message.data;
    final convId = data['conversation_id']?.toString();

    await showNotification(
      id:    convId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: notif?.title ?? data['title'] ?? 'Nouveau message',
      body:  notif?.body  ?? data['body']  ?? '',
      payload: jsonEncode({
        'conversation_id': convId ?? '',
        'sender_name':     data['sender_name']  ?? '',
        'sender_photo':    data['sender_photo'] ?? '',
        'sender_id':       data['sender_id']    ?? '',
      }),
    );
  }

  Future<void> showMessageNotification({
    required String senderName,
    required String messageBody,
    required String conversationId,
    String? senderPhoto,
    String? senderId,
  }) async {
    await showNotification(
      id:    conversationId.hashCode,
      title: senderName,
      body:  messageBody,
      payload: jsonEncode({
        'conversation_id': conversationId,
        'sender_name':     senderName,
        'sender_photo':    senderPhoto ?? '',
        'sender_id':       senderId    ?? '',
      }),
    );
  }

  Future<void> cancelNotification(String conversationId) async =>
      _local.cancel(conversationId.hashCode);

  Future<void> cancelAll() async => _local.cancelAll();

  // ─── FCM ────────────────────────────────────────────────────────────────────
  Future<void> _initFCM() async {
    final settings = await _fcm.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // Message reçu en foreground (app ouverte)
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[FCM FG] ${msg.notification?.title}');
      showFCMNotification(msg);
    });

    // Tap sur notification (app en arrière-plan)
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] onMessageOpenedApp: ${msg.data}');
      _handleFCMTap(msg.data);
    });

    // App lancée depuis une notification (fermée)
    final init = await _fcm.getInitialMessage();
    if (init != null) {
      debugPrint('[FCM] initialMessage: ${init.data}');
      Future.delayed(
        const Duration(milliseconds: 1500),
        () => _handleFCMTap(init.data),
      );
    }

    await _registerToken();
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  Future<void> _registerToken() async {
    try {
      String? token;
      if (Platform.isIOS) {
        final apns = await _fcm.getAPNSToken();
        if (apns != null) token = await _fcm.getToken();
      } else {
        token = await _fcm.getToken();
      }
      if (token != null) {
        debugPrint('[FCM] Token: ${token.substring(0, 20)}…');
        await _storage.write(key: 'fcm_token_pending', value: token);
        await _sendTokenToBackend(token);
      }
    } catch (e) { debugPrint('[FCM] Erreur token: $e'); }
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
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'fcm_token': fcmToken,
          'platform': Platform.isIOS ? 'ios' : 'android',
        }),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        debugPrint('[FCM] Token enregistré ✓');
        await _storage.delete(key: 'fcm_token_pending');
      } else {
        debugPrint('[FCM] Erreur enregistrement: ${resp.statusCode}');
      }
    } catch (e) { debugPrint('[FCM] Erreur envoi token: $e'); }
  }

  Future<void> refreshTokenAfterLogin() async {
    try {
      final pending = await _storage.read(key: 'fcm_token_pending');
      if (pending != null && pending.isNotEmpty) {
        await _sendTokenToBackend(pending);
      } else {
        await _registerToken();
      }
    } catch (e) { debugPrint('[FCM] refreshTokenAfterLogin: $e'); }
  }

  // ─── Gestion du tap ─────────────────────────────────────────────────────────
  void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      debugPrint('[Notif] Tap: $data');
      onNotificationTap?.call(data);
    } catch (_) {
      // Ancien format (juste un string conversation_id)
      onNotificationTap?.call({'conversation_id': payload});
    }
  }

  void _handleFCMTap(Map<String, dynamic> data) {
    debugPrint('[FCM] Tap: $data');
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

// ─── Callback background tap — obligatoirement top-level ────────────────────
@pragma('vm:entry-point')
void _bgTapCallback(NotificationResponse d) {
  debugPrint('[Notif BG Tap] payload=${d.payload}');
}