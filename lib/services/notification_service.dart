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

const String _kFcmManifestChannelId = 'high_importance_channel'; // pour FCM background OS
const String _kChannelPrefix        = 'careasy';
const String _kChannelName          = 'Notifications CarEasy';
const String _kChannelDesc          = 'Notifications de CarEasy';
const String _kCustomFileSuffix     = 'custom_file';
const String _kSmallIcon            = '@drawable/ic_stat_notification';
const int    _kBadgeNotifId         = 9999;

// ─── Calcul de l'ID de canal selon le son ────────────────────────────────────
String _channelIdForSound(String soundName) {
  if (soundName == 'default')          return '${_kChannelPrefix}_default';
  if (soundName.startsWith('/'))       return '${_kChannelPrefix}_${_kCustomFileSuffix}';
  return '${_kChannelPrefix}_$soundName';
}


@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {

  if (message.notification != null) {
    debugPrint('[FCM BG] Notif affichée par OS: ${message.notification?.title}');
    return;
  }

  // Data-only → on affiche manuellement avec le son personnalisé
  debugPrint('[FCM BG] Data-only message reçu...');
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final soundName = (await storage.read(key: 'notif_custom_sound_name')) ?? 'default';
    final channelId = _channelIdForSound(soundName);

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_notification'),
      iOS:     DarwinInitializationSettings(),
    ));

    final p = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Créer le canal avec le bon son si inexistant
    await _ensureChannelExists(p, channelId, soundName);

    final data  = message.data;
    final title = data['title']?.toString() ?? 'CarEasy';
    final body  = data['body']?.toString()  ?? 'Nouvelle notification';

    // Son à passer dans AndroidNotificationDetails
    final AndroidNotificationSound? sound = _buildSound(soundName);

    await plugin.show(
      message.hashCode.abs() % 100000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId, _kChannelName,
          channelDescription: _kChannelDesc,
          importance:      Importance.high,
          priority:        Priority.high,
          playSound:       true,
          sound:           sound,       // ← son personnalisé
          enableVibration: true,
          icon:            _kSmallIcon,
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          color:           const Color(0xFFC0392B),
          visibility:      NotificationVisibility.public,
          autoCancel:      true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );
    debugPrint('[FCM BG] Notif affichée | canal: $channelId | son: $soundName');
  } catch (e) {
    debugPrint('[FCM BG] Erreur: $e');
  }
}

@pragma('vm:entry-point')
void _onBgNotifTap(NotificationResponse response) {
  debugPrint('[Notif BG Tap] payload: ${response.payload}');
}


AndroidNotificationSound? _buildSound(String soundName) {
  if (soundName == 'default') return null; // → son système du téléphone
  if (soundName.startsWith('/')) {
    return UriAndroidNotificationSound('file://$soundName');
  }
  return RawResourceAndroidNotificationSound(soundName);
}

Future<void> _ensureChannelExists(
  AndroidFlutterLocalNotificationsPlugin? p,
  String channelId,
  String soundName,
) async {
  if (p == null) return;
  try {
    final existing = await p.getNotificationChannels() ?? [];
    final alreadyExists = existing.any((ch) => ch.id == channelId);
    if (alreadyExists) return; // déjà créé avec le bon son

    await p.createNotificationChannel(AndroidNotificationChannel(
      channelId, _kChannelName,
      description:     _kChannelDesc,
      importance:      Importance.high,
      playSound:       true,
      enableVibration: true,
      sound:           _buildSound(soundName),
    ));
    debugPrint('[NotifService] Canal créé: $channelId (son: $soundName)');
  } catch (e) {
    debugPrint('[NotifService] _ensureChannelExists: $e');
  }
}


class NotificationSoundPrefs {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyUseCustom  = 'notif_use_custom_sound';
  static const _keySoundName  = 'notif_custom_sound_name';
  static const _keySoundLabel = 'notif_custom_sound_label';
  static const _keyCustomMp3  = 'notif_custom_mp3_path';

