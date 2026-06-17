import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/message_provider.dart';
import '../providers/rendez_vous_provider.dart';
import '../models/message_model.dart';
import '../utils/constants.dart';
import 'notification_prefs_service.dart';
import 'notification_service.dart';

class PusherService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final PusherService _instance = PusherService._internal();
  factory PusherService() => _instance;
  PusherService._internal();

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _storage = const FlutterSecureStorage(aOptions: _androidOptions, iOptions: _iOSOptions);

  // ── État interne ───────────────────────────────────────────────────────────
  PusherChannelsFlutter? _pusher;
  bool    _isInitialized  = false;
  bool    _isConnecting   = false;
  String? _currentUserId;

  // Canaux gérés
  final Set<String> _pendingChannels    = {};
  final Set<String> _subscribedChannels = {};

  // Reconnexion exponentielle : 2s, 4s, 8s, 16s, 30s (max)
  int    _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectAttempts = 10;

  // Providers injectés
  MessageProvider?    _messageProvider;
  RendezVousProvider? _rdvProvider;

  // Typing / Recording auto-timeout (comme WhatsApp)
  // { "convId:userId" → Timer }
  final Map<String, Timer> _typingTimers    = {};
  final Map<String, Timer> _recordingTimers = {};

  // ── Providers ──────────────────────────────────────────────────────────────
  void setMessageProvider(MessageProvider p) => _messageProvider = p;
  void setRendezVousProvider(RendezVousProvider p) => _rdvProvider = p;

  bool get isConnected   => _isInitialized;
  bool get isReconnecting => _isConnecting;
  String? get currentUserId => _currentUserId;

  Future<void> initialize() async {
    if (_isConnecting) return;
    if (_isInitialized) {
      await _subscribeAllPending();
      return;
    }

    _isConnecting = true;
    debugPrint('[Pusher] ▶ Initialisation...');

    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw == null || raw.isEmpty) {
        debugPrint('[Pusher] Pas de user_data → abandon');
        _isConnecting = false;
        return;
      }

      _currentUserId = (jsonDecode(raw) as Map<String, dynamic>)['id']?.toString();
      if (_currentUserId == null) {
        _isConnecting = false;
        return;
      }

      // Canal utilisateur toujours préinscrit
      _pendingChannels.add('private-user.$_currentUserId');

      _pusher = PusherChannelsFlutter.getInstance();

      await _pusher!.init(
        apiKey : AppConstants.pusherKey,
        cluster: AppConstants.pusherCluster,

        onConnectionStateChange: _onConnectionStateChange,
        onError              : _onError,
        onEvent              : (dynamic e) { if (e is PusherEvent) _onEvent(e); },
        onAuthorizer         : (channel, socketId, opts) => _authorize(channel, socketId),
      );

      await _pusher!.connect();

    } catch (e) {
      debugPrint('[Pusher] Erreur init: $e');
      _isInitialized = false;
      _isConnecting  = false;
      _scheduleReconnect();
    }
  }

  // ── Callbacks état de connexion ────────────────────────────────────────────
  void _onConnectionStateChange(String current, String previous) {
    debugPrint('[Pusher] État: $previous → $current');

    if (current == 'CONNECTED') {
      _isInitialized     = true;
      _isConnecting      = false;
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _subscribeAllPending();

    } else if (current == 'DISCONNECTED') {
      _isInitialized = false;
      _subscribedChannels.clear();
      _clearAllIndicators();

    } else if (current == 'FAILED') {
      _isInitialized = false;
      _isConnecting  = false;
      _subscribedChannels.clear();
      _clearAllIndicators();
      _scheduleReconnect();
    }
  }

  void _onError(String message, int? code, dynamic error) {
    debugPrint('[Pusher] Erreur: $message (code: $code)');
    _isInitialized = false;
    _isConnecting  = false;
    _scheduleReconnect();
  }

  // ── Reconnexion exponentielle ─────────────────────────────────────────────
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[Pusher] Max tentatives atteint (${ _maxReconnectAttempts})');
      return;
    }
    _reconnectTimer?.cancel();

    // Délai : 2^n secondes, plafonné à 30s
    final seconds = (_reconnectAttempts < 5)
        ? (1 << (_reconnectAttempts + 1))   // 2, 4, 8, 16, 32 → min(32,30)=30
        : 30;
    final delay = Duration(seconds: seconds.clamp(2, 30));

    _reconnectAttempts++;
    debugPrint('[Pusher] Reconnexion dans ${delay.inSeconds}s (tentative $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () async {
      if (!_isInitialized && !_isConnecting) await initialize();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  AUTHORISATION PUSHER (canal privé)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<dynamic> _authorize(String channelName, String socketId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) return null;

      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/pusher/auth'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/x-www-form-urlencoded',
          'Accept'       : 'application/json',
        },
        body: 'socket_id=$socketId&channel_name=$channelName',
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded.containsKey('auth')) return decoded;
      }
      debugPrint('[Pusher] Auth échouée ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      debugPrint('[Pusher] Auth erreur: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  SOUSCRIPTION AUX CANAUX
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _subscribeAllPending() async {
    final todo = Set<String>.from(_pendingChannels);
    for (final ch in todo) {
      if (!_subscribedChannels.contains(ch)) await _subscribe(ch);
    }
  }

  Future<void> _subscribe(String channelName) async {
    if (!_isInitialized) {
      _pendingChannels.add(channelName);
      return;
    }
    if (_subscribedChannels.contains(channelName)) return;

    try {
      await _pusher?.subscribe(
        channelName: channelName,
        onEvent: (dynamic e) { if (e is PusherEvent) _onEvent(e); },
      );
      _subscribedChannels.add(channelName);
      debugPrint('[Pusher] ✓ $channelName');
    } catch (e) {
      debugPrint('[Pusher] Erreur souscription $channelName: $e');
    }
  }

  /// Souscrire au canal d'une conversation (appelé à l'ouverture du ChatScreen)
  Future<void> subscribeToConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    _pendingChannels.add(ch);
    if (_isInitialized && !_subscribedChannels.contains(ch)) await _subscribe(ch);
  }

  /// Désabonner d'une conversation (appelé à la fermeture du ChatScreen)
  Future<void> unsubscribeFromConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    _pendingChannels.remove(ch);
    if (_subscribedChannels.contains(ch)) {
      try {
        await _pusher?.unsubscribe(channelName: ch);
        _subscribedChannels.remove(ch);
        debugPrint('[Pusher] ✗ Désabonné: $ch');
      } catch (e) {
        debugPrint('[Pusher] Erreur désabonnement: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DISPATCHER D'ÉVÉNEMENTS
  // ═══════════════════════════════════════════════════════════════════════════
  void _onEvent(PusherEvent event) {
    if (event.eventName.startsWith('pusher')) return;
    if (event.data == null || event.data!.isEmpty) return;

    try {
      final data = jsonDecode(event.data!) as Map<String, dynamic>;
      debugPrint('[Pusher] ← ${event.eventName} | ${event.channelName}');

      switch (event.eventName) {
        // ── Messages ────────────────────────────────────────────────────
        case 'new-message':
          _onNewMessage(data);
          break;
        case 'message-sent':
          _onMessageSent(data);
          break;

        // ── Indicateurs temps réel (WhatsApp-like) ──────────────────────
        case 'typing-indicator':
          _onTypingIndicator(data);
          break;
        case 'recording-indicator':
          _onRecordingIndicator(data);
          break;

        // ── Présence ────────────────────────────────────────────────────
        case 'user-status':
          _onUserStatus(data);
          break;
        case 'messages-read':
          _onMessagesRead(data);
          break;

        // ── Rendez-vous ──────────────────────────────────────────────────
        case 'rdv-pending':
        case 'rdv-confirmed':
        case 'rdv-cancelled':
        case 'rdv-completed':
          _onRdvNotification(data, event.eventName);
          break;

        // ── Entreprises ──────────────────────────────────────────────────
        case 'entreprise-approved':
        case 'entreprise-rejected':
        case 'new-entreprise-pending':
          debugPrint('[Pusher] Événement entreprise: ${event.eventName}');
          break;

        default:
          // Fallback : si le payload contient conversation_id → traiter comme message
          if (_messageProvider != null &&
              _currentUserId != null &&
              data.containsKey('conversation_id')) {
            _onNewMessage(data);
          }
      }
    } catch (e) {
      debugPrint('[Pusher] Erreur dispatch ${event.eventName}: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  HANDLERS MÉTIER
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Nouveau message reçu (canal utilisateur) ───────────────────────────────
  void _onNewMessage(Map<String, dynamic> data) {
    if (_messageProvider == null || _currentUserId == null) return;

    final Map<String, dynamic> msgData = data['message'] is Map
        ? Map<String, dynamic>.from(data['message'] as Map)
        : Map<String, dynamic>.from(data);

    final convId   = (data['conversation_id'] ?? msgData['conversation_id'])?.toString() ?? '';
    final senderId = msgData['sender_id']?.toString() ?? '';

    if (convId.isEmpty) return;
    if (senderId == _currentUserId) return; // Ignorer nos propres messages

    final msg = MessageModel.fromJson(msgData, _currentUserId!);
    _messageProvider!.receiveMessage(msg, convId);

    // Notification locale (si préférences l'autorisent)
    NotificationPrefsService.canShow(type: 'message').then((canShow) {
      if (!canShow) return;
      final senderName = data['sender_name']?.toString() ?? 'Nouveau message';
      final body = _buildNotifBody(msg);
      NotificationService().showMessageNotification(
        senderName     : senderName,
        messageBody    : body,
        conversationId : convId,
        senderPhoto    : data['sender_photo']?.toString(),
        senderId       : senderId,
      );
    });
  }

  // ── Confirmation d'envoi (canal conversation) ──────────────────────────────
  void _onMessageSent(Map<String, dynamic> data) {
    if (_messageProvider == null || _currentUserId == null) return;

    final Map<String, dynamic> msgData = data['message'] is Map
        ? Map<String, dynamic>.from(data['message'] as Map)
        : Map<String, dynamic>.from(data);

    final convId   = msgData['conversation_id']?.toString() ?? '';
    final senderId = msgData['sender_id']?.toString() ?? '';

    if (convId.isEmpty || senderId != _currentUserId) return;
    _messageProvider!.confirmMessage(msgData, convId, _currentUserId!);
  }

  // ── Indicateur "en train d'écrire" (WhatsApp-like avec auto-timeout) ───────
  void _onTypingIndicator(Map<String, dynamic> data) {
    if (_messageProvider == null) return;

    final userId   = data['user_id']?.toString();
    final convId   = data['conversation_id']?.toString() ?? '';
    final isTyping = data['is_typing'] == true;

    if (userId == null || userId == _currentUserId || convId.isEmpty) return;

    _messageProvider!.setTypingIndicator(convId, userId, isTyping);

    final key = '$convId:$userId:typing';

    if (isTyping) {
      // Auto-arrêt si pas de mise à jour pendant 4s (comme WhatsApp)
      _typingTimers[key]?.cancel();
      _typingTimers[key] = Timer(const Duration(seconds: 4), () {
        _messageProvider?.setTypingIndicator(convId, userId, false);
        _typingTimers.remove(key);
      });
    } else {
      _typingTimers[key]?.cancel();
      _typingTimers.remove(key);
    }
  }

  // ── Indicateur "enregistre un vocal" (WhatsApp-like avec auto-timeout) ─────
  void _onRecordingIndicator(Map<String, dynamic> data) {
    if (_messageProvider == null) return;

    final userId      = data['user_id']?.toString();
    final convId      = data['conversation_id']?.toString() ?? '';
    final isRecording = data['is_recording'] == true;

    if (userId == null || userId == _currentUserId || convId.isEmpty) return;

    _messageProvider!.setRecordingIndicator(convId, userId, isRecording);

    final key = '$convId:$userId:recording';

    if (isRecording) {
      // Auto-arrêt après 60s (protection contre les clients qui ne stopent pas)
      _recordingTimers[key]?.cancel();
      _recordingTimers[key] = Timer(const Duration(seconds: 60), () {
        _messageProvider?.setRecordingIndicator(convId, userId, false);
        _recordingTimers.remove(key);
      });
    } else {
      _recordingTimers[key]?.cancel();
      _recordingTimers.remove(key);
    }
  }

  // ── Statut en ligne ────────────────────────────────────────────────────────
  void _onUserStatus(Map<String, dynamic> data) {
    if (_messageProvider == null) return;

    final userId   = data['user_id']?.toString();
    final isOnline = data['is_online'] == true;
    if (userId == null) return;

    DateTime? lastSeen;
    final raw = data['last_seen'] ?? data['last_seen_at'];
    if (raw != null) lastSeen = DateTime.tryParse(raw.toString())?.toLocal();

    _messageProvider!.updateUserOnlineStatus(userId, isOnline, lastSeen);
  }

  // ── Messages lus ──────────────────────────────────────────────────────────
  void _onMessagesRead(Map<String, dynamic> data) {
    if (_messageProvider == null) return;

    final convId = data['conversation_id']?.toString();
    if (convId != null && convId.isNotEmpty) {
      _messageProvider!.markMessagesAsReadLocally(convId);
    }
  }

  // ── Rendez-vous ────────────────────────────────────────────────────────────
  void _onRdvNotification(Map<String, dynamic> data, String eventName) {
    debugPrint('[Pusher] RDV: $eventName — rdv_id=${data['rdv_id']}');
    _rdvProvider?.updateFromNotification(data);
    _showRdvLocalNotification(data, eventName);
  }

  void _showRdvLocalNotification(Map<String, dynamic> data, String eventName) {
    try {
      final title = data['title']?.toString() ?? _rdvEventTitle(eventName);
      final body  = data['body']?.toString()  ?? '';
      final rdvId = data['rdv_id']?.toString() ?? '';
      final type  = data['type']?.toString()  ?? _rdvEventType(eventName);

      if (title.isEmpty && body.isEmpty) return;

      NotificationPrefsService.canShow(type: 'rdv').then((canShow) {
        if (!canShow) return;
        NotificationService().showNotification(
          id     : rdvId.isNotEmpty ? (rdvId.hashCode + 20000).abs() : DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title  : title,
          body   : body,
          payload: jsonEncode({'type': type, 'rdv_id': rdvId}),
        );
      });
    } catch (e) {
      debugPrint('[Pusher] _showRdvLocalNotification: $e');
    }
  }


  void _clearAllIndicators() {
    for (final t in _typingTimers.values)    t.cancel();
    for (final t in _recordingTimers.values) t.cancel();
    _typingTimers.clear();
    _recordingTimers.clear();
    // Remettre à zéro tous les indicateurs dans le provider
    _messageProvider?.clearAllIndicators();
  }

  String _buildNotifBody(MessageModel msg) {
    if (msg.content.isNotEmpty) {
      return msg.content.length > 80
          ? '${msg.content.substring(0, 80)}…'
          : msg.content;
    }
    switch (msg.type) {
      case 'image'   : return '📷 Photo';
      case 'video'   : return '🎥 Vidéo';
      case 'vocal'   : return '🎤 Message vocal';
      case 'document': return '📄 Document';
      case 'location': return '📍 Localisation';
      default        : return 'Nouveau message';
    }
  }

  String _rdvEventTitle(String event) {
    switch (event) {
      case 'rdv-pending'  : return 'Nouvelle demande de RDV';
      case 'rdv-confirmed': return 'Rendez-vous confirmé ✅';
      case 'rdv-cancelled': return 'Rendez-vous annulé ❌';
      case 'rdv-completed': return 'Rendez-vous terminé 🎉';
      default             : return 'Rendez-vous';
    }
  }

  String _rdvEventType(String event) {
    switch (event) {
      case 'rdv-pending'  : return 'rdv_pending';
      case 'rdv-confirmed': return 'rdv_confirmed';
      case 'rdv-cancelled': return 'rdv_cancelled';
      case 'rdv-completed': return 'rdv_completed';
      default             : return 'rdv_pending';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CYCLE DE VIE
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> reinitialize() async {
    _reconnectTimer?.cancel();
    _clearAllIndicators();
    _isInitialized     = false;
    _isConnecting      = false;
    _reconnectAttempts = 0;
    _currentUserId     = null;
    _subscribedChannels.clear();
    try { await _pusher?.disconnect(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
    await initialize();
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _clearAllIndicators();
    try {
      if (_isInitialized) {
        for (final ch in Set<String>.from(_subscribedChannels)) {
          try { await _pusher?.unsubscribe(channelName: ch); } catch (_) {}
        }
        await _pusher?.disconnect();
        _isInitialized = false;
        _subscribedChannels.clear();
      }
    } catch (e) {
      debugPrint('[Pusher] disconnect: $e');
    }
  }
}