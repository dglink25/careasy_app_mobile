// providers/message_provider.dart
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
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final PusherService _pusherService = PusherService();

  Map<String, List<MessageModel>> _messages = {};
  List<ConversationModel> _conversations = [];
  Map<String, Map<String, bool>> _typingIndicators = {};
  // Map userId -> isOnline pour le statut temps réel
  Map<String, bool> _onlineStatus = {};
  Map<String, DateTime?> _lastSeenStatus = {};

  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  String? _currentUserId;

  List<ConversationModel> get conversations => _conversations;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentUserId => _currentUserId;

  int get totalUnreadCount {
    return _conversations.fold(0, (sum, conv) => sum + conv.unreadCount);
  }

  MessageProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadCurrentUser();
    _pusherService.setMessageProvider(this);
    await _pusherService.initialize();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final userData = await _storage.read(key: 'user_data');
      if (userData != null) {
        final Map<String, dynamic> data = jsonDecode(userData);
        _currentUserId = data['id']?.toString();
      }
    } catch (e) {
      debugPrint('Erreur chargement user: $e');
    }
  }

  List<MessageModel> getMessages(String conversationId) {
    return _messages[conversationId] ?? [];
  }

  bool isUserTyping(String conversationId, String userId) {
    return _typingIndicators[conversationId]?[userId] ?? false;
  }

  // ─── Statut en ligne (mis à jour via Pusher) ─────────────────────────────
  bool getUserOnlineStatus(String userId) {
    return _onlineStatus[userId] ?? false;
  }

  DateTime? getUserLastSeen(String userId) {
    return _lastSeenStatus[userId];
  }

  void updateUserOnlineStatus(String userId, bool isOnline, DateTime? lastSeen) {
    _onlineStatus[userId] = isOnline;
    if (lastSeen != null) _lastSeenStatus[userId] = lastSeen;

    // Mettre à jour aussi dans les conversations
    final idx = _conversations.indexWhere(
      (c) => c.otherUser.id == userId,
    );
    if (idx != -1) {
      final old = _conversations[idx];
      final updatedUser = UserModel(
        id: old.otherUser.id,
        name: old.otherUser.name,
        email: old.otherUser.email,
        photoUrl: old.otherUser.photoUrl,
        isOnline: isOnline,
        lastSeen: lastSeen ?? old.otherUser.lastSeen,
        role: old.otherUser.role,
        phone: old.otherUser.phone,
      );
      _conversations[idx] = ConversationModel(
        id: old.id,
        otherUser: updatedUser,
        lastMessage: old.lastMessage,
        unreadCount: old.unreadCount,
        updatedAt: old.updatedAt,
        serviceName: old.serviceName,
        entrepriseName: old.entrepriseName,
        serviceId: old.serviceId,
        entrepriseId: old.entrepriseId,
      );
    }
    notifyListeners();
  }

  // ─── Conversations ────────────────────────────────────────────────────────
  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _conversations = data
            .map((item) => ConversationModel.fromJson(item, _currentUserId ?? ''))
            .toList();
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        // Synchroniser le statut en ligne depuis les données chargées
        for (final conv in _conversations) {
          _onlineStatus[conv.otherUser.id] = conv.otherUser.isOnline;
          if (conv.otherUser.lastSeen != null) {
            _lastSeenStatus[conv.otherUser.id] = conv.otherUser.lastSeen;
          }
        }
        _error = null;
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Erreur loadConversations: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Messages ─────────────────────────────────────────────────────────────
  Future<void> loadMessages(String conversationId) async {
    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        // Le backend retourne { messages: [...], ... } ou { data: [...] }
        final List<dynamic> messagesData =
            data['messages'] ?? data['data'] ?? [];

        _messages[conversationId] = messagesData
            .map((item) => MessageModel.fromJson(item, _currentUserId ?? ''))
            .toList();

        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Erreur loadMessages: $e');
    }
  }

  // ─── Envoi de message ─────────────────────────────────────────────────────
  Future<void> sendMessage(
    String conversationId, {
    required String type,
    String? content,
    String? filePath,
    double? latitude,
    double? longitude,
    String? replyToId,
  }) async {
    if (_isSending) return;
    _isSending = true;

    // Adapter le type pour l'API (audio → vocal, location → text)
    String apiType = type;
    if (type == 'audio') apiType = 'vocal';
    if (type == 'location') apiType = 'text';

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    final tempMessage = MessageModel(
      id: tempId,
      conversationId: conversationId,
      senderId: _currentUserId ?? '',
      content: content ??
          (filePath != null ? _getDefaultContent(apiType) : ''),
      type: type,
      fileUrl: filePath,
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now(),
      isMe: true,
      status: 'sending',
    );

    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }
    _messages[conversationId]!.add(tempMessage);
    notifyListeners();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      Map<String, dynamic>? responseData;

      if (filePath != null) {
        // ── Envoi multipart (fichier) ────────────────────────────────────
        final request = http.MultipartRequest(
          'POST',
          Uri.parse(
              '${AppConstants.apiBaseUrl}/conversation/$conversationId/send-mobile'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'application/json';
        request.fields['type'] = apiType;
        request.fields['temporary_id'] = tempId;
        if (content != null && content.isNotEmpty) {
          request.fields['content'] = content;
        }
        if (replyToId != null) request.fields['reply_to_id'] = replyToId;

        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamed = await request.send();
        final resp = await http.Response.fromStream(streamed);

        if (resp.statusCode == 200 || resp.statusCode == 201) {
          responseData = jsonDecode(resp.body);
        } else {
          throw Exception('Erreur ${resp.statusCode}: ${resp.body}');
        }
      } else {
        // ── Envoi JSON (texte / localisation) ───────────────────────────
        final body = <String, dynamic>{
          'type': apiType,
          'content': content ?? '',
          'temporary_id': tempId,
        };
        if (latitude != null) body['latitude'] = latitude;
        if (longitude != null) body['longitude'] = longitude;
        if (replyToId != null) body['reply_to_id'] = replyToId;

        final resp = await http.post(
          Uri.parse(
              '${AppConstants.apiBaseUrl}/conversation/$conversationId/send-mobile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        );

        if (resp.statusCode == 200 || resp.statusCode == 201) {
          responseData = jsonDecode(resp.body);
        } else {
          throw Exception('Erreur ${resp.statusCode}: ${resp.body}');
        }
      }

      if (responseData != null) {
        // Le backend retourne is_me: true — on le conserve
        // Pour la localisation, on injecte les coordonnées
        if (latitude != null) responseData['latitude'] = latitude;
        if (longitude != null) responseData['longitude'] = longitude;
        if (type == 'location') responseData['type'] = 'location';

        _messages[conversationId]!.removeWhere((m) => m.id == tempId);
        final newMsg = MessageModel.fromJson(responseData, _currentUserId ?? '');
        _messages[conversationId]!.add(newMsg);
        await _updateConversationWithLastMessage(conversationId, newMsg);
      }
    } catch (e) {
      debugPrint('❌ Erreur sendMessage: $e');
      _markMessageAsError(conversationId, tempId,
          content ?? _getDefaultContent(apiType));
      rethrow;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void _markMessageAsError(
      String conversationId, String tempId, String content) {
    final list = _messages[conversationId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(status: 'error');
      notifyListeners();
    }
  }

  Future<void> _updateConversationWithLastMessage(
    String conversationId,
    MessageModel message,
  ) async {
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx != -1) {
      final old = _conversations[idx];
      _conversations[idx] = ConversationModel(
        id: old.id,
        otherUser: old.otherUser,
        lastMessage: message,
        unreadCount: old.unreadCount,
        updatedAt: DateTime.now(),
        serviceName: old.serviceName,
        entrepriseName: old.entrepriseName,
        serviceId: old.serviceId,
        entrepriseId: old.entrepriseId,
      );
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
  }

  // ─── Typing indicator ─────────────────────────────────────────────────────
  Future<void> sendTypingIndicator(
      String conversationId, bool isTyping) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;
      await http.post(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/conversation/$conversationId/typing'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'is_typing': isTyping}),
      );
    } catch (_) {}
  }

  void setTypingIndicator(
      String conversationId, String userId, bool isTyping) {
    _typingIndicators[conversationId] ??= {};
    _typingIndicators[conversationId]![userId] = isTyping;
    notifyListeners();
  }

  // ─── Marquer comme lu ─────────────────────────────────────────────────────
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;
      await http.post(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/conversation/$conversationId/mark-read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx != -1) {
        final old = _conversations[idx];
        _conversations[idx] = ConversationModel(
          id: old.id,
          otherUser: old.otherUser,
          lastMessage: old.lastMessage,
          unreadCount: 0,
          updatedAt: old.updatedAt,
          serviceName: old.serviceName,
          entrepriseName: old.entrepriseName,
          serviceId: old.serviceId,
          entrepriseId: old.entrepriseId,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  // ─── Réception temps réel via Pusher ─────────────────────────────────────
  void receiveMessage(MessageModel message, String conversationId) {
    _messages[conversationId] ??= [];

    // Éviter les doublons (par temporaryId ou id)
    final alreadyExists = _messages[conversationId]!.any(
      (m) => m.id == message.id,
    );
    if (alreadyExists) return;

    _messages[conversationId]!.add(message);

    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx != -1) {
      final old = _conversations[idx];
      _conversations[idx] = ConversationModel(
        id: old.id,
        otherUser: old.otherUser,
        lastMessage: message,
        unreadCount: old.unreadCount + (message.isMe ? 0 : 1),
        updatedAt: DateTime.now(),
        serviceName: old.serviceName,
        entrepriseName: old.entrepriseName,
        serviceId: old.serviceId,
        entrepriseId: old.entrepriseId,
      );
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      // Nouvelle conversation inconnue → recharger
      loadConversations();
    }

    notifyListeners();
  }

  // ─── Statut en ligne ──────────────────────────────────────────────────────
  Future<void> updateOnlineStatus() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/update-online-status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    } catch (_) {}
  }

  String _getDefaultContent(String type) {
    switch (type) {
      case 'image':
        return 'Image';
      case 'video':
        return 'Vidéo';
      case 'vocal':
        return 'Message vocal';
      case 'document':
        return 'Document';
      default:
        return '';
    }
  }
}