  static const List<Map<String, String>> availableSounds = [
    {'name': 'default',             'label': 'Son du téléphone (défaut)', 'emoji': ''},
    {'name': 'careasy_chime_soft',  'label': 'Carillon doux',             'emoji': ''},
    {'name': 'careasy_pristine',    'label': 'Cristallin',                'emoji': ''},
    {'name': 'careasy_subtle_ping', 'label': 'Ping subtil',               'emoji': ''},
    {'name': 'careasy_success',     'label': 'Succès',                    'emoji': ''},
    {'name': 'careasy_gentle_bell', 'label': 'Cloche douce',              'emoji': ''},
    {'name': 'careasy_pop_clean',   'label': 'Pop professionnel',         'emoji': ''},
    {'name': 'careasy_notify_pro',  'label': 'Notification Pro',          'emoji': ''},
  ];

  static Future<bool>   getUseCustomSound()  async =>
      (await _storage.read(key: _keyUseCustom)) == 'true';

  static Future<String> getCustomSoundName() async =>
      (await _storage.read(key: _keySoundName)) ?? 'default';

  static Future<String> getCustomSoundLabel() async =>
      (await _storage.read(key: _keySoundLabel)) ?? 'Son du téléphone (défaut)';

  static Future<String?> getCustomMp3Path() async =>
      _storage.read(key: _keyCustomMp3);

