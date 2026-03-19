// lib/services/notification_service.dart
// ═══════════════════════════════════════════════════════════════════════
// ARCHITECTURE COMPLÈTE — Notifications temps réel
//
// FONCTIONNEMENT:
//  1. App OUVERTE (foreground):
//     → Pusher WebSocket reçoit les events en temps réel
//     → ChatScreen se met à jour via Consumer<MessageProvider>
//     → RDV : RendezVousProvider.updateFromNotification() + notif locale
//
//  2. App EN ARRIÈRE-PLAN:
//     → FCM envoie une push notification
//     → Tap → navigue vers ChatScreen (message) ou RendezVousDetailScreen (RDV)
//
//  3. App FERMÉE:
//     → firebaseMessagingBackgroundHandler affiche la notification
//     → Tap → App démarre → navigue via getInitialMessage()
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
import 'pusher_service.dart';                              // ← AJOUT (pour NotificationServiceRef)

// ── Canal Android messages ────────────────────────────────────────────────────
const String _kChannelId   = 'careasy_messages';
const String _kChannelName = 'Messages CarEasy';
const String _kChannelDesc = 'Notifications de messages CarEasy';

// ── Canal Android rendez-vous ─────────────────────────────────────────────────
const String _kRdvChannelId   = 'careasy_rdv';
const String _kRdvChannelName = 'Rendez-vous CarEasy';
const String _kRdvChannelDesc = 'Notifications de rendez-vous CarEasy';

