// services/notification_service.dart
// ⭐ VERSION FINALE — background handler sans FlutterSecureStorage, token FCM en attente
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz_data;
import '../utils/constants.dart';

// ─── Handler FCM BACKGROUND — OBLIGATOIREMENT top-level ────────────────────
// N'utilise PAS FlutterSecureStorage ni aucune instance singleton
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM BG] id=${message.messageId}');
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    // Créer le canal Android si nécessaire
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
    final payload = convId != null ? jsonEncode({'conversation_id': convId}) : null;

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

// ───────────────────────────────────────────────────────────────────────────
class NotificationService {
  static final NotificationService _inst = NotificationService._internal();
  factory NotificationService() => _inst;
  NotificationService._internal();

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage(aOptions: _androidOptions, iOptions: _iOSOptions);

  Function(String conversationId)? onNotificationTap;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    tz_data.initializeTimeZones();

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: (d) => _handleTap(d.payload),
      onDidReceiveBackgroundNotificationResponse: _bgTapCallback,
    );

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'high_importance_channel', 'Messages',
          description: 'Notifications de nouveaux messages',
          importance: Importance.high, playSound: true, enableVibration: true,
          sound: RawResourceAndroidNotificationSound('notification_bell'),
        ));

    await _initFCM();
  }

  Future<void> _initFCM() async {
    final settings = await _fcm.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // Foreground
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[FCM FG] ${msg.notification?.title}');
      showFCMNotification(msg);
    });

    // App ouverte depuis arrière-plan
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final convId = msg.data['conversation_id']?.toString();
      if (convId != null) onNotificationTap?.call(convId);
    });

    // App lancée depuis notification fermée
    final init = await _fcm.getInitialMessage();
    if (init != null) {
      final convId = init.data['conversation_id']?.toString();
      if (convId != null) {
        Future.delayed(const Duration(milliseconds: 1500), () => onNotificationTap?.call(convId));
      }
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
        body: jsonEncode({'fcm_token': fcmToken, 'platform': Platform.isIOS ? 'ios' : 'android'}),
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        debugPrint('[FCM] Token enregistré ✓');
        await _storage.delete(key: 'fcm_token_pending');
      }
    } catch (e) { debugPrint('[FCM] Erreur envoi token: $e'); }
  }

  // ⭐ Appeler après login réussi
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

  Future<void> showFCMNotification(RemoteMessage message) async {
    final notif  = message.notification;
    final data   = message.data;
    final title  = notif?.title ?? data['title'] ?? 'Nouveau message';
    final body   = notif?.body  ?? data['body']  ?? '';
    final convId = data['conversation_id']?.toString();
    final payload = convId != null ? jsonEncode({'conversation_id': convId}) : null;
    await showNotification(
      id: convId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title, body: body, payload: payload,
    );
  }

  Future<void> showMessageNotification({
    required String senderName, required String messageBody, required String conversationId,
  }) async {
    await showNotification(
      id: conversationId.hashCode, title: senderName, body: messageBody,
      payload: jsonEncode({'conversation_id': conversationId}),
    );
  }

  Future<void> showNotification({
    required int id, required String title, required String body, String? payload,
  }) async {
    await _local.show(id, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel', 'Messages',
          channelDescription: 'Notifications de nouveaux messages',
          importance: Importance.high, priority: Priority.high,
          enableVibration: true, playSound: true,
          sound: const RawResourceAndroidNotificationSound('notification_bell'),
          icon: '@mipmap/ic_launcher', visibility: NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(
          sound: 'default', presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  void _handleTap(String? payload) {
    if (payload == null) return;
    try {
      final data   = jsonDecode(payload) as Map<String, dynamic>;
      final convId = data['conversation_id']?.toString();
      if (convId != null) onNotificationTap?.call(convId);
    } catch (e) { debugPrint('[Notif] tap: $e'); }
  }
}

@pragma('vm:entry-point')
void _bgTapCallback(NotificationResponse d) {
  debugPrint('[Notif BG Tap] payload=${d.payload}');
}