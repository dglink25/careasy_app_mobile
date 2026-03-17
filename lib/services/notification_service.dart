// lib/services/notification_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VERSION FINALE — Sons personnalisables + navigation directe vers chat
// FONCTIONNALITÉS:
// 1. Son par défaut système OU son personnalisé (fichier local)
// 2. Navigation directe vers ChatScreen au clic sur notification
// 3. Récupération correcte des infos conversation pour ouvrir le chat
// 4. Background handler sans FlutterSecureStorage
// 5. Token FCM envoyé automatiquement après login
// ═══════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import '../utils/constants.dart';

// ─── Clés de préférences pour les sons ──────────────────────────────
class NotificationSoundPrefs {
  static const String _keyUseCustomSound   = 'notif_use_custom_sound';
  static const String _keyCustomSoundName  = 'notif_custom_sound_name';
  static const String _keyCustomSoundLabel = 'notif_custom_sound_label';

  // Sons prédéfinis disponibles dans les assets Android res/raw/
  static const List<Map<String, String>> availableSounds = [
    {'name': 'default',           'label': 'Système (défaut)',   'asset': ''},
    {'name': 'notification_bell', 'label': 'Cloche',             'asset': 'notification_bell'},
    {'name': 'message_pop',       'label': 'Pop message',        'asset': 'message_pop'},
    {'name': 'chime',             'label': 'Carillon',           'asset': 'chime'},
    {'name': 'ding',              'label': 'Ding',               'asset': 'ding'},
  ];

  static Future<bool> getUseCustomSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseCustomSound) ?? false;
  }

  static Future<String> getCustomSoundName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomSoundName) ?? 'default';
  }

  static Future<String> getCustomSoundLabel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomSoundLabel) ?? 'Système (défaut)';
  }

  static Future<void> setSoundPreference({
    required bool useCustom,
    required String soundName,
    required String soundLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseCustomSound, useCustom);
    await prefs.setString(_keyCustomSoundName, soundName);
    await prefs.setString(_keyCustomSoundLabel, soundLabel);
  }
}

