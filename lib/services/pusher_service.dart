import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';
import 'notification_service.dart';
import 'notification_prefs_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
//  MODÈLES D'ÉVÉNEMENTS — typés, immuables, rapides
// ──────────────────────────────────────────────────────────────────────────────

class WsMessage {
  final String convId;
  final Map<String, dynamic> data;
  final String? senderName;
  final String? senderPhoto;
  const WsMessage(this.convId, this.data,
      {this.senderName, this.senderPhoto});
}

class WsTyping {
  final String convId;
  final String userId;
  final bool isTyping;
  const WsTyping(this.convId, this.userId, this.isTyping);
}

class WsRecording {
  final String convId;
  final String userId;
  final bool isRecording;
  const WsRecording(this.convId, this.userId, this.isRecording);
}

class WsUserStatus {
  final String userId;
  final bool isOnline;
  final DateTime? lastSeen;
  const WsUserStatus(this.userId, this.isOnline, this.lastSeen);
}

class WsMessagesRead {
  final String convId;
  final String readByUserId;
  const WsMessagesRead(this.convId, this.readByUserId);
}

class WsMessageConfirm {
  final String convId;
  final Map<String, dynamic> data;
  const WsMessageConfirm(this.convId, this.data);
}

class WsConversationDeleted {
  final String convId;
  const WsConversationDeleted(this.convId);
}

// ──────────────────────────────────────────────────────────────────────────────
//  PUSHER SERVICE — WebSocket pur, zéro polling
// ──────────────────────────────────────────────────────────────────────────────

