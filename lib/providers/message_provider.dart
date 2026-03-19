// lib/providers/message_provider.dart
// ═══════════════════════════════════════════════════════════════════════
// MESSAGE PROVIDER — Source unique de vérité pour tous les messages
//
// RESPONSABILITÉS:
//  - Charger les conversations et messages depuis l'API
//  - Recevoir les messages en temps réel (via PusherService)
//  - Gérer les indicateurs typing et recording
//  - Mettre à jour les statuts en ligne
//  - Envoyer messages (texte, image, vidéo, audio, localisation)
// ═══════════════════════════════════════════════════════════════════════

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
  // Messages indexés par conversationId
  final Map<String, List<MessageModel>> _messages = {};

  // Conversations
  List<ConversationModel> _conversations = [];

  // Indicateurs typing: { conversationId: { userId: isTyping } }
  final Map<String, Map<String, bool>> _typing = {};

  // Indicateurs recording: { conversationId: { userId: isRecording } }
  final Map<String, Map<String, bool>> _recording = {};

  // Statuts en ligne: { userId: isOnline }
  final Map<String, bool>      _onlineStatus = {};
  final Map<String, DateTime?> _lastSeen     = {};

  bool    _isLoading = false;
  String? _error;
  String? _currentUserId;

  // Conversation actuellement ouverte à l'écran (pour éviter
  // d'afficher des notifications quand l'utilisateur est dedans)
  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  // Timer pour mettre à jour le statut en ligne toutes les 2 min
  Timer? _onlineTimer;

  // ─── Getters ───────────────────────────────────────────────────────
  List<ConversationModel> get conversations  => _conversations;
  bool                    get isLoading      => _isLoading;
  String?                 get error          => _error;
  String?                 get currentUserId  => _currentUserId;

  int get totalUnreadCount =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  // ═══════════════════════════════════════════════════════════════════
  //  INITIALISATION
  // ═══════════════════════════════════════════════════════════════════
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
        _currentUserId =
            (jsonDecode(raw) as Map<String, dynamic>)['id']?.toString();
        debugPrint('[MessageProvider] userId=$_currentUserId');
      }
    } catch (e) {
      debugPrint('[MessageProvider] _loadCurrentUser: $e');
    }
  }

  // ─── Timer statut en ligne ─────────────────────────────────────────
  void _startOnlineTimer() {
    _onlineTimer?.cancel();
    updateOnlineStatus(); // ping immédiat
    _onlineTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => updateOnlineStatus(),
    );
  }

  void stopOnlineTimer() {
    _onlineTimer?.cancel();
    _onlineTimer = null;
  }

  // ─── Réinitialisation après login ──────────────────────────────────
  Future<void> reinitializeAfterLogin() async {
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

  // ═══════════════════════════════════════════════════════════════════
  //  MISE À JOUR STATUT EN LIGNE
  // ═══════════════════════════════════════════════════════════════════
  /// Appelé par ChatScreen à l'ouverture / fermeture pour savoir
  /// quelle conversation est active (évite la notif locale redondante).
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
    // Marquer comme lu automatiquement quand on entre dans la conv
    if (conversationId != null) {
      markMessagesAsReadLocally(conversationId);
    }
  }

  void updateUserOnlineStatus(
      String userId, bool isOnline, DateTime? lastSeen) {
    _onlineStatus[userId] = isOnline;
    if (lastSeen != null) _lastSeen[userId] = lastSeen;

    // Mettre à jour la conversation correspondante
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

  // ═══════════════════════════════════════════════════════════════════
  //  INDICATEURS TYPING ET RECORDING
  // ═══════════════════════════════════════════════════════════════════

  // Appelé par PusherService quand un autre utilisateur écrit
  void setTypingIndicator(String convId, String userId, bool isTyping) {
    _typing[convId] ??= {};
    _typing[convId]![userId] = isTyping;
    notifyListeners();
  }

  // Appelé par PusherService quand un autre utilisateur enregistre un vocal
  void setRecordingIndicator(
      String convId, String userId, bool isRecording) {
    _recording[convId] ??= {};
    _recording[convId]![userId] = isRecording;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  STATUT EN LIGNE — Vérification directe API
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
          // Calculer si en ligne basé sur lastSeen si flag absent
          final onlineByTime =
              lastSeen != null &&
              DateTime.now().difference(lastSeen).inMinutes < 5;
          updateUserOnlineStatus(
              userId, isOnline || onlineByTime, lastSeen);
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

        // Mettre à jour les statuts en ligne depuis les données des conversations
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

        // Récupérer le statut en ligne de l'autre utilisateur
        final otherUserData =
            data['other_user'] ?? data['user_one'] ?? data['user_two'];
        if (otherUserData is Map) {
          final otherId = otherUserData['id']?.toString();
          if (otherId != null && otherId != _currentUserId) {
            fetchOnlineStatus(otherId); // async, pas await
          }
        }

        // S'abonner au canal de cette conversation via Pusher
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
    // Type API: 'audio' → 'vocal', 'location' → 'text'
    String apiType = type;
    if (type == 'audio')    apiType = 'vocal';
    if (type == 'location') apiType = 'text';

    // Créer un message temporaire immédiatement (UX instantanée)
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
        // ─── Envoi avec fichier (multipart) ───────────────────────
        final req = http.MultipartRequest(
          'POST',
          Uri.parse(
              '${AppConstants.apiBaseUrl}/conversation/$convId/send-mobile'),
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
        // ─── Envoi texte/localisation (JSON) ─────────────────────
        final body = <String, dynamic>{
          'type'        : apiType,
          'content'     : content ?? '',
          'temporary_id': tempId,
        };
        if (latitude  != null) body['latitude']   = latitude;
        if (longitude != null) body['longitude']  = longitude;
        if (replyToId != null) body['reply_to_id'] = replyToId;

        final r = await http.post(
          Uri.parse(
              '${AppConstants.apiBaseUrl}/conversation/$convId/send-mobile'),
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

      // ─── Traitement de la réponse ──────────────────────────────
      if (responseData != null) {
        // Conserver lat/lng si présents
        if (latitude  != null) responseData['latitude']  = latitude;
        if (longitude != null) responseData['longitude'] = longitude;

        // Corriger le type audio
        if (type == 'audio' &&
            (responseData['type'] == 'vocal' ||
             responseData['type'] == 'text')) {
          responseData['type'] = 'audio';
        }

        // Remplacer le message temporaire par le message confirmé
        _messages[convId]!.removeWhere((m) => m.id == tempId);
        final confirmed = MessageModel.fromJson(
            responseData, _currentUserId ?? '');
        _messages[convId]!.add(confirmed);

        // Mettre à jour la dernière conversation
        _updateConversationLastMessage(convId, confirmed);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[MessageProvider] sendMessage error: $e');

      // Marquer le message temporaire en erreur
      final idx =
          _messages[convId]?.indexWhere((m) => m.id == tempId) ?? -1;
      if (idx != -1) {
        _messages[convId]![idx] =
            _messages[convId]![idx].copyWith(status: 'error');
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

    // Éviter les doublons
    if (_messages[convId]!.any((m) => m.id == msg.id)) {
      debugPrint(
          '[MessageProvider] Message ${msg.id} déjà présent, ignoré');
      return;
    }

    debugPrint(
        '[MessageProvider] ✅ Nouveau message reçu: ${msg.id} dans $convId');
    _messages[convId]!.add(msg);

    // Mettre à jour la conversation dans la liste
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      final old = _conversations[idx];
      _conversations[idx] = ConversationModel(
        id            : old.id,
        otherUser     : old.otherUser,
        lastMessage   : msg,
        unreadCount   : old.unreadCount + (msg.isMe ? 0 : 1),
        updatedAt     : DateTime.now(),
        serviceName   : old.serviceName,
        entrepriseName: old.entrepriseName,
        serviceId     : old.serviceId,
        entrepriseId  : old.entrepriseId,
      );
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      // Conversation pas encore dans la liste → recharger
      loadConversations();
    }

    // notifyListeners() → ChatScreen se met à jour automatiquement via Consumer
    notifyListeners();
  }

  // ─── Confirmation d'envoi ───────────────────────────────────────────
  void confirmMessage(
      Map<String, dynamic> data, String convId, String currentUserId) {
    final msgs = _messages[convId];
    if (msgs == null) return;

    final tempId = data['temporary_id']?.toString();
    final msgId  = data['id']?.toString();

    int idx = -1;
    if (tempId != null) {
      idx = msgs.indexWhere(
          (m) => m.temporaryId == tempId || m.id == tempId);
    }
    if (idx == -1 && msgId != null) {
      idx = msgs.indexWhere((m) => m.id == msgId);
    }
    if (idx == -1) return;

    // Préserver lat/lng et type audio
    final orig = msgs[idx];
    if (orig.latitude  != null) data['latitude']  ??= orig.latitude;
    if (orig.longitude != null) data['longitude'] ??= orig.longitude;
    if (orig.type == 'audio' && data['type'] == 'vocal') {
      data['type'] = 'audio';
    }

    msgs[idx] = MessageModel.fromJson(data, currentUserId);
    notifyListeners();
  }

  // ─── Messages lus localement ────────────────────────────────────────
  void markMessagesAsReadLocally(String convId) {
    final msgs = _messages[convId];
    if (msgs == null) return;

    bool changed = false;
    for (int i = 0; i < msgs.length; i++) {
      if (msgs[i].isMe && msgs[i].readAt == null) {
        msgs[i] = msgs[i].copyWith(readAt: DateTime.now());
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INDICATEURS ENVOYÉS AU SERVEUR (pour les autres utilisateurs)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> sendTypingIndicator(String convId, bool isTyping) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;
      await http.post(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/conversation/$convId/typing'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
        },
        body: jsonEncode({'is_typing': isTyping}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> sendRecordingIndicator(
      String convId, bool isRecording) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;
      await http.post(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/conversation/$convId/recording'),
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
        Uri.parse(
            '${AppConstants.apiBaseUrl}/conversation/$convId/mark-read'),
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

  // Token FCM
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