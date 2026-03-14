// providers/message_provider.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../services/pusher_service.dart';
import '../utils/constants.dart';

class MessageProvider extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final PusherService _pusherService = PusherService();
  
  Map<String, List<MessageModel>> _messages = {};
  List<ConversationModel> _conversations = [];
  Map<String, Map<String, bool>> _typingIndicators = {};
  
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;

  List<ConversationModel> get conversations => _conversations;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
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
      print('Erreur chargement user: $e');
    }
  }

  List<MessageModel> getMessages(String conversationId) {
    return _messages[conversationId] ?? [];
  }

  bool isUserTyping(String conversationId, String userId) {
    return _typingIndicators[conversationId]?[userId] ?? false;
  }

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
        _conversations = data.map((item) => 
          ConversationModel.fromJson(item, _currentUserId ?? '')
        ).toList();
        
        // Trier par date de mise à jour
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        
        _error = null;
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(String conversationId) async {
    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations/$conversationId/messages'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _messages[conversationId] = data.map((item) => 
          MessageModel.fromJson(item, _currentUserId ?? '')
        ).toList();
        
        notifyListeners();
      }
    } catch (e) {
      print('Erreur chargement messages: $e');
    }
  }

  Future<void> sendMessage(
    String conversationId, {
    required String type,
    String? content,
    String? filePath,
  }) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      // Créer un message temporaire
      final tempMessage = MessageModel(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversationId,
        senderId: _currentUserId ?? '',
        content: content ?? '',
        type: type,
        filePath: filePath,
        createdAt: DateTime.now(),
        isMe: true,
      );

      // Ajouter le message temporaire
      if (!_messages.containsKey(conversationId)) {
        _messages[conversationId] = [];
      }
      _messages[conversationId]!.add(tempMessage);
      notifyListeners();

      // Envoyer au serveur
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.apiBaseUrl}/conversations/$conversationId/messages'),
      );
      
      request.headers['Authorization'] = 'Bearer $token';
      
      if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
      }
      
      if (content != null) {
        request.fields['content'] = content;
      }
      
      request.fields['type'] = type;

      final response = await request.send();
      
      if (response.statusCode == 201) {
        // Message envoyé avec succès
        final responseData = await http.Response.fromStream(response);
        final data = jsonDecode(responseData.body);
        
        // Remplacer le message temporaire par le vrai
        _messages[conversationId]!.removeWhere((m) => m.id == tempMessage.id);
        _messages[conversationId]!.add(
          MessageModel.fromJson(data['message'] ?? data, _currentUserId ?? '')
        );
        
        // Mettre à jour la conversation
        await loadConversations();
        
        notifyListeners();
      } else {
        // Échec, retirer le message temporaire
        _messages[conversationId]!.removeWhere((m) => m.id == tempMessage.id);
        notifyListeners();
        throw Exception('Erreur envoi message');
      }
    } catch (e) {
      print('Erreur sendMessage: $e');
      rethrow;
    }
  }

  Future<void> sendTypingIndicator(String conversationId, bool isTyping) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations/$conversationId/typing'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'is_typing': isTyping}),
      );
    } catch (e) {
      print('Erreur typing indicator: $e');
    }
  }

  Future<void> markAsRead(String conversationId) async {
    
  }

  Future<void> markConversationAsRead(String conversationId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations/$conversationId/read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      // Mettre à jour localement
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        final oldConv = _conversations[index];
        _conversations[index] = ConversationModel(
          id: oldConv.id,
          otherUser: oldConv.otherUser,
          lastMessage: oldConv.lastMessage,
          unreadCount: 0,
          updatedAt: oldConv.updatedAt,
          serviceName: oldConv.serviceName,
          entrepriseName: oldConv.entrepriseName,
        );
        notifyListeners();
      }
    } catch (e) {
      print('Erreur markAsRead: $e');
    }
  }

  void receiveMessage(MessageModel message, String conversationId) {
    // Ajouter le message
    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }
    _messages[conversationId]!.add(message);
    
    // Mettre à jour la conversation
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final oldConv = _conversations[index];
      _conversations[index] = ConversationModel(
        id: oldConv.id,
        otherUser: oldConv.otherUser,
        lastMessage: message,
        unreadCount: oldConv.unreadCount + (message.isMe ? 0 : 1),
        updatedAt: DateTime.now(),
        serviceName: oldConv.serviceName,
        entrepriseName: oldConv.entrepriseName,
      );
      
      // Réorganiser
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      // Nouvelle conversation
      loadConversations();
    }
    
    notifyListeners();
  }

  void setTypingIndicator(String conversationId, String userId, bool isTyping) {
    if (!_typingIndicators.containsKey(conversationId)) {
      _typingIndicators[conversationId] = {};
    }
    _typingIndicators[conversationId]![userId] = isTyping;
    notifyListeners();
  }
}