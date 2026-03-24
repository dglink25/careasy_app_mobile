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

class PusherService {
  static final PusherService _instance = PusherService._internal();
  factory PusherService() => _instance;
  PusherService._internal();

  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );
  static const _iOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );
  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  PusherChannelsFlutter? _pusher;
  bool    _isInitialized  = false;
  bool    _isConnecting   = false;
  String? _currentUserId;

  final Set<String> _pendingChannels    = {};
  final Set<String> _subscribedChannels = {};

  int    _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectAttempts = 8;

  MessageProvider?    _messageProvider;
  RendezVousProvider? _rdvProvider;

  void setMessageProvider(MessageProvider provider) {
    _messageProvider = provider;
  }

  void setRendezVousProvider(RendezVousProvider provider) {
    _rdvProvider = provider;
  }

  Future<void> initialize() async {
    if (_isConnecting) return;
    if (_isInitialized) {
      await _subscribeAllPending();
      return;
    }

    _isConnecting = true;
    debugPrint('[Pusher] Initialisation...');

    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw == null || raw.isEmpty) {
        debugPrint('[Pusher] Pas de user_data → abandon');
        _isConnecting = false;
        return;
      }

      _currentUserId =
          (jsonDecode(raw) as Map<String, dynamic>)['id']?.toString();
      if (_currentUserId == null) {
        _isConnecting = false;
        return;
      }

      _pendingChannels.add('private-user.$_currentUserId');

      _pusher = PusherChannelsFlutter.getInstance();

      await _pusher!.init(
        apiKey : AppConstants.pusherKey,
        cluster: AppConstants.pusherCluster,

        onConnectionStateChange: (String current, String previous) {
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
          } else if (current == 'FAILED') {
            _isInitialized = false;
            _isConnecting  = false;
            _subscribedChannels.clear();
            _scheduleReconnect();
          }
        },

        onError: (String message, int? code, dynamic error) {
          debugPrint('[Pusher] Erreur: $message (code: $code)');
          _isInitialized = false;
          _isConnecting  = false;
          _scheduleReconnect();
        },

        onEvent: (dynamic event) {
          if (event is PusherEvent) _onEvent(event);
        },

        onAuthorizer: (String channelName, String socketId, dynamic opts) async {
          return await _authorize(channelName, socketId);
        },
      );

      await _pusher!.connect();

    } catch (e) {
      debugPrint('[Pusher] Erreur init: $e');
      _isInitialized = false;
      _isConnecting  = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;

    _reconnectTimer?.cancel();
    final seconds = _reconnectAttempts < 4 ? (2 << _reconnectAttempts) : 30;
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      if (!_isInitialized && !_isConnecting) await initialize();
    });
  }


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
        if (decoded is Map && decoded.containsKey('auth')) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('[Pusher] Auth erreur: $e');
    }
    return null;
  }
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
        onEvent: (dynamic event) {
          if (event is PusherEvent) _onEvent(event);
        },
      );
      _subscribedChannels.add(channelName);
      debugPrint('[Pusher] ✓ Souscrit: $channelName');
    } catch (e) {
      debugPrint('[Pusher] Erreur souscription $channelName: $e');
    }
  }


  void _onEvent(PusherEvent event) {
    if (event.eventName.startsWith('pusher')) return;
    if (event.data == null || event.data!.isEmpty) return;

    try {
      final data = jsonDecode(event.data!) as Map<String, dynamic>;
      debugPrint('[Pusher] ← ${event.eventName} sur ${event.channelName}');

      switch (event.eventName) {
        case 'new-message':
          if (_messageProvider != null && _currentUserId != null) _onNewMessage(data);
          break;
        case 'message-sent':
          if (_messageProvider != null && _currentUserId != null) _onMessageSent(data);
          break;
        case 'typing-indicator':
          if (_messageProvider != null && _currentUserId != null) _onTypingIndicator(data);
          break;
        case 'recording-indicator':
          if (_messageProvider != null && _currentUserId != null) _onRecordingIndicator(data);
          break;
        case 'user-status':
          if (_messageProvider != null) _onUserStatus(data);
          break;
        case 'messages-read':
          if (_messageProvider != null) _onMessagesRead(data);
          break;

        // ── Rendez-vous ───────────────────────────────────────────────
        case 'rdv-pending':
        case 'rdv-confirmed':
        case 'rdv-cancelled':
        case 'rdv-completed':
          _onRdvNotification(data, event.eventName);
          break;

        case 'entreprise-approved':
        case 'entreprise-rejected':
        case 'new-entreprise-pending':
          debugPrint('[Pusher] Notif entreprise: ${event.eventName}');
          break;

        default:
          if (_messageProvider != null &&
              _currentUserId != null &&
              data.containsKey('conversation_id')) {
            _onNewMessage(data);
          }
      }
    } catch (e) {
      debugPrint('[Pusher] Erreur traitement ${event.eventName}: $e');
    }
  }

  void _onNewMessage(Map<String, dynamic> data) {
    final Map<String, dynamic> msgData;
    if (data['message'] is Map) {
      msgData = Map<String, dynamic>.from(data['message'] as Map);
    } else {
      msgData = Map<String, dynamic>.from(data);
    }

    final convId   = (data['conversation_id'] ?? msgData['conversation_id'])?.toString() ?? '';
    final senderId = msgData['sender_id']?.toString() ?? '';

    if (convId.isEmpty) return;
    if (senderId == _currentUserId) return;

    final msg = MessageModel.fromJson(msgData, _currentUserId!);
    _messageProvider!.receiveMessage(msg, convId);
  }

  void _onMessageSent(Map<String, dynamic> data) {
    final Map<String, dynamic> msgData;
    if (data['message'] is Map) {
      msgData = Map<String, dynamic>.from(data['message'] as Map);
    } else {
      msgData = Map<String, dynamic>.from(data);
    }

    final convId   = msgData['conversation_id']?.toString() ?? '';
    final senderId = msgData['sender_id']?.toString() ?? '';

    if (convId.isEmpty || senderId != _currentUserId) return;
    _messageProvider!.confirmMessage(msgData, convId, _currentUserId!);
  }

  void _onTypingIndicator(Map<String, dynamic> data) {
    final userId   = data['user_id']?.toString();
    final convId   = data['conversation_id']?.toString() ?? '';
    final isTyping = data['is_typing'] == true;
    if (userId == null || userId == _currentUserId || convId.isEmpty) return;
    _messageProvider!.setTypingIndicator(convId, userId, isTyping);
  }

  void _onRecordingIndicator(Map<String, dynamic> data) {
    final userId      = data['user_id']?.toString();
    final convId      = data['conversation_id']?.toString() ?? '';
    final isRecording = data['is_recording'] == true;
    if (userId == null || userId == _currentUserId || convId.isEmpty) return;
    _messageProvider!.setRecordingIndicator(convId, userId, isRecording);
  }

  void _onUserStatus(Map<String, dynamic> data) {
    final userId   = data['user_id']?.toString();
    final isOnline = data['is_online'] == true;
    if (userId == null) return;

    DateTime? lastSeen;
    final raw = data['last_seen'] ?? data['last_seen_at'];
    if (raw != null) lastSeen = DateTime.tryParse(raw.toString())?.toLocal();

    _messageProvider!.updateUserOnlineStatus(userId, isOnline, lastSeen);
  }

  void _onMessagesRead(Map<String, dynamic> data) {
    final convId = data['conversation_id']?.toString();
    if (convId != null && convId.isNotEmpty) {
      _messageProvider!.markMessagesAsReadLocally(convId);
    }
  }


  void _onRdvNotification(Map<String, dynamic> data, String eventName) {
    debugPrint('[Pusher] RDV event: $eventName — rdv_id=${data['rdv_id']}');

    // Mettre à jour la liste des RDV dans le provider
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


      NotificationServiceRef.show(
        id:      rdvId.isNotEmpty
                   ? (rdvId.hashCode + 20000).abs()
                   : DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title:   title,
        body:    body,
        payload: jsonEncode({'type': type, 'rdv_id': rdvId}),
      );
    } catch (e) {
      debugPrint('[Pusher] _showRdvLocalNotification error: $e');
    }
  }

  String _rdvEventTitle(String eventName) {
    switch (eventName) {
      case 'rdv-pending'  : return 'Nouvelle demande de RDV';
      case 'rdv-confirmed': return 'Rendez-vous confirmé';
      case 'rdv-cancelled': return 'Rendez-vous annulé';
      case 'rdv-completed': return 'Rendez-vous terminé';
      default             : return 'Rendez-vous';
    }
  }

  String _rdvEventType(String eventName) {
    switch (eventName) {
      case 'rdv-pending'  : return 'rdv_pending';
      case 'rdv-confirmed': return 'rdv_confirmed';
      case 'rdv-cancelled': return 'rdv_cancelled';
      case 'rdv-completed': return 'rdv_completed';
      default             : return 'rdv_pending';
    }
  }


  Future<void> subscribeToConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    _pendingChannels.add(ch);
    if (_isInitialized && !_subscribedChannels.contains(ch)) await _subscribe(ch);
  }

  Future<void> unsubscribeFromConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    if (_subscribedChannels.contains(ch)) {
      try {
        await _pusher?.unsubscribe(channelName: ch);
        _subscribedChannels.remove(ch);
        _pendingChannels.remove(ch);
      } catch (e) {
        debugPrint('[Pusher] Erreur désabonnement: $e');
      }
    }
  }

  Future<void> reinitialize() async {
    _reconnectTimer?.cancel();
    _isInitialized     = false;
    _isConnecting      = false;
    _reconnectAttempts = 0;
    _currentUserId     = null;
    _subscribedChannels.clear();
    try { await _pusher?.disconnect(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
    await initialize();
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    try {
      if (_isInitialized) {
        await _pusher?.disconnect();
        _isInitialized = false;
        _subscribedChannels.clear();
      }
    } catch (e) {
      debugPrint('[Pusher] disconnect: $e');
    }
  }

  bool get isConnected => _isInitialized;
  String? get currentUserId => _currentUserId;
}

// ── Référence indirecte à NotificationService ────────────────────────────────
class NotificationServiceRef {
  static Future<void> Function({
    required int id,
    required String title,
    required String body,
    String? payload,
  })? _showFn;

  static void register(
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      String? payload,
    }) fn,
  ) {
    _showFn = fn;
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showFn?.call(id: id, title: title, body: body, payload: payload);
  }
}