// ═══════════════════════════════════════════════════════════════════════
// HANDLER FCM BACKGROUND
// ═══════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM BG] Reçu: ${message.notification?.title}');

  try {
    final plugin = FlutterLocalNotificationsPlugin();

    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));

    // Créer les deux canaux (idempotent)
    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _kChannelId, _kChannelName,
      description  : _kChannelDesc,
      importance   : Importance.high,
      playSound    : true,
      enableVibration: true,
    ));

    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _kRdvChannelId, _kRdvChannelName,
      description  : _kRdvChannelDesc,
      importance   : Importance.high,
      playSound    : true,
      enableVibration: true,
    ));

    final notif  = message.notification;
    final data   = message.data;
    final type   = data['type']?.toString() ?? '';
    final title  = notif?.title ?? data['title'] ?? 'CarEasy';
    final body   = notif?.body  ?? data['body']  ?? '';

    // Choisir le canal et le payload selon le type
    final bool isRdv = type.startsWith('rdv_');
    final String channelId   = isRdv ? _kRdvChannelId   : _kChannelId;
    final String channelName = isRdv ? _kRdvChannelName : _kChannelName;
    final String channelDesc = isRdv ? _kRdvChannelDesc : _kChannelDesc;

    final String payload;
    if (isRdv) {
      payload = jsonEncode({
        'type'  : type,
        'rdv_id': data['rdv_id'] ?? '',
      });
    } else {
      final convId = data['conversation_id']?.toString() ?? '';
      payload = jsonEncode({
        'conversation_id': convId,
        'sender_name'    : data['sender_name']  ?? '',
        'sender_photo'   : data['sender_photo'] ?? '',
        'sender_id'      : data['sender_id']    ?? '',
      });
    }

    final notifId = isRdv
        ? (data['rdv_id']?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000)
        : (data['conversation_id']?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000);

    await plugin.show(
      notifId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId, channelName,
          channelDescription: channelDesc,
          importance      : Importance.high,
          priority        : Priority.high,
          playSound       : true,
          enableVibration : true,
          icon            : '@mipmap/ic_launcher',
          visibility      : NotificationVisibility.public,
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
void _bgTapCallback(NotificationResponse response) {
  debugPrint('[Notif BG Tap] payload=${response.payload}');
}

// ═══════════════════════════════════════════════════════════════════════
// NOTIFICATION SOUND PREFS
// ═══════════════════════════════════════════════════════════════════════
class NotificationSoundPrefs {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyUseCustom  = 'notif_use_custom_sound';
  static const _keySoundName  = 'notif_custom_sound_name';
  static const _keySoundLabel = 'notif_custom_sound_label';

  static const List<Map<String, String>> availableSounds = [
    {'name': 'default', 'label': 'Son par défaut'},
    {'name': 'message', 'label': 'Message'},
    {'name': 'chime',   'label': 'Carillon'},
    {'name': 'pop',     'label': 'Pop'},
  ];

  static Future<bool>   getUseCustomSound()   async =>
      (await _storage.read(key: _keyUseCustom))  == 'true';
  static Future<String> getCustomSoundName()  async =>
      (await _storage.read(key: _keySoundName))  ?? 'default';
  static Future<String> getCustomSoundLabel() async =>
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
// NOTIFICATION SERVICE — Singleton principal
// ═══════════════════════════════════════════════════════════════════════
class NotificationService {
  static final NotificationService _inst = NotificationService._internal();
  factory NotificationService() => _inst;
  NotificationService._internal();

  static const _androidOptions = AndroidOptions(
      encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(
      accessibility: KeychainAccessibility.first_unlock);

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  // Callback de navigation (messages ET rendez-vous)
  Function(Map<String, dynamic> data)? onNotificationTap;

  bool _initialized = false;

  // ─── INITIALISATION ────────────────────────────────────────────────
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
      onDidReceiveNotificationResponse: (response) {
        _handleTap(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: _bgTapCallback,
    );

    await _createAndroidChannels();
    await _initFCM();

    // ── Enregistrer la callback dans NotificationServiceRef ───────────
    // Permet à PusherService d'afficher des notifications locales
    // sans créer d'import circulaire.
    NotificationServiceRef.register(({
      required int id,
      required String title,
      required String body,
      String? payload,
    }) =>
        showNotification(id: id, title: title, body: body, payload: payload));
  }

  // ─── CANAUX ANDROID ────────────────────────────────────────────────
  Future<void> _createAndroidChannels() async {
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Canal messages
    await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
      _kChannelId, _kChannelName,
      description  : _kChannelDesc,
      importance   : Importance.high,
      playSound    : true,
      enableVibration: true,
    ));

    // Canal rendez-vous
    await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
      _kRdvChannelId, _kRdvChannelName,
      description  : _kRdvChannelDesc,
      importance   : Importance.high,
      playSound    : true,
      enableVibration: true,
    ));

    debugPrint('[Notif] Canaux Android créés: $_kChannelId, $_kRdvChannelId');
  }

  // ─── AFFICHAGE D'UNE NOTIFICATION LOCALE ──────────────────────────
  Future<void> showNotification({
    required int    id,
    required String title,
    required String body,
    String?         payload,
    bool            isRdv = false,
  }) async {
    final channelId   = isRdv ? _kRdvChannelId   : _kChannelId;
    final channelName = isRdv ? _kRdvChannelName : _kChannelName;
    final channelDesc = isRdv ? _kRdvChannelDesc : _kChannelDesc;

    await _local.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId, channelName,
          channelDescription: channelDesc,
          importance      : Importance.high,
          priority        : Priority.high,
          playSound       : true,
          enableVibration : true,
          icon            : '@mipmap/ic_launcher',
          visibility      : NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(
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

  // ─── NOTIFICATION DE RENDEZ-VOUS ────────────────────────────────────
  Future<void> showRdvNotification({
    required String title,
    required String body,
    required String rdvId,
    required String type,
  }) async {
    final payload = jsonEncode({
      'type'  : type,
      'rdv_id': rdvId,
    });

    await showNotification(
      id     : rdvId.hashCode,
      title  : title,
      body   : body,
      payload: payload,
      isRdv  : true,
    );
  }

  // ─── NOTIFICATION FCM FOREGROUND ───────────────────────────────────
  Future<void> showFCMNotification(RemoteMessage message) async {
    final notif = message.notification;
    final data  = message.data;
    final type  = data['type']?.toString() ?? '';

    if (type.startsWith('rdv_')) {
      // Notification RDV en foreground
      await showRdvNotification(
        title: notif?.title ?? data['title'] ?? 'Rendez-vous',
        body : notif?.body  ?? data['body']  ?? '',
        rdvId: data['rdv_id']?.toString() ?? '',
        type : type,
      );
    } else {
      // Notification message en foreground
      final convId = data['conversation_id']?.toString();
      final payload = jsonEncode({
        'conversation_id': convId ?? '',
        'sender_name'    : data['sender_name']  ?? '',
        'sender_photo'   : data['sender_photo'] ?? '',
        'sender_id'      : data['sender_id']    ?? '',
      });

      await showNotification(
        id     : convId?.hashCode ??
                 DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title  : notif?.title ?? data['title'] ?? 'Nouveau message',
        body   : notif?.body  ?? data['body']  ?? '',
        payload: payload,
      );
    }
  }

  // ─── ANNULATION ────────────────────────────────────────────────────
  Future<void> cancelNotification(String id) async {
    await _local.cancel(id.hashCode);
  }

  Future<void> cancelAll() async => _local.cancelAll();

  // ─── FCM ────────────────────────────────────────────────────────────
  Future<void> _initFCM() async {
    final settings = await _fcm.requestPermission(
      alert      : true,
      badge      : true,
      sound      : true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[FCM] Notifications refusées');
      return;
    }

    // Foreground : afficher la notification locale
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      debugPrint('[FCM FG] ${msg.notification?.title}');
      showFCMNotification(msg);
    });

    // Arrière-plan : tap sur la notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      debugPrint('[FCM] onMessageOpenedApp: ${msg.data}');
      _handleFCMTap(msg.data);
    });

    // App fermée : tap sur la notification au démarrage
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM] Initial message: ${initial.data}');
      Future.delayed(
        const Duration(milliseconds: 1500),
        () => _handleFCMTap(initial.data),
      );
    }

    await _registerFCMToken();
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  Future<void> _registerFCMToken() async {
    try {
      String? token;
      if (Platform.isIOS) {
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

  /// Tap sur une notification locale (foreground/background)
  void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      debugPrint('[Notif] Tap: $data');
      onNotificationTap?.call(data);
    } catch (_) {
      onNotificationTap?.call({'conversation_id': payload});
    }
  }

  /// Tap sur une notification FCM (background/killed)
  void _handleFCMTap(Map<String, dynamic> data) {
    debugPrint('[FCM] Tap navigation: $data');

    final type  = data['type']?.toString() ?? '';
    final rdvId = data['rdv_id']?.toString() ?? '';

    // ── Notification RDV ─────────────────────────────────────────────
    if (type.startsWith('rdv_') || rdvId.isNotEmpty) {
      onNotificationTap?.call({
        'type'  : type.isNotEmpty ? type : 'rdv_pending',
        'rdv_id': rdvId,
      });
      return;
    }

    // ── Notification Message ──────────────────────────────────────────
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
  Future<void> updateNotificationChannel() async {
    if (!Platform.isAndroid) return;
    try {
      final useCustom = await NotificationSoundPrefs.getUseCustomSound();
      final soundName = await NotificationSoundPrefs.getCustomSoundName();

      AndroidNotificationChannel channel;
      if (useCustom && soundName != 'default') {
        channel = AndroidNotificationChannel(
          _kChannelId, _kChannelName,
          description: _kChannelDesc,
          importance : Importance.high,
          playSound  : true,
          sound      : RawResourceAndroidNotificationSound(soundName),
        );
      } else {
        channel = const AndroidNotificationChannel(
          _kChannelId, _kChannelName,
          description: _kChannelDesc,
          importance : Importance.high,
          playSound  : true,
        );
      }

      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      debugPrint(
          '[Notif] Canal mis à jour (son: ${useCustom ? soundName : "défaut"})');
    } catch (e) {
      debugPrint('[Notif] updateNotificationChannel error: $e');
    }
  }

  Future<void> playSoundPreview(String soundName) async {
    try {
      AndroidNotificationDetails androidDetails;
      if (soundName != 'default') {
        androidDetails = AndroidNotificationDetails(
          'careasy_preview', 'Aperçu son',
          channelDescription: 'Aperçu des sons de notification',
          importance        : Importance.high,
          priority          : Priority.high,
          playSound         : true,
          sound             : RawResourceAndroidNotificationSound(soundName),
          silent            : false,
        );
      } else {
        androidDetails = const AndroidNotificationDetails(
          'careasy_preview', 'Aperçu son',
          channelDescription: 'Aperçu des sons de notification',
          importance        : Importance.high,
          priority          : Priority.high,
          playSound         : true,
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