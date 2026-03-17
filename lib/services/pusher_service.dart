// lib/services/pusher_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VERSION CORRIGÉE — Réception temps réel fiable
// CORRECTIONS:
// 1. Reconnexion automatique après déconnexion (backoff exponentiel)
// 2. Gestion du recording indicator (vocal en cours)
// 3. Logs détaillés pour debugging
// 4. Pas de double souscription / double message
// 5. Préservation du lat/lng et type audio dans confirmMessage
// ═══════════════════════════════════════════════════════════════════════
import 'dart:async';
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

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  PusherChannelsFlutter? _pusher;
  bool    _isInitialized  = false;
  bool    _isConnecting   = false;
  String? _currentUserId;

  // Canaux
  final Set<String> _pendingChannels    = {};
  final Set<String> _subscribedChannels = {};

  // Reconnexion
  int    _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectAttempts = 5;

  MessageProvider? _messageProvider;

  void setMessageProvider(MessageProvider provider) {
    _messageProvider = provider;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INITIALISATION
  // ═══════════════════════════════════════════════════════════════════
  Future<void> initialize() async {
    if (_isConnecting) {
      debugPrint('[Pusher] Déjà en cours de connexion, ignoré');
      return;
    }
    if (_isInitialized) {
      debugPrint('[Pusher] Déjà initialisé, souscription des canaux en attente');
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
        debugPrint('[Pusher] userId null → abandon');
        _isConnecting = false;
        return;
      }
      debugPrint('[Pusher] UserId = $_currentUserId');

      // Canal utilisateur toujours souscrit
      _pendingChannels.add('private-user.$_currentUserId');

      _pusher = PusherChannelsFlutter.getInstance();

      await _pusher!.init(
        apiKey:  'cab84ca4d5eac6def57e',
        cluster: 'eu',
        onConnectionStateChange: (String cur, String prev) {
          debugPrint('[Pusher] État: $prev → $cur');
          if (cur == 'CONNECTED') {
            _isInitialized     = true;
            _isConnecting      = false;
            _reconnectAttempts = 0;
            _reconnectTimer?.cancel();
            _subscribeAllPending();
          } else if (cur == 'DISCONNECTED' || cur == 'FAILED') {
            _isInitialized = false;
            _subscribedChannels.clear();
            if (cur == 'FAILED') {
              _scheduleReconnect();
            }
          }
        },
        onError: (String msg, int? code, dynamic err) {
          debugPrint('[Pusher] Erreur: $msg (code: $code)');
          _isInitialized = false;
          _isConnecting  = false;
          _scheduleReconnect();
        },
        onEvent: (dynamic event) {
          if (event is PusherEvent) _onEvent(event);
        },
        onAuthorizer: (String channelName, String socketId, dynamic options) async {
          return await _authorize(channelName, socketId);
        },
      );

      await _pusher!.connect();
    } catch (e) {
      debugPrint('[Pusher] init error: $e');
      _isInitialized = false;
      _isConnecting  = false;
      _scheduleReconnect();
    }
  }

  // ── Reconnexion avec backoff exponentiel ──────────────────────────
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[Pusher] Max tentatives atteint, reconnexion abandonnée');
      return;
    }
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (2 << _reconnectAttempts).clamp(2, 30));
    _reconnectAttempts++;
    debugPrint('[Pusher] Reconnexion dans ${delay.inSeconds}s (tentative $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () async {
      if (!_isInitialized && !_isConnecting) {
        await initialize();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  AUTORISATION BEARER
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
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: 'socket_id=$socketId&channel_name=$channelName',
      ).timeout(const Duration(seconds: 10));

      debugPrint('[Pusher] Auth ${resp.statusCode} pour $channelName');

      if (resp.body.isEmpty) {
        debugPrint('[Pusher] Auth: réponse vide pour $channelName');
        return null;
      }

      try {
        final decoded = jsonDecode(resp.body);
        if (resp.statusCode == 200) {
          debugPrint('[Pusher] Auth OK: $channelName');
          return decoded;
        }
        debugPrint('[Pusher] Auth refusée: $channelName → ${resp.body}');
      } catch (parseErr) {
        debugPrint('[Pusher] Auth parse error: $parseErr — body="${resp.body}"');
      }
    } catch (e) {
      debugPrint('[Pusher] Auth network error: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SOUSCRIPTION AUX CANAUX
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
    if (!_isInitialized) {
      debugPrint('[Pusher] Pas initialisé, $channelName mis en attente');
      _pendingChannels.add(channelName);
      return;
    }
    if (_subscribedChannels.contains(channelName)) {
      debugPrint('[Pusher] Déjà souscrit: $channelName');
      return;
    }
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
  //  GESTION DES ÉVÉNEMENTS PUSHER
  // ═══════════════════════════════════════════════════════════════════
  void _onEvent(PusherEvent event) {
    if (event.eventName.startsWith('pusher')) return; // Events système
    
    try {
      if (event.data == null || event.data!.isEmpty) return;
      final data = jsonDecode(event.data!) as Map<String, dynamic>;
      debugPrint('[Pusher] ← Événement: ${event.eventName} sur ${event.channelName}');
      if (_messageProvider == null || _currentUserId == null) {
        debugPrint('[Pusher] Provider ou userId null, événement ignoré');
        return;
      }

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
        case 'recording-indicator':
          _onRecording(data);
          break;
        case 'user-status':
          _onUserStatus(data);
          break;
        case 'messages-read':
          _onMessagesRead(data);
          break;
        // Notifications Laravel broadcast
        case 'new-message': // doublon intentionnel pour Notification
        case 'Illuminate\\Notifications\\Events\\BroadcastNotificationCreated':
          _onBroadcastNotification(data);
          break;
        default:
          debugPrint('[Pusher] Événement non géré: ${event.eventName}');
      }
    } catch (e) {
      debugPrint('[Pusher] Erreur traitement event ${event.eventName}: $e');
    }
  }

  // ── Nouveau message reçu ─────────────────────────────────────────
  void _onNewMessage(Map<String, dynamic> data) {
    debugPrint('[Pusher] new-message reçu: $data');

    // Le message peut être dans data['message'] ou directement dans data
    final msgData = (data['message'] is Map)
        ? Map<String, dynamic>.from(data['message'] as Map)
        : Map<String, dynamic>.from(data);

    final convId = data['conversation_id']?.toString() ??
        msgData['conversation_id']?.toString() ?? '';
    
    if (convId.isEmpty) {
      debugPrint('[Pusher] new-message: conversation_id manquant');
      return;
    }

    final senderId = msgData['sender_id']?.toString() ?? '';
    
    // Ne pas ajouter ses propres messages (déjà ajoutés localement)
    if (senderId == _currentUserId) {
      debugPrint('[Pusher] new-message: message de soi-même, ignoré');
      return;
    }

    final msg = MessageModel.fromJson(msgData, _currentUserId!);
    debugPrint('[Pusher] new-message: ajout du message ${msg.id} dans conv $convId');
    _messageProvider!.receiveMessage(msg, convId);
  }

  // ── Confirmation d'envoi (message-sent = confirmation serveur) ────
  void _onMessageSent(Map<String, dynamic> data) {
    final msgData = (data['message'] is Map)
        ? Map<String, dynamic>.from(data['message'] as Map)
        : Map<String, dynamic>.from(data);
    
    final convId = msgData['conversation_id']?.toString() ?? '';
    if (convId.isEmpty) return;

    final senderId = msgData['sender_id']?.toString() ?? '';
    if (senderId != _currentUserId) return; // Pas notre message

    debugPrint('[Pusher] message-sent: confirmation pour conv $convId');
    _messageProvider!.confirmMessage(msgData, convId, _currentUserId!);
  }

  // ── Indicateur de frappe ──────────────────────────────────────────
  void _onTyping(Map<String, dynamic> data) {
    final userId   = data['user_id']?.toString();
    final isTyping = data['is_typing'] == true;
    final convId   = data['conversation_id']?.toString() ?? '';
    
    if (userId == null || userId == _currentUserId || convId.isEmpty) return;
    debugPrint('[Pusher] typing-indicator: user=$userId, isTyping=$isTyping, conv=$convId');
    _messageProvider!.setTypingIndicator(convId, userId, isTyping);
  }

  // ── Indicateur d'enregistrement vocal ────────────────────────────
  void _onRecording(Map<String, dynamic> data) {
    final userId    = data['user_id']?.toString();
    final isRecording = data['is_recording'] == true;
    final convId    = data['conversation_id']?.toString() ?? '';
    
    if (userId == null || userId == _currentUserId || convId.isEmpty) return;
    debugPrint('[Pusher] recording-indicator: user=$userId, isRecording=$isRecording, conv=$convId');
    _messageProvider!.setRecordingIndicator(convId, userId, isRecording);
  }

  // ── Statut en ligne ───────────────────────────────────────────────
  void _onUserStatus(Map<String, dynamic> data) {
    final userId   = data['user_id']?.toString();
    final isOnline = data['is_online'] == true;
    if (userId == null) return;
    
    DateTime? lastSeen;
    final raw = data['last_seen'] ?? data['last_seen_at'];
    if (raw != null) lastSeen = DateTime.tryParse(raw.toString())?.toLocal();
    
    debugPrint('[Pusher] user-status: user=$userId, online=$isOnline');
    _messageProvider!.updateUserOnlineStatus(userId, isOnline, lastSeen);
  }

  // ── Messages lus ─────────────────────────────────────────────────
  void _onMessagesRead(Map<String, dynamic> data) {
    final convId = data['conversation_id']?.toString();
    if (convId != null) {
      debugPrint('[Pusher] messages-read: conv=$convId');
      _messageProvider!.markMessagesAsReadLocally(convId);
    }
  }

  // ── Notification broadcast Laravel ───────────────────────────────
  void _onBroadcastNotification(Map<String, dynamic> data) {
    final type   = data['type'] as String? ?? '';
    final convId = data['conversation_id']?.toString();
    
    if (type == 'message' && convId != null) {
      debugPrint('[Pusher] broadcast notification message: conv=$convId');
      // La notification FCM s'occupe de l'affichage
      // On recharge juste la liste des conversations
      _messageProvider!.loadConversations();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  API PUBLIQUE
  // ═══════════════════════════════════════════════════════════════════

  /// Souscrire à une conversation spécifique
  Future<void> subscribeToConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    _pendingChannels.add(ch);
    if (_isInitialized && !_subscribedChannels.contains(ch)) {
      await _subscribe(ch);
    }
  }

  /// Se désabonner d'une conversation
  Future<void> unsubscribeFromConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    if (_subscribedChannels.contains(ch)) {
      try {
        await _pusher?.unsubscribe(channelName: ch);
        _subscribedChannels.remove(ch);
        _pendingChannels.remove(ch);
        debugPrint('[Pusher] Désabonné: $ch');
      } catch (e) {
        debugPrint('[Pusher] Erreur désabonnement $ch: $e');
      }
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    try {
      if (_isInitialized) {
        await _pusher?.disconnect();
        _isInitialized = false;
        _subscribedChannels.clear();
        debugPrint('[Pusher] Déconnecté');
      }
    } catch (e) {
      debugPrint('[Pusher] disconnect: $e');
    }
  }

  Future<void> reinitialize() async {
    debugPrint('[Pusher] Réinitialisation...');
    _reconnectTimer?.cancel();
    _isInitialized     = false;
    _isConnecting      = false;
    _reconnectAttempts = 0;
    _subscribedChannels.clear();
    _currentUserId = null;
    
    try { await _pusher?.disconnect(); } catch (_) {}
    
    await Future.delayed(const Duration(milliseconds: 500));
    await initialize();
  }

  bool get isConnected => _isInitialized;
}