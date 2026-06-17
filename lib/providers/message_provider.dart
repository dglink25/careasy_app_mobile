import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../services/pusher_service.dart';
import '../services/connectivity_service.dart';
import '../services/chat_local_db.dart';
import '../services/token_cache.dart';
import '../utils/constants.dart';

// ──────────────────────────────────────────────────────────────────────────────
//  MESSAGE PROVIDER — cache-first + WebSocket temps réel
//
//  Stratégie de performance :
//   1. Cache SQLite local  → affichage instantané (0 ms réseau)
//   2. Rafraîchissement silencieux en arrière-plan depuis l'API
//   3. WebSocket Pusher pour les nouveaux messages en temps réel
//   4. Token JWT en cache mémoire (plus de lecture keystore à chaque appel)
//   5. loadConversations() dédupliqué (cooldown 3 s entre deux appels)
//   6. Edit/delete patchent la liste locale sans recharger depuis l'API
//   7. Pagination : 60 messages initiaux + "charger plus" par tranches de 30
// ──────────────────────────────────────────────────────────────────────────────

class MessageProvider extends ChangeNotifier {
  final PusherService       _ws  = PusherService();
  final ConnectivityService _net = ConnectivityService();
  final ChatLocalDb         _db  = ChatLocalDb();
  final TokenCache          _tok = TokenCache();

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
  String? _uid;
  String? _activeConvId;

  // ── Pagination ────────────────────────────────────────────────────────────
  // Conversations pour lesquelles il reste des messages plus anciens à charger
  final Set<String> _hasMoreMessages = {};

  // ── Cooldown loadConversations (évite les appels en rafale) ──────────────
  DateTime? _lastConvLoad;
  static const _convCooldown = Duration(seconds: 3);

  // ── Souscriptions WebSocket ────────────────────────────────────────────────
  final List<StreamSubscription> _subs = [];

  // ── Ping "en ligne" ────────────────────────────────────────────────────────
  Timer? _pingTimer;
  Timer? _debounce;

  // ── Getters ───────────────────────────────────────────────────────────────
  bool                    get isLoading            => _loading;
  String?                 get error                => _error;
  String?                 get currentUserId        => _uid;
  bool                    get isRealtimeConnected  => _ws.isConnected;
  String?                 get activeConversationId => _activeConvId;
  List<ConversationModel> get conversations        => _conversations;

  int get totalUnreadCount =>
      _conversations.fold(0, (s, c) => s + c.unreadCount);

