
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

  // Gestion des canaux
  final Set<String> _pendingChannels    = {};
  final Set<String> _subscribedChannels = {};

  // Reconnexion automatique
  int    _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectAttempts = 8;

  // Référence au provider (injectée depuis main.dart ou splash_screen)
  MessageProvider? _messageProvider;

  void setMessageProvider(MessageProvider provider) {
    _messageProvider = provider;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INITIALISATION
  // ═══════════════════════════════════════════════════════════════════
  Future<void> initialize() async {
    if (_isConnecting) {
      debugPrint('[Pusher] Connexion déjà en cours');
      return;
    }
    if (_isInitialized) {
      await _subscribeAllPending();
      return;
    }

    _isConnecting = true;
    debugPrint('[Pusher] Initialisation...');

    try {
      // Charger le userId
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

      // Ajouter le canal utilisateur (toujours souscrit)
      _pendingChannels.add('private-user.$_currentUserId');

      _pusher = PusherChannelsFlutter.getInstance();

      await _pusher!.init(
        // ⚠️ Remplacez par votre clé Pusher réelle depuis .env
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

        // Autorisation des canaux privés via le backend Laravel
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

  // ─── Reconnexion avec backoff exponentiel ──────────────────────────
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[Pusher] Max tentatives atteint, abandon reconnexion');
      return;
    }

    _reconnectTimer?.cancel();
    // Backoff: 2s, 4s, 8s, 16s, 30s, 30s, 30s, 30s
    final seconds = _reconnectAttempts < 4
        ? (2 << _reconnectAttempts)
        : 30;
    final delay = Duration(seconds: seconds);
    _reconnectAttempts++;

    debugPrint(
        '[Pusher] Reconnexion dans ${delay.inSeconds}s (tentative $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () async {
      if (!_isInitialized && !_isConnecting) {
        await initialize();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  AUTORISATION BEARER — Requis pour les canaux privés Pusher
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
          'Content-Type' : 'application/x-www-form-urlencoded',
          'Accept'       : 'application/json',
        },
        body: 'socket_id=$socketId&channel_name=$channelName',
      ).timeout(const Duration(seconds: 10));

      debugPrint('[Pusher] Auth ${resp.statusCode} pour $channelName');

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded.containsKey('auth')) {
          debugPrint('[Pusher] Auth OK: $channelName');
          return decoded;
        }
      }

      debugPrint('[Pusher] Auth refusée: $channelName');
    } catch (e) {
      debugPrint('[Pusher] Auth erreur réseau: $e');
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

  // ═══════════════════════════════════════════════════════════════════
  //  ROUTEUR D'ÉVÉNEMENTS PUSHER
  // ═══════════════════════════════════════════════════════════════════
  void _onEvent(PusherEvent event) {
    // Ignorer les événements système Pusher
    if (event.eventName.startsWith('pusher') ||
        event.eventName.startsWith('pusher_internal')) {
      return;
    }

    if (event.data == null || event.data!.isEmpty) return;

    try {
      final data = jsonDecode(event.data!) as Map<String, dynamic>;

      debugPrint('[Pusher] ← ${event.eventName} sur ${event.channelName}');

      if (_messageProvider == null || _currentUserId == null) {
        debugPrint('[Pusher] Provider null, événement ignoré');
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
          _onTypingIndicator(data);
          break;

        case 'recording-indicator':
          _onRecordingIndicator(data);
          break;

        case 'user-status':
          _onUserStatus(data);
          break;

        case 'messages-read':
          _onMessagesRead(data);
          break;

        default:
          // Notifications Laravel broadcast
          if (data.containsKey('conversation_id')) {
            _onNewMessage(data);
          }
      }
    } catch (e) {
      debugPrint('[Pusher] Erreur traitement ${event.eventName}: $e');
    }
  }

  // ─── NOUVEAU MESSAGE ────────────────────────────────────────────────
  // Appelé quand quelqu'un envoie un message dans une conversation
  // où on est participant.
  void _onNewMessage(Map<String, dynamic> data) {
    // Le message peut être dans data['message'] ou à la racine
    final Map<String, dynamic> msgData;
    if (data['message'] is Map) {
      msgData = Map<String, dynamic>.from(data['message'] as Map);
    } else {
      msgData = Map<String, dynamic>.from(data);
    }

    final convId   = (data['conversation_id'] ?? msgData['conversation_id'])
                        ?.toString() ?? '';
    final senderId = msgData['sender_id']?.toString() ?? '';

    if (convId.isEmpty) {
      debugPrint('[Pusher] new-message: conversation_id manquant');
      return;
    }

    // NE PAS ajouter ses propres messages (déjà ajoutés localement à l'envoi)
    if (senderId == _currentUserId) {
      debugPrint('[Pusher] new-message: message de soi-même, ignoré');
      return;
    }

    final msg = MessageModel.fromJson(msgData, _currentUserId!);
    debugPrint('[Pusher] Nouveau message de $senderId dans conv $convId');
    _messageProvider!.receiveMessage(msg, convId);
  }

  // ─── CONFIRMATION D'ENVOI ───────────────────────────────────────────
  // Confirme qu'un message envoyé par NOUS a bien été reçu par le serveur.
  // Remplace le message temporaire (status='sending') par le message confirmé.
  void _onMessageSent(Map<String, dynamic> data) {
    final Map<String, dynamic> msgData;
    if (data['message'] is Map) {
      msgData = Map<String, dynamic>.from(data['message'] as Map);
    } else {
      msgData = Map<String, dynamic>.from(data);
    }

    final convId   = msgData['conversation_id']?.toString() ?? '';
    final senderId = msgData['sender_id']?.toString() ?? '';

    // Seulement pour nos propres messages
    if (convId.isEmpty || senderId != _currentUserId) return;

    debugPrint('[Pusher] Confirmation message dans conv $convId');
    _messageProvider!.confirmMessage(msgData, convId, _currentUserId!);
  }

  // ─── INDICATEUR "EN TRAIN D'ÉCRIRE" ────────────────────────────────
  // Affiché en temps réel dans l'AppBar du ChatScreen
  void _onTypingIndicator(Map<String, dynamic> data) {
    final userId   = data['user_id']?.toString();
    final convId   = data['conversation_id']?.toString() ?? '';
    final isTyping = data['is_typing'] == true;

    // Ne pas traiter ses propres indicateurs
    if (userId == null || userId == _currentUserId || convId.isEmpty) return;

    debugPrint('[Pusher] Typing: user=$userId, isTyping=$isTyping');
    _messageProvider!.setTypingIndicator(convId, userId, isTyping);
  }

  // ─── INDICATEUR "ENREGISTRE UN VOCAL" ──────────────────────────────
  // Affiché en temps réel dans l'AppBar: "● enregistre un vocal..."
  void _onRecordingIndicator(Map<String, dynamic> data) {
    final userId      = data['user_id']?.toString();
    final convId      = data['conversation_id']?.toString() ?? '';
    final isRecording = data['is_recording'] == true;

    if (userId == null || userId == _currentUserId || convId.isEmpty) return;

    debugPrint('[Pusher] Recording: user=$userId, isRecording=$isRecording');
    _messageProvider!.setRecordingIndicator(convId, userId, isRecording);
  }

  // ─── STATUT EN LIGNE ────────────────────────────────────────────────
  void _onUserStatus(Map<String, dynamic> data) {
    final userId   = data['user_id']?.toString();
    final isOnline = data['is_online'] == true;
    if (userId == null) return;

    DateTime? lastSeen;
    final raw = data['last_seen'] ?? data['last_seen_at'];
    if (raw != null) {
      lastSeen = DateTime.tryParse(raw.toString())?.toLocal();
    }

    _messageProvider!.updateUserOnlineStatus(userId, isOnline, lastSeen);
  }

  // ─── MESSAGES LUS ───────────────────────────────────────────────────
  void _onMessagesRead(Map<String, dynamic> data) {
    final convId = data['conversation_id']?.toString();
    if (convId != null && convId.isNotEmpty) {
      _messageProvider!.markMessagesAsReadLocally(convId);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  API PUBLIQUE
  // ═══════════════════════════════════════════════════════════════════

  /// Souscrire au canal d'une conversation (appelé quand on ouvre un chat)
  Future<void> subscribeToConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    _pendingChannels.add(ch);
    if (_isInitialized && !_subscribedChannels.contains(ch)) {
      await _subscribe(ch);
    }
  }

  /// Se désabonner quand on quitte un chat
  Future<void> unsubscribeFromConversation(String conversationId) async {
    final ch = 'private-conversation.$conversationId';
    if (_subscribedChannels.contains(ch)) {
      try {
        await _pusher?.unsubscribe(channelName: ch);
        _subscribedChannels.remove(ch);
        _pendingChannels.remove(ch);
        debugPrint('[Pusher] Désabonné: $ch');
      } catch (e) {
        debugPrint('[Pusher] Erreur désabonnement: $e');
      }
    }
  }

  /// Réinitialisation complète (appelée après connexion/déconnexion)
  Future<void> reinitialize() async {
    debugPrint('[Pusher] Réinitialisation complète...');
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
        debugPrint('[Pusher] Déconnecté proprement');
      }
    } catch (e) {
      debugPrint('[Pusher] disconnect: $e');
    }
  }

  bool get isConnected => _isInitialized;
  String? get currentUserId => _currentUserId;
}