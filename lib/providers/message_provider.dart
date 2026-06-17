import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../services/pusher_service.dart';
import '../services/connectivity_service.dart';
import '../utils/constants.dart';

// ──────────────────────────────────────────────────────────────────────────────
//  MESSAGE PROVIDER — état réactif, 100% WebSocket
// ──────────────────────────────────────────────────────────────────────────────

class MessageProvider extends ChangeNotifier {
  static const _ao = AndroidOptions(encryptedSharedPreferences: true);
  static const _io = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _store = const FlutterSecureStorage(aOptions: _ao, iOptions: _io);

  final PusherService      _ws   = PusherService();
  final ConnectivityService _net = ConnectivityService();

  // ── État ──────────────────────────────────────────────────────────────────
  final Map<String, List<MessageModel>> _messages      = {};
  List<ConversationModel>               _conversations = [];

  // Indicateurs temps réel (clé = convId, valeur = {userId: bool})
  final Map<String, Map<String, bool>> _typing    = {};
  final Map<String, Map<String, bool>> _recording = {};

  // Présence
  final Map<String, bool>      _online   = {};
  final Map<String, DateTime?> _lastSeen = {};

  bool    _loading = false;
  String? _error;
  String? _uid;                  // userId courant
  String? _activeConvId;         // conversation ouverte à l'écran

  // ── Souscriptions WebSocket ────────────────────────────────────────────────
  final List<StreamSubscription> _subs = [];

  // ── Ping "en ligne" ────────────────────────────────────────────────────────
  Timer? _pingTimer;
  // Délai de debounce pour notifyListeners groupés (évite de rebuild trop souvent)
  Timer? _debounce;

  // ── Getters ───────────────────────────────────────────────────────────────
  bool                 get isLoading         => _loading;
  String?              get error             => _error;
  String?              get currentUserId     => _uid;
  bool                 get isRealtimeConnected => _ws.isConnected;
  String?              get activeConversationId => _activeConvId;
  List<ConversationModel> get conversations  => _conversations;

  int get totalUnreadCount =>
      _conversations.fold(0, (s, c) => s + c.unreadCount);

  List<MessageModel> getMessages(String convId)  => _messages[convId] ?? [];
  bool isUserTyping(String convId, String uid)   => _typing[convId]?[uid] ?? false;
  bool isUserRecording(String convId, String uid) => _recording[convId]?[uid] ?? false;

  bool getUserOnlineStatus(String uid) {
    if (_online.containsKey(uid)) return _online[uid]!;
    final ls = _lastSeen[uid];
    return ls != null && DateTime.now().difference(ls).inMinutes < 5;
  }
  DateTime? getUserLastSeen(String uid) => _lastSeen[uid];

  // ────────────────────────────────────────────────────────────────────────────
  //  INIT
  // ────────────────────────────────────────────────────────────────────────────

  MessageProvider() { _boot(); }

  Future<void> _boot() async {
    await _loadUid();
    if (_uid == null) return;
    await _ws.initialize();
    _listenWs();
    _listenNet();
    _startPing();
  }

