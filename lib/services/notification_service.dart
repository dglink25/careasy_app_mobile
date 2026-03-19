// lib/services/notification_service.dart
// ═══════════════════════════════════════════════════════════════════════
// ARCHITECTURE COMPLÈTE — Notifications temps réel
//
// FONCTIONNEMENT:
//  1. App OUVERTE (foreground):
//     → Pusher WebSocket reçoit les events en temps réel
//     → ChatScreen se met à jour automatiquement via Consumer<MessageProvider>
//     → Indicateurs typing/recording affichés dans l'AppBar
//
//  2. App EN ARRIÈRE-PLAN ou VERROUILLÉE:
//     → FCM (Firebase Cloud Messaging) envoie une vraie notification push
//     → Son = son par défaut du téléphone (pas de son personnalisé)
//     → Tap sur la notification → ouvre le bon ChatScreen
//
//  3. App FERMÉE:
//     → firebaseMessagingBackgroundHandler (top-level) reçoit le message FCM
//     → Affiche la notification avec flutter_local_notifications
//     → Tap → App démarre → navigue vers le bon chat
//
// SON: Toujours le son par défaut du téléphone (conforme à ce qui est demandé)
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz_data;
import '../utils/constants.dart';

// ═══════════════════════════════════════════════════════════════════════
// CANAL ANDROID UNIQUE — son système par défaut
// Android API 26+: le son est défini par le canal, pas par la notification.
// On crée UN seul canal avec Importance.high → le système joue son son par défaut.
// ═══════════════════════════════════════════════════════════════════════
const String _kChannelId   = 'careasy_messages';
const String _kChannelName = 'Messages CarEasy';
const String _kChannelDesc = 'Notifications de messages CarEasy';

// ═══════════════════════════════════════════════════════════════════════
// HANDLER FCM BACKGROUND — obligatoirement top-level (pas dans une classe)
// Appelé quand l'app est FERMÉE ou en arrière-plan (Android/iOS).
// Pas d'accès au BuildContext ni aux providers ici.
// ═══════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM BG] Reçu: ${message.notification?.title}');

  try {
    final plugin = FlutterLocalNotificationsPlugin();

    // Initialisation minimale pour le background isolate
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));

    // Créer le canal Android (idempotent — safe si déjà créé)
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _kChannelId,
          _kChannelName,
          description: _kChannelDesc,
          importance: Importance.high,
          playSound: true,         // son système par défaut
          enableVibration: true,
          // PAS de sound: RawResourceAndroidNotificationSound(...)
          // → le système utilise son son par défaut
        ));

    final notif  = message.notification;
    final data   = message.data;
    final title  = notif?.title ?? data['title'] ?? 'Nouveau message';
    final body   = notif?.body  ?? data['body']  ?? '';
    final convId = data['conversation_id']?.toString();

    // Payload JSON pour la navigation au tap
    final payload = jsonEncode({
      'conversation_id': convId ?? '',
      'sender_name'    : data['sender_name']  ?? '',
      'sender_photo'   : data['sender_photo'] ?? '',
      'sender_id'      : data['sender_id']    ?? '',
    });

    await plugin.show(
      // ID unique par conversation pour éviter le spam de notifications
      convId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          channelDescription: _kChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
          // styleInformation: BigTextStyleInformation pour les longs messages
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // sound: null → son système par défaut iOS
        ),
      ),
      payload: payload,
    );
  } catch (e) {
    debugPrint('[FCM BG] Erreur: $e');
  }
}

// Callback background tap — top-level obligatoire
@pragma('vm:entry-point')
void _bgTapCallback(NotificationResponse response) {
  debugPrint('[Notif BG Tap] payload=${response.payload}');
  // La navigation sera gérée au démarrage via getInitialMessage()
}

// ═══════════════════════════════════════════════════════════════════════
// NOTIFICATION SERVICE — Singleton principal
// ═══════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════
// NOTIFICATION SOUND PREFS — Préférences de son pour les notifications
// Utilisé par notifications_settings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
class NotificationSoundPrefs {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyUseCustom  = 'notif_use_custom_sound';
  static const _keySoundName  = 'notif_custom_sound_name';
  static const _keySoundLabel = 'notif_custom_sound_label';

  /// Sons disponibles (son système = pas de son personnalisé)
  static const List<Map<String, String>> availableSounds = [
    {'name': 'default', 'label': 'Son par défaut'},
    {'name': 'message', 'label': 'Message'},
    {'name': 'chime',   'label': 'Carillon'},
    {'name': 'pop',     'label': 'Pop'},
  ];

