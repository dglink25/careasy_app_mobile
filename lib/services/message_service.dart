import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../models/user_model.dart';

class MessageService {
  static final MessageService _instance = MessageService._internal();
  factory MessageService() => _instance;
  MessageService._internal();

  final _storage = const FlutterSecureStorage();
  String? _cachedToken;

  Future<String?> _getToken() async {
    if (_cachedToken != null) return _cachedToken;
    _cachedToken = await _storage.read(key: 'auth_token');
    return _cachedToken;
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  // Récupérer toutes les conversations
  Future<List<ConversationModel>> getConversations() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final currentUserId = await _getCurrentUserId();
        
        return data.map((json) => 
          ConversationModel.fromJson(json, currentUserId)
        ).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getConversations: $e');
      return [];
    }
  }

  // Récupérer les messages d'une conversation
  Future<List<MessageModel>> getMessages(String conversationId) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = data['messages'] as List<dynamic>;
        final currentUserId = await _getCurrentUserId();
        
        return messages.map((json) => 
          MessageModel.fromJson(json, currentUserId)
        ).toList();
      }
      return [];
    } catch (e) {
      print('Erreur getMessages: $e');
      return [];
    }
  }

  // Envoyer un message
  Future<MessageModel?> sendMessage(String conversationId, {
    required String type,
    String? content,
    String? filePath,
    double? latitude,
    double? longitude,
    String? temporaryId,
    String? replyToId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Non authentifié');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId/send'),
      );

      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      request.fields['type'] = type;
      if (content != null) request.fields['content'] = content;
      if (latitude != null) request.fields['latitude'] = latitude.toString();
      if (longitude != null) request.fields['longitude'] = longitude.toString();
      if (temporaryId != null) request.fields['temporary_id'] = temporaryId;
      if (replyToId != null) request.fields['reply_to_id'] = replyToId;

      if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final currentUserId = await _getCurrentUserId();
        return MessageModel.fromJson(data, currentUserId);
      }
      return null;
    } catch (e) {
      print('Erreur sendMessage: $e');
      return null;
    }
  }

  // Démarrer une conversation avec un service
  Future<Map<String, dynamic>?> startServiceConversation(String serviceId, {String? message}) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Non authentifié');

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/service'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'service_id': serviceId,
          'message': message,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Erreur startServiceConversation: $e');
      return null;
    }
  }

  // Marquer les messages comme lus
  Future<bool> markAsRead(String conversationId) async {
    try {
      final token = await _getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId/mark-read'),
        headers: await _getHeaders(),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erreur markAsRead: $e');
      return false;
    }
  }

  // Indicateur de frappe
  Future<bool> sendTypingIndicator(String conversationId, bool isTyping) async {
    try {
      final token = await _getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$conversationId/typing'),
        headers: await _getHeaders(),
        body: jsonEncode({'is_typing': isTyping}),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Mettre à jour le statut en ligne
  Future<bool> updateOnlineStatus() async {
    try {
      final token = await _getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/update-online-status'),
        headers: await _getHeaders(),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Vérifier le statut en ligne d'un utilisateur
  Future<Map<String, dynamic>?> checkOnlineStatus(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/$userId/online-status'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String> _getCurrentUserId() async {
    final userData = await _storage.read(key: 'user_data');
    if (userData != null) {
      final Map<String, dynamic> data = jsonDecode(userData);
      return data['id']?.toString() ?? '';
    }
    return '';
  }
}