  Future<void> _loadUid() async {
    try {
      final raw = await _store.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty) {
        _uid = (jsonDecode(raw) as Map<String, dynamic>)['id']?.toString();
      }
    } catch (e) {
      debugPrint('[MP] loadUid: $e');
    }
  }

  // ── Abonnements aux streams WebSocket ─────────────────────────────────────

  void _listenWs() {
    _subs.addAll([
      _ws.onMessage.listen(_onWsMessage),
      _ws.onMessageConfirm.listen(_onWsConfirm),
      _ws.onTyping.listen(_onWsTyping),
      _ws.onRecording.listen(_onWsRecording),
      _ws.onUserStatus.listen(_onWsUserStatus),
      _ws.onMessagesRead.listen(_onWsMessagesRead),
      _ws.onConversationDeleted.listen(_onWsConvDeleted),
    ]);
  }

  // ── Reconnexion automatique sur retour réseau ──────────────────────────────

  void _listenNet() {
    _subs.add(_net.onConnectivityChanged.listen((online) {
      if (online && !_ws.isConnected) {
        debugPrint('[MP] réseau de retour → reconnexion WS');
        _ws.reconnect();
        notifyListeners(); // met à jour l'icône WiFi
      } else if (!online) {
        notifyListeners();
      }
    }));
  }

  // ── Ping "en ligne" toutes les 3 min (suspendu si hors ligne) ─────────────

  void _startPing() {
    _pingTimer?.cancel();
    _updateOnlineSilent();
    _pingTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (_net.isOnline) _updateOnlineSilent();
    });
  }

  Future<void> _updateOnlineSilent() async {
    try {
      final token = await _getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/update-online-status'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // ── Réinit après login ─────────────────────────────────────────────────────

  Future<void> reinitializeAfterLogin() async {
    for (final s in _subs) { await s.cancel(); }
    _subs.clear();
    await _loadUid();
    if (_uid == null) return;
    await _ws.reinitialize();
    _listenWs();
    _listenNet();
    _startPing();
  }

  /// Conservé pour compatibilité — le ping est géré en interne
  void stopOnlineTimer() => stopOnlinePing();

  void stopOnlinePing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  HANDLERS WEBSOCKET
  // ────────────────────────────────────────────────────────────────────────────

  void _onWsMessage(WsMessage ev) {
    if (_uid == null) return;

    _messages[ev.convId] ??= [];

    // Déduplication
    final exists = _messages[ev.convId]!.any((m) =>
        m.id == ev.data['id']?.toString() ||
        (ev.data['temporary_id'] != null &&
         ev.data['temporary_id'].toString().isNotEmpty &&
         m.temporaryId == ev.data['temporary_id'].toString()));
    if (exists) return;

    final msg = MessageModel.fromJson(ev.data, _uid!);
    _messages[ev.convId]!.add(msg);
    _sortMessages(ev.convId);

    // Conversations
    final idx = _conversations.indexWhere((c) => c.id == ev.convId);
    if (idx != -1) {
      final old = _conversations[idx];
      _conversations[idx] = old.copyWithLastMessage(
        msg,
        unreadCount: old.unreadCount + (_activeConvId == ev.convId ? 0 : 1),
      );
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      // Conversation pas encore chargée
      Future.microtask(loadConversations);
    }

    _notify();
  }

  void _onWsConfirm(WsMessageConfirm ev) {
    if (_uid == null) return;
    final msgs = _messages[ev.convId];
    if (msgs == null) return;

    final tempId = ev.data['temporary_id']?.toString() ?? '';
    final msgId  = ev.data['id']?.toString() ?? '';

    int idx = -1;
    if (tempId.isNotEmpty) {
      idx = msgs.indexWhere((m) => m.temporaryId == tempId || m.id == tempId);
    }
    if (idx == -1 && msgId.isNotEmpty) {
      idx = msgs.indexWhere((m) => m.id == msgId);
    }
    if (idx == -1) return;

    final orig = msgs[idx];
    final d = Map<String, dynamic>.from(ev.data);
    if (orig.latitude  != null) d['latitude']  ??= orig.latitude;
    if (orig.longitude != null) d['longitude'] ??= orig.longitude;
    if (orig.type == 'audio' && d['type'] == 'vocal') d['type'] = 'audio';
    d['is_me']     = true;
    d['sender_id'] ??= _uid;

    msgs[idx] = MessageModel.fromJson(d, _uid!);
    _sortMessages(ev.convId);
    _notify();
  }

  void _onWsTyping(WsTyping ev) {
    _typing[ev.convId] ??= {};
    _typing[ev.convId]![ev.userId] = ev.isTyping;
    _notify();
  }

  void _onWsRecording(WsRecording ev) {
    _recording[ev.convId] ??= {};
    _recording[ev.convId]![ev.userId] = ev.isRecording;
    _notify();
  }

  void _onWsUserStatus(WsUserStatus ev) {
    _online[ev.userId] = ev.isOnline;
    if (ev.lastSeen != null) _lastSeen[ev.userId] = ev.lastSeen;

    // Met à jour l'avatar dans la liste des conversations
    final idx = _conversations.indexWhere((c) => c.otherUser.id == ev.userId);
    if (idx != -1) {
      final old = _conversations[idx];
      _conversations[idx] = old.copyWithOnlineStatus(ev.isOnline, ev.lastSeen);
    }
    _notify();
  }

  void _onWsMessagesRead(WsMessagesRead ev) {
    // L'autre utilisateur a lu nos messages → marquer readAt localement
    final msgs = _messages[ev.convId];
    if (msgs == null) return;
    bool changed = false;
    for (int i = 0; i < msgs.length; i++) {
      if (msgs[i].isMe && msgs[i].readAt == null) {
        msgs[i] = msgs[i].copyWith(readAt: DateTime.now());
        changed = true;
      }
    }
    if (changed) _notify();
  }

  void _onWsConvDeleted(WsConversationDeleted ev) {
    _conversations.removeWhere((c) => c.id == ev.convId);
    _messages.remove(ev.convId);
    _notify();
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  CONVERSATION ACTIVE
  // ────────────────────────────────────────────────────────────────────────────

  void setActiveConversation(String? convId) {
    _activeConvId = convId;
    if (convId != null) _markReadLocally(convId);
  }

  void clearAllIndicators() {
    _typing.clear();
    _recording.clear();
    _notify();
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  CHARGEMENT HTTP (initial uniquement)
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> loadConversations() async {
    _loading = true;
    notifyListeners();
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Non authentifié');
      if (_uid == null) await _loadUid();

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final list = body is List ? body
            : (body is Map ? (body['data'] ?? body['conversations'] ?? []) : []);

        _conversations = (list as List)
            .map((i) => ConversationModel.fromJson(i, _uid ?? ''))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        for (final c in _conversations) {
          _online[c.otherUser.id]   = c.otherUser.isOnline;
          if (c.otherUser.lastSeen != null) _lastSeen[c.otherUser.id] = c.otherUser.lastSeen;
        }
        _error = null;
      } else if (resp.statusCode == 401) {
        _error = 'Session expirée';
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('[MP] loadConversations: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(String convId) async {
    _messages[convId] ??= [];
    if (_uid == null) await _loadUid();

    try {
      final token = await _getToken();
      if (token == null) throw Exception('Non authentifié');

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data    = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawMsgs = data['messages'] ?? data['data'] ?? [];

        _messages[convId] = (rawMsgs as List)
            .map((i) => MessageModel.fromJson(i as Map<String, dynamic>, _uid ?? ''))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Statut en ligne de l'interlocuteur
        final otherData = data['other_user'];
        if (otherData is Map) {
          final otherId = otherData['id']?.toString();
          if (otherId != null && otherId != _uid) _fetchOnlineBg(otherId);
        }

        // Souscrire au canal WebSocket de la conversation
        await _ws.subscribeToConversation(convId);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[MP] loadMessages: $e');
    }
  }

  Future<void> fetchOnlineStatus(String uid) async {
    try {
      final token = await _getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/$uid/online-status'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final d        = jsonDecode(resp.body) as Map<String, dynamic>;
        final isOnline = d['is_online'] == true;
        DateTime? ls;
        final raw = d['last_seen_at'] ?? d['last_seen'];
        if (raw != null) ls = DateTime.tryParse(raw.toString())?.toLocal();

        updateUserOnlineStatus(uid, isOnline || (ls != null && DateTime.now().difference(ls).inMinutes < 5), ls);
      }
    } catch (_) {}
  }

  void _fetchOnlineBg(String uid) => Future.microtask(() => fetchOnlineStatus(uid));

  // ────────────────────────────────────────────────────────────────────────────
  //  ENVOI (Optimistic UI)
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> sendMessage(
    String convId, {
    required String type,
    String?  content,
    String?  filePath,
    double?  latitude,
    double?  longitude,
    String?  replyToId,
  }) async {
    if (_uid == null) await _loadUid();

    String apiType = type;
    if (type == 'audio')    apiType = 'vocal';
    if (type == 'location') apiType = 'text';

    final tempId  = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = MessageModel(
      id            : tempId,
      conversationId: convId,
      senderId      : _uid ?? '',
      content       : content ?? _defaultContent(apiType),
      type          : type,
      fileUrl       : filePath,
      latitude      : latitude,
      longitude     : longitude,
      createdAt     : DateTime.now(),
      isMe          : true,
      status        : 'sending',
      temporaryId   : tempId,
    );

    _messages[convId] ??= [];
    _messages[convId]!.add(tempMsg);
    notifyListeners();

    final token = await _getToken();
    if (token == null) { _markError(convId, tempId); throw Exception('Non authentifié'); }

    Map<String, dynamic>? data;
    Exception? lastErr;

    for (int i = 1; i <= 2; i++) {
      try {
        data = filePath != null
            ? await _sendMultipart(token, convId, apiType, content, filePath,
                lat: latitude, lng: longitude, replyId: replyToId, tmpId: tempId)
            : await _sendJson(token, convId, apiType, content,
                lat: latitude, lng: longitude, replyId: replyToId, tmpId: tempId);
        if (data != null) break;
      } catch (e) {
        lastErr = Exception(e.toString());
        if (i < 2) await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    if (data == null) {
      _markError(convId, tempId);
      throw lastErr ?? Exception("Envoi impossible");
    }

    _applyResponse(data, convId, tempId, originalType: type,
        latitude: latitude, longitude: longitude);
  }

  Future<Map<String, dynamic>?> _sendJson(
    String token, String convId, String apiType, String? content, {
    double? lat, double? lng, String? replyId, String? tmpId,
  }) async {
    final body = <String, dynamic>{
      'type'        : apiType,
      'content'     : content ?? '',
      'temporary_id': tmpId ?? '',
    };
    if (lat    != null) body['latitude']    = lat;
    if (lng    != null) body['longitude']   = lng;
    if (replyId != null) body['reply_to_id'] = replyId;

    final resp = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/send-mobile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type' : 'application/json',
        'Accept'       : 'application/json',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    return _parse(resp);
  }

  Future<Map<String, dynamic>?> _sendMultipart(
    String token, String convId, String apiType, String? content, String filePath, {
    double? lat, double? lng, String? replyId, String? tmpId,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/send-mobile'),
    );
    req.headers['Authorization'] = 'Bearer $token';
    req.headers['Accept']        = 'application/json';
    req.fields['type']           = apiType;
    req.fields['temporary_id']   = tmpId ?? '';
    if (content  != null && content.isNotEmpty)  req.fields['content']      = content;
    if (lat      != null) req.fields['latitude']  = lat.toString();
    if (lng      != null) req.fields['longitude'] = lng.toString();
    if (replyId  != null) req.fields['reply_to_id'] = replyId;
    req.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final resp     = await http.Response.fromStream(streamed);
    return _parse(resp);
  }

  Map<String, dynamic>? _parse(http.Response resp) {
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      try {
        final d = jsonDecode(resp.body);
        if (d is Map<String, dynamic>) {
          if (d.containsKey('data') && d['data'] is Map) return Map.from(d['data'] as Map);
          return d;
        }
      } catch (_) {}
    }
    throw Exception('HTTP ${resp.statusCode}');
  }

  void _applyResponse(
    Map<String, dynamic> data, String convId, String tempId, {
    required String originalType,
    double? latitude,
    double? longitude,
  }) {
    if (latitude  != null) data['latitude']  ??= latitude;
    if (longitude != null) data['longitude'] ??= longitude;
    if (originalType == 'audio' && (data['type'] == 'vocal' || data['type'] == 'text')) {
      data['type'] = 'audio';
    }
    data['is_me']     = true;
    data['sender_id'] ??= _uid;

    final msgs = _messages[convId];
    if (msgs == null) return;

    msgs.removeWhere((m) => m.id == tempId);
    final confirmed = MessageModel.fromJson(data, _uid ?? '');
    msgs.add(confirmed);
    _sortMessages(convId);

    // Mettre à jour aperçu conversation
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      _conversations[idx] = _conversations[idx].copyWithLastMessage(confirmed);
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    _notify();
  }

  void _markError(String convId, String tempId) {
    final msgs = _messages[convId];
    if (msgs == null) return;
    final i = msgs.indexWhere((m) => m.id == tempId);
    if (i != -1) { msgs[i] = msgs[i].copyWith(status: 'error'); _notify(); }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  LIRE / TYPING / RECORDING
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> markConversationAsRead(String convId) async {
    _markReadLocally(convId);
    _clearUnreadBadge(convId);
    try {
      final token = await _getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/mark-read'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void _markReadLocally(String convId) {
    final msgs = _messages[convId];
    if (msgs == null) return;
    bool changed = false;
    for (int i = 0; i < msgs.length; i++) {
      if (!msgs[i].isMe && msgs[i].readAt == null) {
        msgs[i] = msgs[i].copyWith(readAt: DateTime.now());
        changed = true;
      }
    }
    if (changed) _notify();
  }

  void _clearUnreadBadge(String convId) {
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx == -1) return;
    final old = _conversations[idx];
    if (old.unreadCount == 0) return;
    _conversations[idx] = old.copyWithLastMessage(old.lastMessage, unreadCount: 0);
    _notify();
  }

  Future<void> sendTypingIndicator(String convId, bool v) async {
    try {
      final token = await _getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/typing'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_typing': v}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> sendRecordingIndicator(String convId, bool v) async {
    try {
      final token = await _getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/recording'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_recording': v}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // ── Statut en ligne public ─────────────────────────────────────────────────

  void updateUserOnlineStatus(String uid, bool isOnline, DateTime? lastSeen) {
    _online[uid] = isOnline;
    if (lastSeen != null) _lastSeen[uid] = lastSeen;
    final idx = _conversations.indexWhere((c) => c.otherUser.id == uid);
    if (idx != -1) _conversations[idx] = _conversations[idx].copyWithOnlineStatus(isOnline, lastSeen);
    _notify();
  }

  // ── FCM ───────────────────────────────────────────────────────────────────

  Future<void> saveFcmToken(String fcmToken) async {
    try {
      final token = await _getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/fcm-token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
          'Accept'       : 'application/json',
        },
        body: jsonEncode({'fcm_token': fcmToken, 'platform': 'android'}),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String?> _getToken() => _store.read(key: 'auth_token');

  void _sortMessages(String convId) =>
      _messages[convId]?.sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Debounce : regroupe les notifyListeners proches (< 16ms) en un seul
  void _notify() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 16), notifyListeners);
  }

  String _defaultContent(String type) {
    switch (type) {
      case 'image':    return 'Image';
      case 'video':    return 'Vidéo';
      case 'vocal':    return 'Message vocal';
      case 'document': return 'Document';
      default:         return '';
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _debounce?.cancel();
    for (final s in _subs) { s.cancel(); }
    super.dispose();
  }
}
