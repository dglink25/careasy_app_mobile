import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../models/user_model.dart';
import '../services/pusher_service.dart';
import '../utils/constants.dart';

class MessageProvider extends ChangeNotifier {
  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );
  static const _iOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  final PusherService _pusher = PusherService();

  // ─── État ───────────────────────────────────────────────────────────
  final Map<String, List<MessageModel>> _messages = {};
  List<ConversationModel> _conversations = [];
  final Map<String, Map<String, bool>> _typing = {};
  final Map<String, Map<String, bool>> _recording = {};
  final Map<String, bool>      _onlineStatus = {};
  final Map<String, DateTime?> _lastSeen     = {};

  bool    _isLoading = false;
  String? _error;
  String? _currentUserId;
  String? _activeConversationId;
  Timer?  _onlineTimer;

  String? get activeConversationId => _activeConversationId;
  List<ConversationModel> get conversations  => _conversations;
  bool                    get isLoading      => _isLoading;
  String?                 get error          => _error;
  String?                 get currentUserId  => _currentUserId;

  int get totalUnreadCount =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  MessageProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadCurrentUser();
    if (_currentUserId != null) {
      _pusher.setMessageProvider(this);
      await _pusher.initialize();
      _startOnlineTimer();
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _currentUserId = decoded['id']?.toString();
        debugPrint('[MessageProvider] userId=$_currentUserId');
      }
    } catch (e) {
      debugPrint('[MessageProvider] _loadCurrentUser: $e');
    }
  }

  void _startOnlineTimer() {
    _onlineTimer?.cancel();
    updateOnlineStatus();
    _onlineTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => updateOnlineStatus(),
    );
  }

  void stopOnlineTimer() {
    _onlineTimer?.cancel();
    _onlineTimer = null;
  }

  Future<void> reinitializeAfterLogin() async {
    // Recharger l'userId depuis le storage (après login, il est maintenant disponible)
    await _loadCurrentUser();
    if (_currentUserId != null) {
      _pusher.setMessageProvider(this);
      await _pusher.reinitialize();
      _startOnlineTimer();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  GETTERS DONNÉES
  // ═══════════════════════════════════════════════════════════════════
  List<MessageModel> getMessages(String convId) =>
      _messages[convId] ?? [];

  bool isUserTyping(String convId, String userId) =>
      _typing[convId]?[userId] ?? false;

  bool isUserRecording(String convId, String userId) =>
      _recording[convId]?[userId] ?? false;

  bool getUserOnlineStatus(String userId) {
    if (_onlineStatus.containsKey(userId)) return _onlineStatus[userId]!;
    final ls = _lastSeen[userId];
    if (ls != null) return DateTime.now().difference(ls).inMinutes < 5;
    return false;
  }

  DateTime? getUserLastSeen(String userId) => _lastSeen[userId];

  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
    if (conversationId != null) {
      markMessagesAsReadLocally(conversationId);
    }
  }

  void updateUserOnlineStatus(String userId, bool isOnline, DateTime? lastSeen) {
    _onlineStatus[userId] = isOnline;
    if (lastSeen != null) _lastSeen[userId] = lastSeen;

    final idx = _conversations.indexWhere((c) => c.otherUser.id == userId);
    if (idx != -1) {
      final old = _conversations[idx];
      _conversations[idx] = ConversationModel(
        id            : old.id,
        otherUser     : UserModel(
          id       : old.otherUser.id,
          name     : old.otherUser.name,
          email    : old.otherUser.email,
          photoUrl : old.otherUser.photoUrl,
          isOnline : isOnline,
          lastSeen : lastSeen ?? old.otherUser.lastSeen,
          role     : old.otherUser.role,
          phone    : old.otherUser.phone,
        ),
        lastMessage   : old.lastMessage,
        unreadCount   : old.unreadCount,
        updatedAt     : old.updatedAt,
        serviceName   : old.serviceName,
        entrepriseName: old.entrepriseName,
        serviceId     : old.serviceId,
        entrepriseId  : old.entrepriseId,
      );
    }
    notifyListeners();
  }

  void setTypingIndicator(String convId, String userId, bool isTyping) {
    _typing[convId] ??= {};
    _typing[convId]![userId] = isTyping;
    notifyListeners();
  }

  void setRecordingIndicator(String convId, String userId, bool isRecording) {
    _recording[convId] ??= {};
    _recording[convId]![userId] = isRecording;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  STATUT EN LIGNE
  // ═══════════════════════════════════════════════════════════════════
  Future<void> fetchOnlineStatus(String userId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) return;

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/$userId/online-status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept'       : 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data     = jsonDecode(resp.body) as Map<String, dynamic>;
        final isOnline = data['is_online'] == true;
        DateTime? lastSeen;
        final raw = data['last_seen_at'] ?? data['last_seen'];
        if (raw != null) {
          lastSeen = DateTime.tryParse(raw.toString())?.toLocal();
          final onlineByTime = lastSeen != null &&
              DateTime.now().difference(lastSeen).inMinutes < 5;
          updateUserOnlineStatus(userId, isOnline || onlineByTime, lastSeen);
          return;
        }
        updateUserOnlineStatus(userId, isOnline, null);
      }
    } catch (e) {
      debugPrint('[MessageProvider] fetchOnlineStatus: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CONVERSATIONS
  // ═══════════════════════════════════════════════════════════════════
  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) throw Exception('Non authentifié');

      // S'assurer que currentUserId est chargé
      if (_currentUserId == null) await _loadCurrentUser();

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept'       : 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        _conversations = list
            .map((i) => ConversationModel.fromJson(
                i as Map<String, dynamic>, _currentUserId ?? ''))
            .toList();
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        for (final c in _conversations) {
          _onlineStatus[c.otherUser.id] = c.otherUser.isOnline;
          if (c.otherUser.lastSeen != null) {
            _lastSeen[c.otherUser.id] = c.otherUser.lastSeen;
          }
        }
        _error = null;
      } else if (resp.statusCode == 401) {
        _error = 'Session expirée';
      } else {
        throw Exception('Erreur HTTP ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('[MessageProvider] loadConversations: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  MESSAGES
  // ═══════════════════════════════════════════════════════════════════
  Future<void> loadMessages(String convId) async {
    _messages[convId] ??= [];

    // S'assurer que currentUserId est chargé avant de parser les messages
    if (_currentUserId == null) await _loadCurrentUser();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) throw Exception('Non authentifié');

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept'       : 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data    = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawMsgs = data['messages'] ?? data['data'] ?? [];
        final msgs    = rawMsgs is List ? rawMsgs : [];

        _messages[convId] = msgs
            .map((i) => MessageModel.fromJson(
                i as Map<String, dynamic>, _currentUserId ?? ''))
            .toList();

        // Trier par date croissante
        _messages[convId]!.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        final otherUserData =
            data['other_user'] ?? data['user_one'] ?? data['user_two'];
        if (otherUserData is Map) {
          final otherId = otherUserData['id']?.toString();
          if (otherId != null && otherId != _currentUserId) {
            fetchOnlineStatus(otherId);
          }
        }

        await _pusher.subscribeToConversation(convId);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[MessageProvider] loadMessages: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ENVOI DE MESSAGE
  // ═══════════════════════════════════════════════════════════════════
  Future<void> sendMessage(
    String convId, {
    required String type,
    String? content,
    String? filePath,
    double? latitude,
    double? longitude,
    String? replyToId,
  }) async {
    if (_currentUserId == null) await _loadCurrentUser();

    String apiType = type;
    if (type == 'audio')    apiType = 'vocal';
    if (type == 'location') apiType = 'text';

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = MessageModel(
      id            : tempId,
      conversationId: convId,
      senderId      : _currentUserId ?? '',
      content       : content ?? _defaultContent(apiType),
      type          : type,
      fileUrl       : filePath,
      latitude      : latitude,
      longitude     : longitude,
      createdAt     : DateTime.now(),
      isMe          : true,
      status        : 'sending',
    );

    _messages[convId] ??= [];
    _messages[convId]!.add(tempMsg);
    notifyListeners();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) throw Exception('Non authentifié');

      Map<String, dynamic>? responseData;

      if (filePath != null) {
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/send-mobile'),
        );
        req.headers['Authorization'] = 'Bearer $token';
        req.headers['Accept']        = 'application/json';
        req.fields['type']           = apiType;
        req.fields['temporary_id']   = tempId;
        if (content != null && content.isNotEmpty) {
          req.fields['content'] = content;
        }
        if (replyToId != null) req.fields['reply_to_id'] = replyToId;
        req.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamed = await req.send().timeout(const Duration(seconds: 60));
        final r = await http.Response.fromStream(streamed);

        if (r.statusCode == 200 || r.statusCode == 201) {
          responseData = jsonDecode(r.body) as Map<String, dynamic>;
        } else {
          throw Exception('HTTP ${r.statusCode}: ${r.body}');
        }
      } else {
        final body = <String, dynamic>{
          'type'        : apiType,
          'content'     : content ?? '',
          'temporary_id': tempId,
        };
        if (latitude  != null) body['latitude']   = latitude;
        if (longitude != null) body['longitude']  = longitude;
        if (replyToId != null) body['reply_to_id'] = replyToId;

        final r = await http.post(
          Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/send-mobile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type' : 'application/json',
            'Accept'       : 'application/json',
          },
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 30));

        if (r.statusCode == 200 || r.statusCode == 201) {
          responseData = jsonDecode(r.body) as Map<String, dynamic>;
        } else {
          throw Exception('HTTP ${r.statusCode}: ${r.body}');
        }
      }

      if (responseData != null) {
        // Conserver lat/lng et type audio
        if (latitude  != null) responseData['latitude']  ??= latitude;
        if (longitude != null) responseData['longitude'] ??= longitude;
        if (type == 'audio' &&
            (responseData['type'] == 'vocal' || responseData['type'] == 'text')) {
          responseData['type'] = 'audio';
        }

        // Forcer is_me = true pour notre propre message
        responseData['is_me'] = true;
        responseData['sender_id'] ??= _currentUserId;

        _messages[convId]!.removeWhere((m) => m.id == tempId);
        final confirmed = MessageModel.fromJson(responseData, _currentUserId ?? '');
        _messages[convId]!.add(confirmed);
        _messages[convId]!.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        _updateConversationLastMessage(convId, confirmed);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[MessageProvider] sendMessage error: $e');
      final idx = _messages[convId]?.indexWhere((m) => m.id == tempId) ?? -1;
      if (idx != -1) {
        _messages[convId]![idx] = _messages[convId]![idx].copyWith(status: 'error');
        notifyListeners();
      }
      rethrow;
    }
  }

  void _updateConversationLastMessage(String convId, MessageModel msg) {
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      final old = _conversations[idx];
      _conversations[idx] = ConversationModel(
        id            : old.id,
        otherUser     : old.otherUser,
        lastMessage   : msg,
        unreadCount   : old.unreadCount,
        updatedAt     : DateTime.now(),
        serviceName   : old.serviceName,
        entrepriseName: old.entrepriseName,
        serviceId     : old.serviceId,
        entrepriseId  : old.entrepriseId,
      );
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  RÉCEPTION TEMPS RÉEL — Appelé par PusherService
  // ═══════════════════════════════════════════════════════════════════
  void receiveMessage(MessageModel msg, String convId) {
    _messages[convId] ??= [];

    // Ne pas ajouter nos propres messages (déjà ajoutés via sendMessage)
    if (msg.isMe) {
      debugPrint('[MessageProvider] Message de soi ignoré en réception: ${msg.id}');
      return;
    }

    // Déduplication par id ET temporaryId
    final alreadyExists = _messages[convId]!.any((m) =>
        m.id == msg.id ||
        (msg.temporaryId != null && m.temporaryId == msg.temporaryId));

    if (alreadyExists) {
      debugPrint('[MessageProvider] Doublon ignoré: ${msg.id}');
      return;
    }

    debugPrint('[MessageProvider] ✅ Nouveau message reçu: ${msg.id} dans $convId');
    _messages[convId]!.add(msg);
    // Trier par date pour maintenir l'ordre correct
    _messages[convId]!.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      final old = _conversations[idx];
      _conversations[idx] = ConversationModel(
        id            : old.id,
        otherUser     : old.otherUser,
        lastMessage   : msg,
        unreadCount   : old.unreadCount + 1,
        updatedAt     : DateTime.now(),
        serviceName   : old.serviceName,
        entrepriseName: old.entrepriseName,
        serviceId     : old.serviceId,
        entrepriseId  : old.entrepriseId,
      );
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      loadConversations();
    }

    notifyListeners();
  }

  // ─── Confirmation d'envoi (via Pusher) ─────────────────────────────
  void confirmMessage(Map<String, dynamic> data, String convId, String currentUserId) {
    final msgs = _messages[convId];
    if (msgs == null) return;

    final tempId = data['temporary_id']?.toString();
    final msgId  = data['id']?.toString();

    int idx = -1;
    if (tempId != null) {
      idx = msgs.indexWhere((m) => m.temporaryId == tempId || m.id == tempId);
    }
    if (idx == -1 && msgId != null) {
      idx = msgs.indexWhere((m) => m.id == msgId);
    }
    if (idx == -1) return;

    final orig = msgs[idx];
    if (orig.latitude  != null) data['latitude']  ??= orig.latitude;
    if (orig.longitude != null) data['longitude'] ??= orig.longitude;
    if (orig.type == 'audio' && data['type'] == 'vocal') {
      data['type'] = 'audio';
    }
    // Toujours forcer is_me = true pour la confirmation de nos propres messages
    data['is_me'] = true;
    data['sender_id'] ??= currentUserId;

    msgs[idx] = MessageModel.fromJson(data, currentUserId);
    msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    notifyListeners();
  }

  void markMessagesAsReadLocally(String convId) {
    final msgs = _messages[convId];
    if (msgs == null) return;

    bool changed = false;
    for (int i = 0; i < msgs.length; i++) {
      if (!msgs[i].isMe && msgs[i].readAt == null) {
        msgs[i] = msgs[i].copyWith(readAt: DateTime.now());
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INDICATEURS ENVOYÉS AU SERVEUR
  // ═══════════════════════════════════════════════════════════════════
  Future<void> sendTypingIndicator(String convId, bool isTyping) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/typing'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
        },
        body: jsonEncode({'is_typing': isTyping}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> sendRecordingIndicator(String convId, bool isRecording) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/recording'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
        },
        body: jsonEncode({'is_recording': isRecording}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════
  //  MARQUER COMME LU
  // ═══════════════════════════════════════════════════════════════════
  Future<void> markConversationAsRead(String convId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId/mark-read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      final idx = _conversations.indexWhere((c) => c.id == convId);
      if (idx != -1) {
        final old = _conversations[idx];
        _conversations[idx] = ConversationModel(
          id            : old.id,
          otherUser     : old.otherUser,
          lastMessage   : old.lastMessage,
          unreadCount   : 0,
          updatedAt     : old.updatedAt,
          serviceName   : old.serviceName,
          entrepriseName: old.entrepriseName,
          serviceId     : old.serviceId,
          entrepriseId  : old.entrepriseId,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[MessageProvider] markConversationAsRead: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  STATUT EN LIGNE — Ping serveur
  // ═══════════════════════════════════════════════════════════════════
  Future<void> updateOnlineStatus() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/update-online-status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
        },
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> saveFcmToken(String fcmToken) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/fcm-token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
          'Accept'       : 'application/json',
        },
        body: jsonEncode({
          'fcm_token': fcmToken,
          'platform' : 'android',
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[MessageProvider] saveFcmToken: $e');
    }
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
    _onlineTimer?.cancel();
    super.dispose();
  }
}