  static Future<bool>    getUseCustomSound()    async =>
      (await _storage.read(key: _keyUseCustom))  == 'true';
  static Future<String>  getCustomSoundName()   async =>
      (await _storage.read(key: _keySoundName))  ?? 'default';
  static Future<String>  getCustomSoundLabel()  async =>
      (await _storage.read(key: _keySoundLabel)) ?? 'Son par défaut';

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

// ═══════════════════════════════════════════════════════════════════════
class NotificationService {
  static final NotificationService _inst = NotificationService._internal();
  factory NotificationService() => _inst;
  NotificationService._internal();

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  // Callback de navigation appelé quand l'utilisateur tape une notification
  // Reçoit: {conversation_id, sender_name, sender_photo, sender_id}
  Function(Map<String, dynamic> data)? onNotificationTap;

  bool _initialized = false;

  // ─── INITIALISATION ────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    tz_data.initializeTimeZones();

    // 1. Initialiser flutter_local_notifications
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      // Tap en foreground
      onDidReceiveNotificationResponse: (response) {
        _handleTap(response.payload);
      },
      // Tap depuis background (app pas encore fermée)
      onDidReceiveBackgroundNotificationResponse: _bgTapCallback,
    );

    // 2. Créer le canal Android (Importance.high = son système par défaut)
    await _createAndroidChannel();