// ─── Handler FCM BACKGROUND — OBLIGATOIREMENT top-level ─────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM BG] id=${message.messageId}');
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));

    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'high_importance_channel', 'Messages',
          description: 'Notifications de nouveaux messages',
          importance: Importance.high, playSound: true, enableVibration: true,
        ));

    final notif  = message.notification;
    final data   = message.data;
    final title  = notif?.title ?? data['title'] ?? 'Nouveau message';
    final body   = notif?.body  ?? data['body']  ?? '';
    final convId = data['conversation_id']?.toString();
    final payload = convId != null ? jsonEncode({
      'conversation_id': convId,
      'sender_name': data['sender_name'] ?? '',
      'sender_photo': data['sender_photo'] ?? '',
    }) : null;

    await plugin.show(
      convId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel', 'Messages',
          channelDescription: 'Notifications de nouveaux messages',
          importance: Importance.high, priority: Priority.high,
          enableVibration: true, playSound: true, icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          sound: 'default', presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: payload,
    );
  } catch (e) {
    debugPrint('[FCM BG] Erreur: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────
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

  /// Callback appelé quand l'utilisateur tape sur une notification
  /// Reçoit conversation_id, sender_name, sender_photo
  Function(Map<String, dynamic> data)? onNotificationTap;
  
  bool _initialized = false;

  // ── Initialisation ───────────────────────────────────────────────
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
      onDidReceiveNotificationResponse: (d) => _handleTap(d.payload),
      onDidReceiveBackgroundNotificationResponse: _bgTapCallback,
    );

    // Créer le canal avec le son actuellement configuré
    await _createNotificationChannel();
    await _initFCM();
  }

  // ── Création du canal Android avec son personnalisé ──────────────
  Future<void> _createNotificationChannel() async {
    final useCustom  = await NotificationSoundPrefs.getUseCustomSound();
    final soundName  = await NotificationSoundPrefs.getCustomSoundName();

    AndroidNotificationSound? sound;
    if (useCustom && soundName != 'default' && soundName.isNotEmpty) {
      sound = RawResourceAndroidNotificationSound(soundName);
    }

    final channel = AndroidNotificationChannel(
      'high_importance_channel',
      'Messages',
      description: 'Notifications de nouveaux messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      sound: sound,
    );

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    
    debugPrint('[NotifService] Canal créé avec son: ${sound == null ? "défaut" : soundName}');
  }

  /// Recréer le canal après changement de son (Android recréé uniquement si différent)
  Future<void> updateNotificationChannel() async {
    // Supprimer l'ancien canal et recréer avec les nouvelles préférences
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.deleteNotificationChannel('high_importance_channel');
    await _createNotificationChannel();
  }

  // ── FCM ──────────────────────────────────────────────────────────
  Future<void> _initFCM() async {
    final settings = await _fcm.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // Message reçu en foreground
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[FCM FG] ${msg.notification?.title}');
      showFCMNotification(msg);
    });

    // App ouverte depuis arrière-plan (tap sur notif)
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] onMessageOpenedApp: ${msg.data}');
      _handleFCMTap(msg.data);
    });

    // App lancée depuis notification fermée
    final init = await _fcm.getInitialMessage();
    if (init != null) {
      debugPrint('[FCM] initialMessage: ${init.data}');
      Future.delayed(const Duration(milliseconds: 1500), () => _handleFCMTap(init.data));
    }

    await _registerToken();
    _fcm.onTokenRefresh.listen((t) => _sendTokenToBackend(t));
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
        debugPrint('[FCM] Token obtenu: ${token.substring(0, 20)}…');
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
        debugPrint('[FCM] Erreur enregistrement token: ${resp.statusCode}');
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

  // ── Affichage des notifications ──────────────────────────────────
  Future<void> showFCMNotification(RemoteMessage message) async {
    final notif  = message.notification;
    final data   = message.data;
    final title  = notif?.title ?? data['title'] ?? 'Nouveau message';
    final body   = notif?.body  ?? data['body']  ?? '';
    final convId = data['conversation_id']?.toString();
    
    final payload = jsonEncode({
      'conversation_id': convId ?? '',
      'sender_name':     data['sender_name'] ?? '',
      'sender_photo':    data['sender_photo'] ?? '',
      'sender_id':       data['sender_id'] ?? '',
    });

    await showNotification(
      id:      convId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title:   title,
      body:    body,
      payload: payload,
    );
  }

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
      'sender_id':       senderId ?? '',
    });
    await showNotification(
      id:      conversationId.hashCode,
      title:   senderName,
      body:    messageBody,
      payload: payload,
    );
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final useCustom = await NotificationSoundPrefs.getUseCustomSound();
    final soundName = await NotificationSoundPrefs.getCustomSoundName();

    AndroidNotificationSound? sound;
    if (useCustom && soundName != 'default' && soundName.isNotEmpty) {
      sound = RawResourceAndroidNotificationSound(soundName);
    }

    await _local.show(
      id, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'Messages',
          channelDescription: 'Notifications de nouveaux messages',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          sound: sound,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          sound: 'default',
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ── Gestion du tap sur notification ─────────────────────────────
  void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      debugPrint('[NotifService] Tap sur notification: $data');
      onNotificationTap?.call(data);
    } catch (e) {
      debugPrint('[NotifService] Erreur parsing payload: $e — payload=$payload');
      // Essayer l'ancien format (juste conversation_id en string)
      onNotificationTap?.call({'conversation_id': payload});
    }
  }

  void _handleFCMTap(Map<String, dynamic> data) {
    debugPrint('[NotifService] FCM tap: $data');
    final convId = data['conversation_id']?.toString();
    if (convId != null && convId.isNotEmpty) {
      onNotificationTap?.call({
        'conversation_id': convId,
        'sender_name':     data['sender_name'] ?? '',
        'sender_photo':    data['sender_photo'] ?? '',
        'sender_id':       data['sender_id'] ?? '',
      });
    }
  }

  /// Annuler une notification spécifique
  Future<void> cancelNotification(String conversationId) async {
    await _local.cancel(conversationId.hashCode);
  }

  /// Annuler toutes les notifications
  Future<void> cancelAll() async {
    await _local.cancelAll();
  }
}

@pragma('vm:entry-point')
void _bgTapCallback(NotificationResponse d) {
  debugPrint('[Notif BG Tap] payload=${d.payload}');
}