  static Future<void> setSoundPreference({
    required bool   useCustom,
    required String soundName,
    required String soundLabel,
    String?         customMp3Path,
  }) async {
    await _storage.write(key: _keyUseCustom,  value: useCustom.toString());
    await _storage.write(key: _keySoundName,  value: soundName);
    await _storage.write(key: _keySoundLabel, value: soundLabel);
    if (customMp3Path != null) {
      await _storage.write(key: _keyCustomMp3, value: customMp3Path);
    } else if (!useCustom) {
      await _storage.delete(key: _keyCustomMp3);
    }
  }
}

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
  int  _badgeCount  = 0;
  int  get badgeCount => _badgeCount;

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

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse:           (r) => _handleLocalTap(r.payload),
      onDidReceiveBackgroundNotificationResponse: _onBgNotifTap,
    );

    _initialized = true;

    if (Platform.isAndroid) {
      // Créer le canal pour le son actuellement sélectionné
      await _setupCurrentChannel();
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    await _initFCM();

    NotificationServiceRef.register(
      ({required int id, required String title, required String body, String? payload}) =>
          showNotification(id: id, title: title, body: body, payload: payload),
    );

    debugPrint('[NotifService] Initialisé');
  }


  Future<void> _setupCurrentChannel() async {
    final p = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (p == null) return;

    final soundName = await NotificationSoundPrefs.getCustomSoundName();
    final activeId  = _channelIdForSound(soundName);

    // Supprimer les anciens canaux 'careasy_*' obsolètes
    try {
      final existing = await p.getNotificationChannels() ?? [];
      for (final ch in existing) {
        if (ch.id.startsWith(_kChannelPrefix) && ch.id != activeId) {
          await p.deleteNotificationChannel(ch.id);
          debugPrint('[NotifService] Canal obsolète supprimé: ${ch.id}');
        }
      }
    } catch (_) {}

    // Créer le canal actif si nécessaire
    await _ensureChannelExists(p, activeId, soundName);
  }

  /// Appelé par NotificationsSettingsScreen après un changement de son.
  /// Crée le nouveau canal (l'ancien est supprimé au prochain démarrage ou ici).
  Future<void> updateNotificationChannel() async {
    if (!Platform.isAndroid) return;
    final p = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (p == null) return;

    final soundName = await NotificationSoundPrefs.getCustomSoundName();
    final activeId  = _channelIdForSound(soundName);

    // Supprimer les anciens canaux 'careasy_*' sauf le nouveau
    try {
      final existing = await p.getNotificationChannels() ?? [];
      for (final ch in existing) {
        if (ch.id.startsWith(_kChannelPrefix) && ch.id != activeId) {
          await p.deleteNotificationChannel(ch.id);
          debugPrint('[NotifService] Canal supprimé: ${ch.id}');
        }
      }
    } catch (_) {}

    // Forcer la recréation du canal actif
    // (supprimer d'abord au cas où il existait déjà avec un mauvais son)
    try {
      await p.deleteNotificationChannel(activeId);
    } catch (_) {}

    await _ensureChannelExists(p, activeId, soundName);
    debugPrint('[NotifService] Canal mis à jour: $activeId (son: $soundName)');
  }

  Future<void> _initFCM() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true, badge: true, sound: true, provisional: false,
      );
      debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // iOS : afficher les notifs FCM en foreground
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      // FOREGROUND : l'app est ouverte → FCM ne montre rien automatiquement
      // On affiche via flutter_local_notifications avec le son personnalisé
      FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('[FCM FG] ${msg.notification?.title ?? msg.data['title']}');
        _showFcmAsLocal(msg);
      });

      // BACKGROUND TAP : l'app était en arrière-plan
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('[FCM] App ouverte depuis notif background');
        _handleFcmTap(msg.data);
      });

      // TERMINATED TAP : l'app était fermée
      final initial = await _fcm.getInitialMessage();
      if (initial != null) {
        Future.delayed(
          const Duration(milliseconds: 1500),
          () => _handleFcmTap(initial.data),
        );
      }

      await _registerFcmToken();
      _fcm.onTokenRefresh.listen(_sendTokenToServer);
    } catch (e) {
      debugPrint('[FCM] _initFCM: $e');
    }
  }

  /// FCM reçu en foreground → afficher avec le son personnalisé
  Future<void> _showFcmAsLocal(RemoteMessage message) async {
    final data  = message.data;
    final notif = message.notification;
    final type  = data['type']?.toString() ?? '';
    final title = notif?.title ?? data['title'] ?? 'CarEasy';
    final body  = notif?.body  ?? data['body']  ?? '';
    if (body.isEmpty && title.isEmpty) return;

    final rdvId  = data['rdv_id']?.toString() ?? '';
    final convId = data['conversation_id']?.toString() ?? '';

    if (type == 'review_request') {
      await showReviewRequestNotification(
        rdvId:       rdvId,
        serviceName: data['service_name']?.toString() ?? 'le service',
      );
      return;
    }
    if (type.startsWith('rdv_')) {
      await showRdvNotification(title: title, body: body, rdvId: rdvId, type: type);
      return;
    }
    // Message ou autre
    await showNotification(
      id: convId.isNotEmpty
          ? convId.hashCode.abs() % 10000 + 1000
          : DateTime.now().millisecondsSinceEpoch ~/ 1000 % 10000,
      title:   title,
      body:    body,
      payload: jsonEncode({
        'type':            type,
        'conversation_id': convId,
        'sender_name':     data['sender_name']  ?? '',
        'sender_photo':    data['sender_photo'] ?? '',
        'sender_id':       data['sender_id']    ?? '',
        'rdv_id':          rdvId,
      }),
    );
  }

  Future<void> _registerFcmToken() async {
    try {
      String? token;
      if (Platform.isIOS) {
        final apns = await _fcm.getAPNSToken();
        if (apns != null) token = await _fcm.getToken();
      } else {
        token = await _fcm.getToken();
      }
      if (token != null && token.isNotEmpty) {
        await _storage.write(key: 'fcm_token_pending', value: token);
        await _sendTokenToServer(token);
      }
    } catch (e) {
      debugPrint('[FCM] _registerFcmToken: $e');
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
        debugPrint('[FCM] ✅ Token enregistré');
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
        await _registerFcmToken();
      }
    } catch (e) {
      debugPrint('[FCM] refreshTokenAfterLogin: $e');
    }
  }

  Future<void> showNotification({
    required int    id,
    required String title,
    required String body,
    String?         payload,
    String          type = '',
  }) async {
    if (!_initialized) await initialize();

    _badgeCount++;

    try {
      final soundName = await NotificationSoundPrefs.getCustomSoundName();
      final channelId = _channelIdForSound(soundName);
      final sound     = _buildSound(soundName);

      // S'assurer que le canal existe avec le bon son
      final p = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (Platform.isAndroid) {
        await _ensureChannelExists(p, channelId, soundName);
      }

      await _local.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId, _kChannelName,
            channelDescription: _kChannelDesc,
            importance:      Importance.high,
            priority:        Priority.high,
            playSound:       true,
            sound:           sound,          // ← son personnalisé (null = son système)
            enableVibration: true,
            icon:            _kSmallIcon,
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            color:           const Color(0xFFC0392B),
            visibility:      NotificationVisibility.public,
            number:          _badgeCount,
            autoCancel:      true,
            showWhen:        true,
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
      debugPrint('[NotifService] ✅ "$title" | canal: $channelId | son: $soundName');
    } catch (e) {
      debugPrint('[NotifService] showNotification error: $e');
      // Fallback minimal
      try {
        await _local.show(
          id, title, body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'careasy_default', _kChannelName,
              channelDescription: _kChannelDesc,
              importance: Importance.high,
              priority:   Priority.high,
              icon:       _kSmallIcon,
              autoCancel: true,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true, presentBadge: true, presentSound: true,
            ),
          ),
          payload: payload,
        );
      } catch (_) {}
    }
  }

  Future<void> showMessageNotification({
    required String senderName,
    required String messageBody,
    required String conversationId,
    String? senderPhoto,
    String? senderId,
  }) async {
    await showNotification(
      id:      conversationId.hashCode.abs() % 10000 + 1000,
      title:   senderName,
      body:    messageBody.length > 100 ? '${messageBody.substring(0, 100)}…' : messageBody,
      payload: jsonEncode({
        'type':            'message',
        'conversation_id': conversationId,
        'sender_name':     senderName,
        'sender_photo':    senderPhoto ?? '',
        'sender_id':       senderId    ?? '',
      }),
    );
  }

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
    );
  }

  Future<void> showReviewRequestNotification({
    required String rdvId,
    required String serviceName,
  }) async {
    await showNotification(
      id:      _buildNotifId('review_request', {'rdv_id': rdvId}),
      title:   '⭐ Votre avis nous intéresse !',
      body:    "Comment s'est passé votre RDV pour $serviceName ?",
      payload: jsonEncode({'type': 'review_request', 'rdv_id': rdvId}),
    );
  }

  // ── Rappel planifié ────────────────────────────────────────────────────────
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
      if (reminderTime.isBefore(tz.TZDateTime.now(tz.local))) {
        debugPrint('[NotifService] Rappel ignoré (heure passée)');
        return;
      }

      final soundName = await NotificationSoundPrefs.getCustomSoundName();
      final channelId = _channelIdForSound(soundName);
      final sound     = _buildSound(soundName);

      // S'assurer que le canal existe
      final p = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (Platform.isAndroid) {
        await _ensureChannelExists(p, channelId, soundName);
      }

      await _local.zonedSchedule(
        _buildNotifId('rdv_reminder', {'rdv_id': rdvId}),
        '⏰ Rappel rendez-vous',
        isPrestataire
            ? 'Rappel : rendez-vous pour $serviceName dans 1h'
            : 'Votre rendez-vous pour $serviceName commence dans 1 heure !',
        reminderTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId, _kChannelName,
            channelDescription: _kChannelDesc,
            importance: Importance.high,
            priority:   Priority.high,
            playSound:  true,
            sound:      sound,
            icon:       _kSmallIcon,
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            color:      const Color(0xFFC0392B),
            autoCancel: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true, presentBadge: true, presentSound: true,
          ),
        ),
        payload: jsonEncode({'type': 'rdv_reminder', 'rdv_id': rdvId}),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('[NotifService] ✅ Rappel planifié: $rdvDate $rdvTime | son: $soundName');
    } catch (e) {
      debugPrint('[NotifService] scheduleRdvReminder: $e');
    }
  }

  Future<void> cancelRdvReminder(String rdvId) async {
    try {
      await _local.cancel(_buildNotifId('rdv_reminder', {'rdv_id': rdvId}));
    } catch (_) {}
  }

  Future<void> updateAppBadge(int count) async {
    _badgeCount = count > 0 ? count : 0;
    if (Platform.isIOS && _initialized) {
      try {
        await _local.show(
          _kBadgeNotifId, '', '',
          NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: false,
              presentBadge: true,
              presentSound: false,
              badgeNumber:  _badgeCount,
            ),
          ),
        );
        if (_badgeCount == 0) {
          await Future.delayed(const Duration(milliseconds: 100));
          await _local.cancel(_kBadgeNotifId);
        }
      } catch (e) {
        debugPrint('[NotifService] updateAppBadge iOS: $e');
      }
    }
  }

  Future<void> clearBadge() async => updateAppBadge(0);


  Future<void> playSoundPreview(String soundName) async {
    try {
      await _previewPlayer.stop();

      if (soundName == 'default') {
        // Pour le son système : envoyer une vraie notification silencieuse
        // qui laisse l'OS jouer son propre son de notification.
        // On utilise le canal careasy_default (sans son forcé → son système).
        final p = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (Platform.isAndroid) {
          await _ensureChannelExists(p, 'careasy_default', 'default');
        }
        await _local.show(
          88888, // ID fixe pour la preview
          'Aperçu son',
          'Son système par défaut du téléphone',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'careasy_default', _kChannelName,
              channelDescription: _kChannelDesc,
              importance:      Importance.high,
              priority:        Priority.high,
              playSound:       true,
              sound:           null, // → son système
              enableVibration: false,
              icon:            _kSmallIcon,
              autoCancel:      true,
              timeoutAfter:    3000,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true, presentBadge: false, presentSound: true,
            ),
          ),
        );
        debugPrint('[NotifService] Preview: son système du téléphone');
        return;
      }

      // Son uploadé (chemin absolu)
      if (soundName.startsWith('/')) {
        await _previewPlayer.play(DeviceFileSource(soundName), volume: 1.0);
        debugPrint('[NotifService] Preview: fichier $soundName');
        return;
      }

      // Son prédéfini dans assets/sounds/
      try {
        await _previewPlayer.play(AssetSource('sounds/$soundName.mp3'), volume: 1.0);
      } catch (_) {
        await _previewPlayer.play(AssetSource('sounds/$soundName.wav'), volume: 1.0);
      }
      debugPrint('[NotifService] Preview: $soundName');
    } catch (e) {
      debugPrint('[NotifService] playSoundPreview($soundName): $e');
    }
  }

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

  void _handleLocalTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (_badgeCount > 0) _badgeCount--;
    try {
      onNotificationTap?.call(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {
      onNotificationTap?.call({'conversation_id': payload});
    }
  }

  void _handleFcmTap(Map<String, dynamic> data) {
    final type  = data['type']?.toString() ?? '';
    final rdvId = data['rdv_id']?.toString() ?? '';
    if (type == 'review_request' || type.startsWith('rdv_') || rdvId.isNotEmpty) {
      onNotificationTap?.call({'type': type, 'rdv_id': rdvId});
      return;
    }
    final convId = data['conversation_id']?.toString() ?? '';
    if (convId.isNotEmpty) {
      onNotificationTap?.call({
        'conversation_id': convId,
        'sender_name':     data['sender_name']  ?? '',
        'sender_photo':    data['sender_photo'] ?? '',
        'sender_id':       data['sender_id']    ?? '',
      });
    }
  }
}

// ─── Helpers internes ────────────────────────────────────────────────────────
int _buildNotifId(String type, Map<String, dynamic> data) {
  final rdvId  = data['rdv_id']?.toString() ?? '';
  final convId = data['conversation_id']?.toString() ?? '';
  if (type == 'rdv_reminder')   return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 30000).abs();
  if (type == 'review_request') return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 40000).abs();
  if (type.startsWith('rdv_'))  return ((rdvId.isNotEmpty ? rdvId.hashCode : 0) + 20000).abs();
  return convId.isNotEmpty
      ? convId.hashCode.abs() % 10000 + 1000
      : DateTime.now().millisecondsSinceEpoch ~/ 1000 % 10000;
}


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
  ) => _showFn = fn;

  static Future<void> show({
    required int    id,
    required String title,
    required String body,
    String?         payload,
  }) async =>
      _showFn?.call(id: id, title: title, body: body, payload: payload);
}