    // 3. Initialiser FCM
    await _initFCM();
  }

  // ─── CANAL ANDROID ─────────────────────────────────────────────────
  Future<void> _createAndroidChannel() async {
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _kChannelId,
          _kChannelName,
          description: _kChannelDesc,
          importance: Importance.high,
          playSound: true,       // son système par défaut du téléphone
          enableVibration: true,
          // Pas de sound personnalisé → son système
        ));
    debugPrint('[Notif] Canal Android créé: $_kChannelId');
  }

  // ─── AFFICHAGE D'UNE NOTIFICATION LOCALE ──────────────────────────
  Future<void> showNotification({
    required int    id,
    required String title,
    required String body,
    String?         payload,
  }) async {
    await _local.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          channelDescription: _kChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ─── NOTIFICATION DE MESSAGE ────────────────────────────────────────
  Future<void> showMessageNotification({
    required String senderName,
    required String messageBody,
    required String conversationId,
    String? senderPhoto,
    String? senderId,
  }) async {
    final payload = jsonEncode({
      'conversation_id': conversationId,
      'sender_name'    : senderName,
      'sender_photo'   : senderPhoto ?? '',
      'sender_id'      : senderId    ?? '',
    });

    await showNotification(
      id     : conversationId.hashCode,
      title  : senderName,
      body   : messageBody.length > 100
                   ? '${messageBody.substring(0, 100)}…'
                   : messageBody,
      payload: payload,
    );
  }

  // ─── NOTIFICATION FCM FOREGROUND ───────────────────────────────────
  Future<void> showFCMNotification(RemoteMessage message) async {
    final notif  = message.notification;
    final data   = message.data;
    final convId = data['conversation_id']?.toString();

    final payload = jsonEncode({
      'conversation_id': convId ?? '',
      'sender_name'    : data['sender_name']  ?? '',
      'sender_photo'   : data['sender_photo'] ?? '',
      'sender_id'      : data['sender_id']    ?? '',
    });

    await showNotification(
      id     : convId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title  : notif?.title ?? data['title'] ?? 'Nouveau message',
      body   : notif?.body  ?? data['body']  ?? '',
      payload: payload,
    );
  }

  // ─── ANNULATION ────────────────────────────────────────────────────
  Future<void> cancelNotification(String conversationId) async {
    await _local.cancel(conversationId.hashCode);
  }

  Future<void> cancelAll() async => _local.cancelAll();

  // ─── FCM ────────────────────────────────────────────────────────────
  Future<void> _initFCM() async {
    // Demander la permission (iOS obligatoire, Android 13+)
    final settings = await _fcm.requestPermission(
      alert    : true,
      badge    : true,
      sound    : true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[FCM] Notifications refusées par l\'utilisateur');
      return;
    }

    // Message reçu en FOREGROUND (app ouverte à l'écran)
    // Pusher gère déjà la mise à jour du chat, mais on affiche quand même
    // la notification si l'utilisateur n'est PAS dans ce chatscreen précis
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      debugPrint('[FCM FG] ${msg.notification?.title}');
      // Note: Dans ChatScreen, on annule la notif après ouverture
      // Ici on l'affiche toujours pour les autres conversations
      showFCMNotification(msg);
    });

    // Tap sur notification quand l'app est en ARRIÈRE-PLAN (pas fermée)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      debugPrint('[FCM] onMessageOpenedApp: ${msg.data}');
      _handleFCMTap(msg.data);
    });

    // App lancée DEPUIS une notification (app était fermée)
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM] Initial message: ${initial.data}');
      // Délai pour laisser le temps à l'app de s'initialiser
      Future.delayed(
        const Duration(milliseconds: 1500),
        () => _handleFCMTap(initial.data),
      );
    }

    // Enregistrer le token FCM
    await _registerFCMToken();

    // Écouter les refresh de token
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  Future<void> _registerFCMToken() async {
    try {
      String? token;
      if (Platform.isIOS) {
        // iOS: attendre le token APNS d'abord
        final apns = await _fcm.getAPNSToken();
        if (apns != null) {
          token = await _fcm.getToken();
        } else {
          debugPrint('[FCM] Pas de token APNS — simulateur?');
        }
      } else {
        token = await _fcm.getToken();
      }

      if (token != null) {
        debugPrint('[FCM] Token: ${token.substring(0, 20)}…');
        await _storage.write(key: 'fcm_token_pending', value: token);
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('[FCM] Erreur récupération token: $e');
    }
  }

  Future<void> _sendTokenToBackend(String fcmToken) async {
    try {
      final authToken = await _storage.read(key: 'auth_token');
      if (authToken == null || authToken.isEmpty) {
        // Pas encore connecté — on garde le token en attente
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
        debugPrint('[FCM] Token enregistré sur le serveur ✓');
        await _storage.delete(key: 'fcm_token_pending');
      } else {
        debugPrint('[FCM] Erreur enregistrement token: ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('[FCM] Erreur envoi token au backend: $e');
    }
  }

  // Appelé après la connexion pour envoyer le token si en attente
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

  // ─── GESTION DES TAPS ──────────────────────────────────────────────
  void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      debugPrint('[Notif] Tap navigation: $data');
      onNotificationTap?.call(data);
    } catch (_) {
      // Ancien format simple
      onNotificationTap?.call({'conversation_id': payload});
    }
  }

  void _handleFCMTap(Map<String, dynamic> data) {
    debugPrint('[FCM] Tap navigation: $data');
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

  // ─── PARAMÈTRES DE SON ─────────────────────────────────────────────
  /// Recrée le canal Android avec les nouvelles préférences de son.
  /// Appelé depuis NotificationsSettingsScreen après changement.
  Future<void> updateNotificationChannel() async {
    if (!Platform.isAndroid) return;
    try {
      final useCustom = await NotificationSoundPrefs.getUseCustomSound();
      final soundName = await NotificationSoundPrefs.getCustomSoundName();

      AndroidNotificationChannel channel;
      if (useCustom && soundName != 'default') {
        channel = AndroidNotificationChannel(
          'careasy_messages',
          'Messages CarEasy',
          description : 'Notifications de nouveaux messages',
          importance  : Importance.high,
          playSound   : true,
          sound       : RawResourceAndroidNotificationSound(soundName),
        );
      } else {
        channel = const AndroidNotificationChannel(
          'careasy_messages',
          'Messages CarEasy',
          description : 'Notifications de nouveaux messages',
          importance  : Importance.high,
          playSound   : true,
          // son système par défaut
        );
      }

      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      debugPrint('[Notif] Canal mis à jour (son: ${useCustom ? soundName : "défaut"})');
    } catch (e) {
      debugPrint('[Notif] updateNotificationChannel error: $e');
    }
  }

  /// Joue un aperçu du son (simple notification silencieuse avec son).
  Future<void> playSoundPreview(String soundName) async {
    try {
      AndroidNotificationDetails androidDetails;
      if (soundName != 'default') {
        androidDetails = AndroidNotificationDetails(
          'careasy_preview',
          'Aperçu son',
          channelDescription : 'Aperçu des sons de notification',
          importance         : Importance.high,
          priority           : Priority.high,
          playSound          : true,
          sound              : RawResourceAndroidNotificationSound(soundName),
          silent             : false,
        );
      } else {
        androidDetails = const AndroidNotificationDetails(
          'careasy_preview',
          'Aperçu son',
          channelDescription : 'Aperçu des sons de notification',
          importance         : Importance.high,
          priority           : Priority.high,
          playSound          : true,
        );
      }

      await _local.show(
        9999,
        'Aperçu du son',
        'Voici à quoi ressemblera votre son de notification.',
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('[Notif] playSoundPreview error: $e');
    }
  }
}