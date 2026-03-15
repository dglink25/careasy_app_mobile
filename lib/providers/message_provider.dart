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
  bool _isSending = false;
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

      print('📥 Conversations response: ${response.statusCode}');
      print('📥 Body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _conversations = data.map((item) => 
          ConversationModel.fromJson(item, _currentUserId ?? '')
        ).toList();
        
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _error = null;
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur loadConversations: $e');
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
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      print('📥 Messages response: ${response.statusCode}');
      print('📥 Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> messagesData = data['messages'] ?? data['data'] ?? [];
        
        _messages[conversationId] = messagesData.map((item) => 
          MessageModel.fromJson(item, _currentUserId ?? '')
        ).toList();
        
        notifyListeners();
      }
    } catch (e) {
      print('❌ Erreur loadMessages: $e');
    }
  }

  Future<void> sendMessage(
    String conversationId, {
    required String type,
    String? content,
    String? filePath,
    double? latitude,
    double? longitude,
  }) async {
    if (_isSending) return;
    _isSending = true;

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      // ADAPTATION: Convertir les types pour correspondre à votre API
      // Votre API accepte: text, image, video, vocal, document
      String apiType = type;
      if (type == 'audio') apiType = 'vocal';
      if (type == 'location') apiType = 'text'; // Fallback pour location

      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      
      final tempMessage = MessageModel(
        id: tempId,
        conversationId: conversationId,
        senderId: _currentUserId ?? '',
        content: content ?? (filePath != null ? _getDefaultContent(apiType) : ''),
        type: type, // Garder le type original pour l'affichage
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

      // Pour les messages texte simples
      if (type == 'text' && filePath == null) {
        final response = await http.post(
          Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId/send-mobile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'type': apiType,
            'content': content ?? '',
            'temporary_id': tempId,
          }),
        );

        print('📥 Réponse texte: ${response.statusCode} - ${response.body}');

        if (response.statusCode == 201 || response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          
          _messages[conversationId]!.removeWhere((m) => m.id == tempId);
          
          final newMessage = MessageModel.fromJson(data, _currentUserId ?? '');
          _messages[conversationId]!.add(newMessage);
          
          await _updateConversationWithLastMessage(conversationId, newMessage);
          notifyListeners();
        } else {
          _markMessageAsError(conversationId, tempId, content ?? '');
          throw Exception('Erreur ${response.statusCode}');
        }
      } 
      // Pour les fichiers (images, vidéos, audio)
      else if (filePath != null) {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId/send-mobile'),
        );
        
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'application/json';
        
        request.fields['type'] = apiType;
        if (content != null && content.isNotEmpty) {
          request.fields['content'] = content;
        }
        request.fields['temporary_id'] = tempId;
        
        final file = await http.MultipartFile.fromPath('file', filePath);
        request.files.add(file);
        
        print('📤 Envoi fichier vers: ${AppConstants.apiBaseUrl}/conversation/$conversationId/send-mobile');
        
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
        
        print('📥 Réponse fichier: ${response.statusCode} - ${response.body}');

        if (response.statusCode == 201 || response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          
          _messages[conversationId]!.removeWhere((m) => m.id == tempId);
          
          final newMessage = MessageModel.fromJson(data, _currentUserId ?? '');
          _messages[conversationId]!.add(newMessage);
          
          await _updateConversationWithLastMessage(conversationId, newMessage);
          notifyListeners();
        } else {
          _markMessageAsError(conversationId, tempId, _getDefaultContent(apiType));
          throw Exception('Erreur ${response.statusCode}');
        }
      }
      // Pour la localisation (fallback en texte)
      else if (latitude != null && longitude != null) {
        final response = await http.post(
          Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId/send-mobile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'type': 'text',
            'content': content ?? '📍 Localisation partagée',
            'temporary_id': tempId,
          }),
        );

        if (response.statusCode == 201 || response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          
          _messages[conversationId]!.removeWhere((m) => m.id == tempId);
          
          // Ajouter les coordonnées pour l'affichage
          data['latitude'] = latitude;
          data['longitude'] = longitude;
          
          final newMessage = MessageModel.fromJson(data, _currentUserId ?? '');
          _messages[conversationId]!.add(newMessage);
          
          await _updateConversationWithLastMessage(conversationId, newMessage);
          notifyListeners();
        } else {
          _markMessageAsError(conversationId, tempId, content ?? '📍 Localisation');
          throw Exception('Erreur ${response.statusCode}');
        }
      }

    } catch (e) {
      print('❌ Erreur sendMessage: $e');
      rethrow;
    } finally {
      _isSending = false;
    }
  }

  void _markMessageAsError(String conversationId, String tempId, String content) {
    final index = _messages[conversationId]!.indexWhere((m) => m.id == tempId);
    if (index != -1) {
      _messages[conversationId]![index] = MessageModel(
        id: tempId,
        conversationId: conversationId,
        senderId: _currentUserId ?? '',
        content: content,
        type: 'text',
        createdAt: DateTime.now(),
        isMe: true,
        status: 'error',
      );
      notifyListeners();
    }
  }

  Future<void> _updateConversationWithLastMessage(
    String conversationId,
    MessageModel message,
  ) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final oldConv = _conversations[index];
      _conversations[index] = ConversationModel(
        id: oldConv.id,
        otherUser: oldConv.otherUser,
        lastMessage: message,
        unreadCount: oldConv.unreadCount,
        updatedAt: DateTime.now(),
        serviceName: oldConv.serviceName,
        entrepriseName: oldConv.entrepriseName,
        serviceId: oldConv.serviceId,
        entrepriseId: oldConv.entrepriseId,
      );
      
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      notifyListeners();
    }
  }

  Future<void> sendTypingIndicator(String conversationId, bool isTyping) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId/typing'),
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

  Future<void> markConversationAsRead(String conversationId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId/mark-read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

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

  String _getDefaultContent(String type) {
    switch (type) {
      case 'image': return '📷 Image';
      case 'video': return '🎥 Vidéo';
      case 'vocal': return '🎤 Message vocal';
      case 'document': return '📄 Document';
      default: return '';
    }
  }

  void receiveMessage(MessageModel message, String conversationId) {
    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = [];
    }
    _messages[conversationId]!.add(message);
    
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
      
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
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

  // Nouvelle méthode pour mettre à jour le statut en ligne
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
    } catch (e) {
      print('Erreur updateOnlineStatus: $e');
    }
  }
}