class PusherService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final PusherService _i = PusherService._();
  factory PusherService() => _i;
  PusherService._();

  static const _ao = AndroidOptions(encryptedSharedPreferences: true);
  static const _io = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _store = const FlutterSecureStorage(aOptions: _ao, iOptions: _io);

  // ── Instance Pusher ────────────────────────────────────────────────────────
  PusherChannelsFlutter? _pusher;

  // ── État connexion ─────────────────────────────────────────────────────────
  bool    _connected    = false;
  bool    _connecting   = false;
  String? _userId;

  bool get isConnected => _connected;

  /// Compatibilité — les événements RDV arrivent désormais via [onRdvEvent].
  /// Brancher le RendezVousProvider sur ce stream dans splash_screen.
  /// Cette méthode est conservée pour éviter les erreurs de compilation.
  void setRendezVousProvider(dynamic _) {
    // no-op : voir onRdvEvent
  }

  // ── Canaux ─────────────────────────────────────────────────────────────────
  final Set<String> _subscribed = {};
  final Set<String> _pending    = {};

  // ── Reconnexion exponentielle ─────────────────────────────────────────────
  int    _attempt    = 0;
  Timer? _retryTimer;
  static const _maxAttempts = 15;

  // ── Streams publics (broadcast — plusieurs listeners possibles) ────────────
  final _msgCtrl     = StreamController<WsMessage>.broadcast();
  final _confirmCtrl = StreamController<WsMessageConfirm>.broadcast();
  final _typingCtrl  = StreamController<WsTyping>.broadcast();
  final _recCtrl     = StreamController<WsRecording>.broadcast();
  final _statusCtrl  = StreamController<WsUserStatus>.broadcast();
  final _readCtrl    = StreamController<WsMessagesRead>.broadcast();
  final _delConvCtrl = StreamController<WsConversationDeleted>.broadcast();
  // Stream RDV — map brute car structure variable selon le backend
  final _rdvCtrl     = StreamController<Map<String, dynamic>>.broadcast();

  Stream<WsMessage>             get onMessage          => _msgCtrl.stream;
  Stream<WsMessageConfirm>      get onMessageConfirm   => _confirmCtrl.stream;
  Stream<WsTyping>              get onTyping           => _typingCtrl.stream;
  Stream<WsRecording>           get onRecording        => _recCtrl.stream;
  Stream<WsUserStatus>          get onUserStatus       => _statusCtrl.stream;
  Stream<WsMessagesRead>        get onMessagesRead     => _readCtrl.stream;
  Stream<WsConversationDeleted> get onConversationDeleted => _delConvCtrl.stream;
  /// Stream brut pour les événements RDV — écouter depuis RendezVousProvider
  Stream<Map<String, dynamic>>  get onRdvEvent         => _rdvCtrl.stream;

  // ── Indicateurs typing/recording auto-expiry ──────────────────────────────
  final Map<String, Timer> _typingExpiry   = {};
  final Map<String, Timer> _recordExpiry   = {};

  // ────────────────────────────────────────────────────────────────────────────
  //  INIT & CONNEXION
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_connecting || _connected) {
      if (_connected) _flushPending();
      return;
    }
    _connecting = true;

    try {
      final raw = await _store.read(key: 'user_data');
      if (raw == null || raw.isEmpty) {
        _connecting = false;
        return;
      }
      _userId = (jsonDecode(raw) as Map<String, dynamic>)['id']?.toString();
      if (_userId == null) { _connecting = false; return; }

      // Canal utilisateur toujours pré-requis
      _pending.add('private-user.$_userId');

      _pusher = PusherChannelsFlutter.getInstance();
      await _pusher!.init(
        apiKey              : AppConstants.pusherKey,
        cluster             : AppConstants.pusherCluster,
        onConnectionStateChange: _onState,
        onError             : _onError,
        onEvent             : (e) { _dispatch(e); },
        onAuthorizer        : (ch, sid, _) => _auth(ch, sid),
      );
      await _pusher!.connect();
    } catch (e) {
      debugPrint('[WS] init error: $e');
      _connecting = false;
      _scheduleRetry();
    }
  }

  // ── Changement d'état Pusher ───────────────────────────────────────────────

  void _onState(String cur, String prev) {
    debugPrint('[WS] $prev → $cur');
    switch (cur) {
      case 'CONNECTED':
        _connected  = true;
        _connecting = false;
        _attempt    = 0;
        _retryTimer?.cancel();
        _flushPending();
        break;
      case 'DISCONNECTED':
        _connected = false;
        _subscribed.clear();
        _clearIndicators();
        break;
      case 'FAILED':
        _connected  = false;
        _connecting = false;
        _subscribed.clear();
        _clearIndicators();
        _scheduleRetry();
        break;
    }
  }

  void _onError(String msg, int? code, dynamic err) {
    debugPrint('[WS] error $code: $msg');
    _connected  = false;
    _connecting = false;
    _scheduleRetry();
  }

  // ── Reconnexion exponentielle ─────────────────────────────────────────────

  void _scheduleRetry() {
    if (_attempt >= _maxAttempts) return;
    _retryTimer?.cancel();
    // backoff : 1s, 2s, 4s, 8s, 16s, 30s (max)
    final secs = (_attempt < 5) ? (1 << _attempt) : 30;
    _attempt++;
    debugPrint('[WS] retry #$_attempt in ${secs}s');
    _retryTimer = Timer(Duration(seconds: secs.clamp(1, 30)), () {
      if (!_connected && !_connecting) initialize();
    });
  }

  // ── Reconnexion forcée (depuis ConnectivityService) ───────────────────────

  Future<void> reconnect() async {
    _retryTimer?.cancel();
    _attempt    = 0;
    _connected  = false;
    _connecting = false;
    _subscribed.clear();
    try { await _pusher?.disconnect(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));
    await initialize();
  }

  // ── Auth canal privé ───────────────────────────────────────────────────────

  Future<dynamic> _auth(String channel, String socketId) async {
    try {
      final token = await _store.read(key: 'auth_token');
      if (token == null || token.isEmpty) return null;

      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/pusher/auth'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/x-www-form-urlencoded',
          'Accept'       : 'application/json',
        },
        body: 'socket_id=$socketId&channel_name=$channel',
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final d = jsonDecode(resp.body);
        if (d is Map && d.containsKey('auth')) return d;
      }
    } catch (e) {
      debugPrint('[WS] auth error: $e');
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  CANAUX
  // ────────────────────────────────────────────────────────────────────────────

  void _flushPending() {
    for (final ch in Set.of(_pending)) {
      if (!_subscribed.contains(ch)) _subscribe(ch);
    }
  }

  Future<void> _subscribe(String ch) async {
    if (!_connected) { _pending.add(ch); return; }
    if (_subscribed.contains(ch)) return;
    try {
      await _pusher?.subscribe(
        channelName: ch,
        onEvent: (e) { _dispatch(e); },
      );
      _subscribed.add(ch);
      debugPrint('[WS] ✓ $ch');
    } catch (e) {
      debugPrint('[WS] subscribe error $ch: $e');
    }
  }

  /// Appeler à l'ouverture d'un ChatScreen
  Future<void> subscribeToConversation(String convId) async {
    final ch = 'private-conversation.$convId';
    _pending.add(ch);
    await _subscribe(ch);
  }

  /// Appeler à la fermeture d'un ChatScreen
  Future<void> unsubscribeFromConversation(String convId) async {
    final ch = 'private-conversation.$convId';
    _pending.remove(ch);
    if (!_subscribed.contains(ch)) return;
    try {
      await _pusher?.unsubscribe(channelName: ch);
      _subscribed.remove(ch);
    } catch (_) {}
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  DISPATCH D'ÉVÉNEMENTS
  // ────────────────────────────────────────────────────────────────────────────

  void _dispatch(dynamic event) {
    if (event is! PusherEvent) return;
    final e = event;
    if (e.eventName.startsWith('pusher')) return;
    if (e.data == null || e.data!.isEmpty)  return;

    Map<String, dynamic> d;
    try {
      d = jsonDecode(e.data!) as Map<String, dynamic>;
    } catch (_) { return; }

    debugPrint('[WS] ← ${e.eventName}  ch=${e.channelName}');

    switch (e.eventName) {
      case 'new-message':     _handleNewMessage(d); break;
      case 'message-sent':    _handleMessageSent(d); break;
      case 'typing-indicator':_handleTyping(d); break;
      case 'recording-indicator': _handleRecording(d); break;
      case 'user-status':     _handleUserStatus(d); break;
      case 'messages-read':   _handleMessagesRead(d); break;
      case 'conversation-deleted': _handleConvDeleted(d); break;
      case 'rdv-pending':
      case 'rdv-confirmed':
      case 'rdv-cancelled':
      case 'rdv-completed':
        _rdvCtrl.add({...d, '_event': e.eventName});
        break;
      default: break; // Ignorer les événements inconnus (plus de fallback permissif)
    }
  }

  // ── Nouveau message reçu ───────────────────────────────────────────────────

  void _handleNewMessage(Map<String, dynamic> d) {
    final msgData = d['message'] is Map
        ? Map<String, dynamic>.from(d['message'] as Map)
        : d;

    final convId   = (d['conversation_id'] ?? msgData['conversation_id'])?.toString() ?? '';
    final senderId = msgData['sender_id']?.toString() ?? '';

    if (convId.isEmpty) return;
    if (senderId == _userId) return; // Nos propres messages arrivent via message-sent

    _msgCtrl.add(WsMessage(
      convId,
      msgData,
      senderName : d['sender_name']?.toString(),
      senderPhoto: d['sender_photo']?.toString(),
    ));

    // Notification locale
    _showMsgNotif(d, msgData, convId, senderId);
  }

  // ── Confirmation message envoyé (canal conversation) ──────────────────────

  void _handleMessageSent(Map<String, dynamic> d) {
    final msgData = d['message'] is Map
        ? Map<String, dynamic>.from(d['message'] as Map)
        : d;

    final convId   = msgData['conversation_id']?.toString() ?? '';
    final senderId = msgData['sender_id']?.toString() ?? '';

    if (convId.isEmpty) return;
    // Seulement nos propres confirmations
    if (senderId != _userId) return;

    _confirmCtrl.add(WsMessageConfirm(convId, msgData));
  }

  // ── Typing (avec auto-expiry 4s comme WhatsApp) ───────────────────────────

  void _handleTyping(Map<String, dynamic> d) {
    final userId   = d['user_id']?.toString();
    final convId   = d['conversation_id']?.toString() ?? '';
    final isTyping = d['is_typing'] == true;

    if (userId == null || userId == _userId || convId.isEmpty) return;

    _typingCtrl.add(WsTyping(convId, userId, isTyping));

    final key = '$convId:$userId';
    _typingExpiry[key]?.cancel();

    if (isTyping) {
      // Auto-stop si pas de refresh pendant 4s
      _typingExpiry[key] = Timer(const Duration(seconds: 4), () {
        _typingCtrl.add(WsTyping(convId, userId, false));
        _typingExpiry.remove(key);
      });
    } else {
      _typingExpiry.remove(key);
    }
  }

  // ── Recording (avec auto-expiry 60s) ──────────────────────────────────────

  void _handleRecording(Map<String, dynamic> d) {
    final userId      = d['user_id']?.toString();
    final convId      = d['conversation_id']?.toString() ?? '';
    final isRecording = d['is_recording'] == true;

    if (userId == null || userId == _userId || convId.isEmpty) return;

    _recCtrl.add(WsRecording(convId, userId, isRecording));

    final key = '$convId:$userId';
    _recordExpiry[key]?.cancel();

    if (isRecording) {
      _recordExpiry[key] = Timer(const Duration(seconds: 60), () {
        _recCtrl.add(WsRecording(convId, userId, false));
        _recordExpiry.remove(key);
      });
    } else {
      _recordExpiry.remove(key);
    }
  }

  // ── Statut en ligne ────────────────────────────────────────────────────────

  void _handleUserStatus(Map<String, dynamic> d) {
    final userId   = d['user_id']?.toString();
    if (userId == null) return;

    final isOnline = d['is_online'] == true;
    DateTime? lastSeen;
    final raw = d['last_seen'] ?? d['last_seen_at'];
    if (raw != null) lastSeen = DateTime.tryParse(raw.toString())?.toLocal();

    _statusCtrl.add(WsUserStatus(userId, isOnline, lastSeen));
  }

  // ── Messages lus ──────────────────────────────────────────────────────────

  void _handleMessagesRead(Map<String, dynamic> d) {
    final convId     = d['conversation_id']?.toString() ?? '';
    final readByUser = d['user_id']?.toString() ?? '';
    if (convId.isEmpty) return;
    _readCtrl.add(WsMessagesRead(convId, readByUser));
  }

  // ── Conversation supprimée ─────────────────────────────────────────────────

  void _handleConvDeleted(Map<String, dynamic> d) {
    final convId = d['conversation_id']?.toString() ?? '';
    if (convId.isEmpty) return;
    _delConvCtrl.add(WsConversationDeleted(convId));
    unsubscribeFromConversation(convId);
  }

  // ── Notification locale ────────────────────────────────────────────────────

  void _showMsgNotif(
    Map<String, dynamic> d,
    Map<String, dynamic> msgData,
    String convId,
    String senderId,
  ) {
    NotificationPrefsService.canShow(type: 'message').then((ok) {
      if (!ok) return;
      final type    = msgData['type']?.toString() ?? 'text';
      final content = msgData['content']?.toString() ?? '';
      final body    = content.isNotEmpty ? content : _notifBody(type);
      NotificationService().showMessageNotification(
        senderName    : d['sender_name']?.toString() ?? 'Message',
        messageBody   : body,
        conversationId: convId,
        senderPhoto   : d['sender_photo']?.toString(),
        senderId      : senderId,
      );
    });
  }

  String _notifBody(String type) {
    switch (type) {
      case 'image':    return '📷 Photo';
      case 'video':    return '🎥 Vidéo';
      case 'vocal':    return '🎤 Message vocal';
      case 'document': return '📎 Document';
      case 'location': return '📍 Localisation';
      default:         return 'Nouveau message';
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  NETTOYAGE
  // ────────────────────────────────────────────────────────────────────────────

  void _clearIndicators() {
    for (final t in _typingExpiry.values)  t.cancel();
    for (final t in _recordExpiry.values)  t.cancel();
    _typingExpiry.clear();
    _recordExpiry.clear();
  }

  Future<void> reinitialize() async {
    _retryTimer?.cancel();
    _clearIndicators();
    _connected  = false;
    _connecting = false;
    _attempt    = 0;
    _userId     = null;
    _subscribed.clear();
    try { await _pusher?.disconnect(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));
    await initialize();
  }

  Future<void> disconnect() async {
    _retryTimer?.cancel();
    _clearIndicators();
    for (final ch in Set.of(_subscribed)) {
      try { await _pusher?.unsubscribe(channelName: ch); } catch (_) {}
    }
    _subscribed.clear();
    try { await _pusher?.disconnect(); } catch (_) {}
    _connected  = false;
    _connecting = false;
  }

  void dispose() {
    _msgCtrl.close();
    _confirmCtrl.close();
    _typingCtrl.close();
    _recCtrl.close();
    _statusCtrl.close();
    _readCtrl.close();
    _delConvCtrl.close();
    _rdvCtrl.close();
    disconnect();
  }
}
