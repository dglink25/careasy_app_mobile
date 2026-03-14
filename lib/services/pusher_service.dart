// lib/services/pusher_service.dart - Version corrigée
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../providers/message_provider.dart';
import '../models/message_model.dart';
import '../utils/constants.dart';

class PusherService {
  static final PusherService _instance = PusherService._internal();
  factory PusherService() => _instance;
  PusherService._internal();

  final _storage = const FlutterSecureStorage();
  PusherChannelsFlutter? _pusher;
  bool _isInitialized = false;
  String? _currentUserId;
  bool _isConnecting = false;

  MessageProvider? _messageProvider;

  void setMessageProvider(MessageProvider provider) {
    _messageProvider = provider;
  }

  Future<void> initialize() async {
    if (_isInitialized || _isConnecting) return;

    _isConnecting = true;

    try {
      final userData = await _storage.read(key: 'user_data');
      if (userData != null) {
        final Map<String, dynamic> data = jsonDecode(userData);
        _currentUserId = data['id']?.toString();
      }

      if (_currentUserId == null) {
        _isConnecting = false;
        return;
      }

      _pusher = PusherChannelsFlutter.getInstance();
      
      await _pusher!.init(
        apiKey: 'cab84ca4d5eac6def57e',
        cluster: 'eu',
        onConnectionStateChange: (String currentState, String previousState) {
          debugPrint("Pusher state: $currentState");

          if (currentState == "CONNECTED") {
            _isInitialized = true;
            _isConnecting = false;
          } else if (currentState == "DISCONNECTED") {
            _isInitialized = false;
          }
        },
        onError: (message, code, error) {
          debugPrint("Pusher error: $message");
          _isInitialized = false;
          _isConnecting = false;
        },
        onEvent: _handleEvent,
        authEndpoint: '${AppConstants.apiBaseUrl}/pusher/auth',
      );
      await _pusher!.connect();
      
      await _pusher!.subscribe(
        channelName: 'private-user.$_currentUserId',
        onEvent: _handleEvent,
      );

    } catch (e) {
      print('Erreur Pusher: $e');
      _isInitialized = false;
      _isConnecting = false;
    }
  }

  void _handleEvent(PusherEvent event) {
    try {
      if (event.data == null || event.data!.isEmpty) return;
      
      final data = jsonDecode(event.data!);
      print('Événement reçu: ${event.eventName}');
      
      if (_messageProvider != null && _currentUserId != null) {
        switch (event.eventName) {
          case 'new-message':
            _handleNewMessage(data);
            break;
          case 'typing-indicator':
            _handleTypingIndicator(data);
            break;
        }
      }
    } catch (e) {
      print('Erreur traitement événement: $e');
    }
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final messageData = data['message'] ?? data;
    final conversationId = data['conversation_id']?.toString() ?? 
                          messageData['conversation_id']?.toString() ?? '';
    
    if (conversationId.isNotEmpty && messageData.isNotEmpty) {
      final senderId = messageData['sender_id']?.toString() ?? '';
      if (senderId != _currentUserId) {
        final message = MessageModel.fromJson(messageData, _currentUserId!);
        _messageProvider!.receiveMessage(message, conversationId);
      }
    }
  }

  void _handleTypingIndicator(Map<String, dynamic> data) {
    final userId = data['user_id']?.toString();
    final isTyping = data['is_typing'] == true;
    final conversationId = data['conversation_id']?.toString() ?? '';

    if (userId != null && userId != _currentUserId && conversationId.isNotEmpty) {
      _messageProvider!.setTypingIndicator(conversationId, userId, isTyping);
    }
  }

  Future<void> subscribeToConversation(String conversationId) async {
    if (!_isInitialized) return;
    
    try {
      await _pusher?.subscribe(
        channelName: 'private-conversation.$conversationId',
        onEvent: _handleEvent,
      );
    } catch (e) {
      print('Erreur subscription: $e');
    }
  }

  Future<void> disconnect() async {
    if (_isInitialized) {
      await _pusher?.disconnect();
      _isInitialized = false;
    }
  }
}