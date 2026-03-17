// lib/services/pusher_service.dart
// ═══════════════════════════════════════════════════════════════════════
// CORRECTION PRINCIPALE:
// L'erreur "FormatException: Unexpected end of input" venait du fait que
// le backend retourne parfois une réponse vide "" (pas un JSON valide)
// quand l'authentification échoue ou que la connexion est déjà établie.
// On gère maintenant ce cas proprement.
// ═══════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/message_provider.dart';
import '../models/message_model.dart';
import '../utils/constants.dart';

class PusherService {
  static final PusherService _instance = PusherService._internal();
  factory PusherService() => _instance;
  PusherService._internal();

  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  PusherChannelsFlutter? _pusher;
  bool    _isInitialized = false;
  String? _currentUserId;
  bool    _isConnecting  = false;

  final Set<String> _pendingChannels    = {};
  final Set<String> _subscribedChannels = {};

  MessageProvider? _messageProvider;

  void setMessageProvider(MessageProvider provider) {
    _messageProvider = provider;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INITIALISATION
  // ═══════════════════════════════════════════════════════════════════
  Future<void> initialize() async {
    if (_isConnecting) return;
    if (_isInitialized) {
      await _subscribeAllPending();
      return;
    }
    _isConnecting = true;

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
        apiKey:  'cab84ca4d5eac6def57e',
        cluster: 'eu',
        onConnectionStateChange: (String cur, String prev) {
          debugPrint('[Pusher] $prev → $cur');
          if (cur == 'CONNECTED') {
            _isInitialized = true;
            _isConnecting  = false;
            _subscribeAllPending();
          } else if (cur == 'DISCONNECTED' || cur == 'FAILED') {
            _isInitialized = false;
            _subscribedChannels.clear();
          }
        },
        onError: (String msg, int? code, dynamic err) {
          debugPrint('[Pusher] Erreur: $msg (code: $code)');
          _isInitialized = false;
          _isConnecting  = false;
        },
        // ⭐ CORRECTION: void Function(dynamic) obligatoire
        onEvent: (dynamic event) {
          if (event is PusherEvent) _onEvent(event);
        },
        onAuthorizer:
            (String channelName, String socketId, dynamic options) async {
          return await _authorize(channelName, socketId);
        },
      );

      await _pusher!.connect();
    } catch (e) {
      debugPrint('[Pusher] init error: $e');
      _isInitialized = false;
      _isConnecting  = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  AUTHORISATION BEARER — CORRECTION FormatException
  // ═══════════════════════════════════════════════════════════════════
  Future<dynamic> _authorize(String channelName, String socketId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) {
        debugPrint('[Pusher] Auth: token manquant pour $channelName');
        return null;
      }

      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/pusher/auth'),
        headers: {
          'Authorization': 'Bearer $token',
          // ⭐ CORRECTION: Content-Type correct pour Laravel Broadcast::auth()
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        // ⭐ CORRECTION: champs NE doivent PAS être Uri.encodeComponent
        // Laravel Broadcast::auth() lit directement socket_id et channel_name
        body: 'socket_id=$socketId&channel_name=$channelName',
      );

      debugPrint('[Pusher] Auth ${resp.statusCode} pour $channelName');

      // ⭐ CORRECTION CRITIQUE: gérer les réponses vides ou non-JSON
      if (resp.body.isEmpty) {
        debugPrint('[Pusher] Auth: réponse vide pour $channelName');
        return null;
      }

      // Vérifier que c'est du JSON valide avant de parser
      try {
        final decoded = jsonDecode(resp.body);
        if (resp.statusCode == 200) {
          debugPrint('[Pusher] Auth OK: $channelName');
          return decoded;
        }
        debugPrint('[Pusher] Auth refusée: $channelName → ${resp.body}');
      } catch (parseErr) {
        // ⭐ CORRECTION: Ne pas crasher sur FormatException
        debugPrint('[Pusher] Auth parse error pour $channelName: $parseErr');
        debugPrint('[Pusher] Body reçu: "${resp.body}"');
      }
    } catch (e) {
      debugPrint('[Pusher] Auth network error: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SOUSCRIPTION
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _subscribeAllPending() async {
    final todo = Set<String>.from(_pendingChannels);
    for (final ch in todo) {
      if (!_subscribedChannels.contains(ch)) {
        await _subscribe(ch);
      }
    }
  }

  Future<void> _subscribe(String channelName) async {
    if (!_isInitialized || _subscribedChannels.contains(channelName)) return;
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

  // ═══════════════════════════════════════════════════════════════════
  //  GESTION DES ÉVÉNEMENTS
  // ═══════════════════════════════════════════════════════════════════
  void _onEvent(PusherEvent event) {
    try {
      if (event.data == null || event.data!.isEmpty) return;
      final data = jsonDecode(event.data!) as Map<String, dynamic>;
      debugPrint('[Pusher] ← ${event.eventName}');
      if (_messageProvider == null || _currentUserId == null) return;

      switch (event.eventName) {
        case 'new-message':
          _onNewMessage(data);
          break;
        case 'message-sent':
          _onMessageSent(data);
          break;
        case 'typing-indicator':
          _onTyping(data);
          break;
        case 'user-status':
          _onUserStatus(data);
          break;
        case 'messages-read':
          _onMessagesRead(data);
          break;
      }
    } catch (e) {
      debugPrint('[Pusher] Event error: $e');
    }
  }

  void _onNewMessage(Map<String, dynamic> data) {
    final msgData = (data['message'] is Map)
        ? Map<String, dynamic>.from(data['message'] as Map)
        : Map<String, dynamic>.from(data);
    final convId  = data['conversation_id']?.toString() ??
        msgData['conversation_id']?.toString() ?? '';
    if (convId.isEmpty) return;
    if ((msgData['sender_id']?.toString() ?? '') == _currentUserId) return;
    _messageProvider!.receiveMessage(
        MessageModel.fromJson(msgData, _currentUserId!), convId);
  }

  void _onMessageSent(Map<String, dynamic> data) {
    final msgData = (data['message'] is Map)
        ? Map<String, dynamic>.from(data['message'] as Map)
        : Map<String, dynamic>.from(data);
    final convId  = msgData['conversation_id']?.toString() ?? '';
    if (convId.isEmpty) return;
    if ((msgData['sender_id']?.toString() ?? '') != _currentUserId) return;
    _messageProvider!.confirmMessage(msgData, convId, _currentUserId!);
  }

  void _onTyping(Map<String, dynamic> data) {
    final userId = data['user_id']?.toString();
    final isTyping = data['is_typing'] == true;
    final convId   = data['conversation_id']?.toString() ?? '';
    if (userId == null || userId == _currentUserId || convId.isEmpty) return;
    _messageProvider!.setTypingIndicator(convId, userId, isTyping);
  }

  void _onUserStatus(Map<String, dynamic> data) {
    final userId   = data['user_id']?.toString();
    final isOnline = data['is_online'] == true;
    if (userId == null) return;
    DateTime? lastSeen;
    final raw = data['last_seen'];
    if (raw != null) lastSeen = DateTime.tryParse(raw.toString());
    _messageProvider!.updateUserOnlineStatus(userId, isOnline, lastSeen);
  }

  void _onMessagesRead(Map<String, dynamic> data) {
    final convId = data['conversation_id']?.toString();
    if (convId != null) _messageProvider!.markMessagesAsReadLocally(convId);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  API PUBLIQUE
  // ═══════════════════════════════════════════════════════════════════
  Future<void> subscribeToConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    _pendingChannels.add(ch);
    if (_isInitialized && !_subscribedChannels.contains(ch)) {
      await _subscribe(ch);
    }
  }

  Future<void> disconnect() async {
    try {
      if (_isInitialized) {
        await _pusher?.disconnect();
        _isInitialized = false;
        _subscribedChannels.clear();
      }
    } catch (e) { debugPrint('[Pusher] disconnect: $e'); }
  }

  Future<void> reinitialize() async {
    debugPrint('[Pusher] reinitialize...');
    _isInitialized = false;
    _isConnecting  = false;
    _subscribedChannels.clear();
    _currentUserId = null;
    try { await _pusher?.disconnect(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
    await initialize();
  }
}