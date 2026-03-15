// services/notification_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../utils/constants.dart';

// ⚠️ DOIT être une fonction top-level (pas dans une classe) pour fonctionner
// en background avec Firebase Messaging.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 Message FCM en arrière-plan: ${message.messageId}');
  await NotificationService().showFCMNotification(message);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage();

  // Callback appelé quand l'utilisateur tape sur une notification
  // pour naviguer vers la bonne conversation.
  Function(String conversationId)? onNotificationTap;

  // ─── Initialisation principale ────────────────────────────────────────────
  Future<void> initialize() async {
    tz_data.initializeTimeZones();

    // ── Local notifications ──────────────────────────────────────────────
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        _handleNotificationTap(details.payload);
      },
    );

    await _createNotificationChannel();

    // ── Firebase Messaging ───────────────────────────────────────────────
    await _initFCM();
  }

  Future<void> _initFCM() async {
    // Demander la permission (iOS + Android 13+)
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint(
        '🔔 Permission FCM: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('❌ Notifications FCM refusées par l\'utilisateur');
      return;
    }

    // Enregistrer le handler background (doit être appelé ici ET dans main())
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Message reçu quand l'app est en PREMIER PLAN
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 FCM au premier plan: ${message.notification?.title}');
      showFCMNotification(message);
    });

    // L'utilisateur tape sur la notif quand l'app était en ARRIÈRE-PLAN
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 Notif ouverte depuis arrière-plan');
      final conversationId = message.data['conversation_id']?.toString();
      if (conversationId != null) {
        onNotificationTap?.call(conversationId);
      }
    });

    // L'utilisateur a ouvert l'app depuis une notif (app était FERMÉE)
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🔔 App ouverte depuis notification (app fermée)');
      final conversationId =
          initialMessage.data['conversation_id']?.toString();
      if (conversationId != null) {
        // Délai pour laisser l'app s'initialiser
        Future.delayed(const Duration(milliseconds: 1500), () {
          onNotificationTap?.call(conversationId);
        });
      }
    }

    // Obtenir et envoyer le token FCM au backend
    await _registerFCMToken();

    // Écouter les changements de token
    _fcm.onTokenRefresh.listen((newToken) {
      debugPrint('🔄 Token FCM rafraîchi');
      _sendTokenToBackend(newToken);
    });
  }

  Future<void> _registerFCMToken() async {
    try {
      String? token;
      if (Platform.isIOS) {
        // Sur iOS, attendre l'APNS token d'abord
        final apnsToken = await _fcm.getAPNSToken();
        if (apnsToken != null) {
          token = await _fcm.getToken();
        }
      } else {
        token = await _fcm.getToken();
      }

      if (token != null) {
        debugPrint('📱 Token FCM: $token');
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('❌ Erreur obtention token FCM: $e');
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final authToken = await _storage.read(key: 'auth_token');
      if (authToken == null) return;

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'fcm_token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        }),
      );

      debugPrint(
          '📤 Token FCM envoyé au backend: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ Erreur envoi token FCM: $e');
    }
  }

  // ─── Afficher une notification FCM comme notification locale ──────────────
  Future<void> showFCMNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    final title = notification?.title ??
        data['title'] ??
        'Nouveau message';
    final body = notification?.body ??
        data['body'] ??
        '';
    final conversationId = data['conversation_id']?.toString();
    final payload = conversationId != null
        ? jsonEncode({'conversation_id': conversationId})
        : null;

    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: payload,
      sound: true,
    );
  }

  // ─── Afficher une notification locale générique ───────────────────────────
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool sound = true,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Messages',
      channelDescription: 'Notifications de nouveaux messages',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: sound,
      // Son de cloche par défaut
      sound: sound
          ? const RawResourceAndroidNotificationSound('notification_bell')
          : null,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      sound: 'default',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details, payload: payload);
  }

  // ─── Notification de nouveau message (appelée depuis Pusher) ─────────────
  Future<void> showMessageNotification({
    required String senderName,
    required String messageBody,
    required String conversationId,
  }) async {
    final payload = jsonEncode({'conversation_id': conversationId});

    await showNotification(
      id: conversationId.hashCode,
      title: senderName,
      body: messageBody,
      payload: payload,
    );
  }

  void _handleNotificationTap(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final conversationId = data['conversation_id']?.toString();
      if (conversationId != null) {
        onNotificationTap?.call(conversationId);
      }
    } catch (e) {
      debugPrint('Erreur parse payload notification: $e');
    }
  }

  // ─── Canal Android ────────────────────────────────────────────────────────
  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'Messages',
      description: 'Notifications de nouveaux messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      // Son de cloche personnalisé (fichier res/raw/notification_bell.mp3)
      sound: RawResourceAndroidNotificationSound('notification_bell'),
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
}