  List<MessageModel> getMessages(String convId)       => _messages[convId] ?? [];
  bool isUserTyping(String convId, String uid)        => _typing[convId]?[uid] ?? false;
  bool isUserRecording(String convId, String uid)     => _recording[convId]?[uid] ?? false;
  bool hasMoreMessages(String convId)                 => _hasMoreMessages.contains(convId);

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
    // Précharger token + userId en mémoire dès le démarrage
    await _tok.preload();
    _uid = await _tok.getUserId();
    if (_uid == null) return;
    await _ws.initialize();
    _listenWs();
    _listenNet();
    _startPing();
  }

  Future<void> _loadUid() async {
    _uid ??= await _tok.getUserId();
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
      final token = await _tok.getToken();
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
    _tok.invalidate();
    await _tok.preload();
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

    // Persister en base locale
    _db.saveMessage(msg);

    // Conversations
    final idx = _conversations.indexWhere((c) => c.id == ev.convId);
    if (idx != -1) {
      final old       = _conversations[idx];
      final newUnread = old.unreadCount + (_activeConvId == ev.convId ? 0 : 1);
      _conversations[idx] = old.copyWithLastMessage(msg, unreadCount: newUnread);
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _db.updateConversationLastMessage(ev.convId, msg, newUnread);
    } else {
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

    final confirmed = MessageModel.fromJson(d, _uid!);
    msgs[idx] = confirmed;
    _sortMessages(ev.convId);

    // Remplacer en base locale (supprime le temp, insère le confirmé)
    if (tempId.isNotEmpty) {
      _db.confirmMessage(tempId, confirmed);
    } else {
      _db.saveMessage(confirmed);
    }

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
    final msgs = _messages[ev.convId];
    if (msgs == null) return;
    bool changed = false;
    for (int i = 0; i < msgs.length; i++) {
      if (msgs[i].isMe && msgs[i].readAt == null) {
        msgs[i] = msgs[i].copyWith(readAt: DateTime.now());
        changed = true;
      }
    }
    if (changed) {
      _db.markSentMessagesRead(ev.convId);
      _notify();
    }
  }

  void _onWsConvDeleted(WsConversationDeleted ev) {
    _conversations.removeWhere((c) => c.id == ev.convId);
    _messages.remove(ev.convId);
    _db.deleteConversation(ev.convId);
    _notify();
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  CONVERSATION ACTIVE
  // ────────────────────────────────────────────────────────────────────────────

  void setActiveConversation(String? convId) {
    _activeConvId = convId;
    if (convId != null) {
      _markReadLocally(convId);
      _db.resetUnreadCount(convId);
    }
  }

  void clearAllIndicators() {
    _typing.clear();
    _recording.clear();
    _notify();
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  CHARGEMENT — stratégie cache-first
  // ────────────────────────────────────────────────────────────────────────────

  /// Charge les conversations.
  /// - Retour immédiat depuis SQLite si disponible (0 ms)
  /// - Rafraîchissement HTTP silencieux en arrière-plan
  /// - Cooldown de 3 s pour éviter les appels en rafale
  Future<void> loadConversations({bool forceRefresh = false}) async {
    // Cooldown : évite 4-5 appels identiques à la suite
    final now = DateTime.now();
    if (!forceRefresh &&
        _lastConvLoad != null &&
        now.difference(_lastConvLoad!) < _convCooldown &&
        _conversations.isNotEmpty) {
      return;
    }
    _lastConvLoad = now;

    await _loadUid();

    // ── 1. Cache local → affichage instantané ──────────────────────────────
    if (_conversations.isEmpty) {
      final cached = await _db.loadConversations(_uid ?? '');
      if (cached.isNotEmpty) {
        _conversations = cached;
        for (final c in _conversations) {
          _online[c.otherUser.id] = c.otherUser.isOnline;
          if (c.otherUser.lastSeen != null) {
            _lastSeen[c.otherUser.id] = c.otherUser.lastSeen;
          }
        }
        notifyListeners(); // affichage immédiat
      }
    }

    // ── 2. Rafraîchissement HTTP en arrière-plan ──────────────────────────
    _loading = _conversations.isEmpty; // spinner seulement si rien en cache
    if (_loading) notifyListeners();

    try {
      final token = await _tok.getToken();
      if (token == null) throw Exception('Non authentifié');

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
          _online[c.otherUser.id] = c.otherUser.isOnline;
          if (c.otherUser.lastSeen != null) {
            _lastSeen[c.otherUser.id] = c.otherUser.lastSeen;
          }
        }
        _error = null;

        // Persister pour la prochaine ouverture
        _db.saveConversations(_conversations);
      } else if (resp.statusCode == 401) {
        _error = 'Session expirée';
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (_conversations.isEmpty) _error = e.toString();
      debugPrint('[MP] loadConversations: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Charge les messages d'une conversation.
  /// - Retour immédiat depuis SQLite (60 derniers messages)
  /// - Puis rafraîchissement silencieux depuis l'API
  Future<void> loadMessages(String convId) async {
    await _loadUid();

    // ── 1. Cache local → affichage en < 10 ms ─────────────────────────────
    final cached = await _db.loadMessages(
      convId,
      limit: 60,
      currentUserId: _uid ?? '',
    );
    if (cached.isNotEmpty) {
      _messages[convId] = cached;
      _hasMoreMessages.add(convId); // on présume qu'il y en a plus
      notifyListeners(); // affichage immédiat du cache
    } else {
      _messages[convId] ??= [];
    }

    // ── 2. Rafraîchissement réseau ─────────────────────────────────────────
    try {
      final token = await _tok.getToken();
      if (token == null) throw Exception('Non authentifié');

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data    = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawMsgs = data['messages'] ?? data['data'] ?? [];

        final fresh = (rawMsgs as List)
            .map((i) => MessageModel.fromJson(
                i as Map<String, dynamic>, _uid ?? ''))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        _messages[convId] = fresh;

        // Marquer qu'il n'y a probablement pas plus si < 60 messages reçus
        if (fresh.length < 60) _hasMoreMessages.remove(convId);

        // Persister en base (upsert complet)
        _db.saveMessages(convId, fresh);

        // Statut en ligne de l'interlocuteur
        final otherData = data['other_user'];
        if (otherData is Map) {
          final otherId = otherData['id']?.toString();
          if (otherId != null && otherId != _uid) _fetchOnlineBg(otherId);
        }

        // Souscrire au canal WebSocket
        await _ws.subscribeToConversation(convId);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[MP] loadMessages: $e');
      // En cas d'erreur réseau, on reste sur le cache — pas de message d'erreur
      if (cached.isNotEmpty) {
        await _ws.subscribeToConversation(convId);
      }
    }
  }

  /// Charge les messages plus anciens (pagination infinie vers le haut).
  Future<void> loadOlderMessages(String convId) async {
    final msgs = _messages[convId];
    if (msgs == null || msgs.isEmpty) return;

    // D'abord essayer le cache local
    final firstId = msgs.first.id;
    final older = await _db.loadOlderMessages(
      convId,
      beforeId: firstId,
      limit: 30,
      currentUserId: _uid ?? '',
    );

    if (older.isNotEmpty) {
      _messages[convId] = [...older, ...msgs];
      _notify();
    } else {
      _hasMoreMessages.remove(convId);
    }
  }

  // ── Patch local edit (sans rechargement réseau) ───────────────────────────

  /// Met à jour le contenu d'un message localement après une édition.
  void patchMessageContent(String convId, String msgId, String newContent) {
    final msgs = _messages[convId];
    if (msgs == null) return;
    final i = msgs.indexWhere((m) => m.id == msgId);
    if (i == -1) return;
    msgs[i] = msgs[i].copyWith(content: newContent);
    _db.updateMessageContent(msgId, newContent);
    _notify();
  }

  /// Supprime un message localement après confirmation serveur.
  void removeMessage(String convId, String msgId) {
    final msgs = _messages[convId];
    if (msgs == null) return;
    msgs.removeWhere((m) => m.id == msgId);
    _db.deleteMessage(msgId);

    // Mettre à jour l'aperçu de la conversation si c'était le dernier message
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      final lastMsg = msgs.isNotEmpty ? msgs.last : null;
      _conversations[idx] = _conversations[idx].copyWithLastMessage(lastMsg);
    }
    _notify();
  }

  Future<void> fetchOnlineStatus(String uid) async {
    try {
      final token = await _tok.getToken();
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
        updateUserOnlineStatus(
          uid,
          isOnline || (ls != null && DateTime.now().difference(ls).inMinutes < 5),
          ls,
        );
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
    // Persister le message optimiste pour le retrouver en cas de kill de l'app
    _db.saveMessage(tempMsg);
    notifyListeners();

    final token = await _tok.getToken();
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

    _applyResponse(data, convId, tempId,
        originalType: type, latitude: latitude, longitude: longitude);
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
    if (lat     != null) body['latitude']    = lat;
    if (lng     != null) body['longitude']   = lng;
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

    // Timeout élevé pour les gros fichiers (vidéos, documents) jusqu'à 100 Mo
    final streamed = await req.send().timeout(const Duration(minutes: 10));
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
    if (resp.statusCode == 422) {
      // Erreur de validation (ex: fichier trop lourd)
      try {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        final msg = d['message'] ?? d['errors']?.toString() ?? 'Fichier refusé';
        throw Exception(msg.toString());
      } catch (e) {
        if (e is Exception) rethrow;
      }
    }
    if (resp.statusCode == 413) {
      throw Exception('Fichier trop lourd pour le serveur (max 100 Mo)');
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
    if (originalType == 'audio' &&
        (data['type'] == 'vocal' || data['type'] == 'text')) {
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

    // Persister en base (supprime le temp, insère le confirmé)
    _db.confirmMessage(tempId, confirmed);

    // Mettre à jour aperçu conversation
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      _conversations[idx] = _conversations[idx].copyWithLastMessage(confirmed);
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _db.updateConversationLastMessage(convId, confirmed, 0);
    }
    _notify();
  }

  void _markError(String convId, String tempId) {
    final msgs = _messages[convId];
    if (msgs == null) return;
    final i = msgs.indexWhere((m) => m.id == tempId);
    if (i != -1) {
      msgs[i] = msgs[i].copyWith(status: 'error');
      _db.updateMessageStatus(tempId, 'error');
      _notify();
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  LIRE / TYPING / RECORDING
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> markConversationAsRead(String convId) async {
    _markReadLocally(convId);
    _clearUnreadBadge(convId);
    _db.markAllRead(convId);
    _db.resetUnreadCount(convId);
    try {
      final token = await _tok.getToken();
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
      final token = await _tok.getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/typing'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
        },
        body: jsonEncode({'is_typing': v}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> sendRecordingIndicator(String convId, bool v) async {
    try {
      final token = await _tok.getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/recording'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
        },
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
      final token = await _tok.getToken();
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

  // ── Vider le cache local à la déconnexion ─────────────────────────────────
  Future<void> clearLocalCache() async {
    _messages.clear();
    _conversations.clear();
    _lastConvLoad = null;
    _tok.invalidate();
    await _db.clearAll();
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
