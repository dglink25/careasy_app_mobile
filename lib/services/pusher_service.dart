// services/pusher_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
          debugPrint('Pusher state: $currentState');
          if (currentState == 'CONNECTED') {
            _isInitialized = true;
            _isConnecting = false;
          } else if (currentState == 'DISCONNECTED') {
            _isInitialized = false;
          }
        },
        onError: (message, code, error) {
          debugPrint('Pusher error: $message');
          _isInitialized = false;
          _isConnecting = false;
        },
        onEvent: _handleEvent,
        authEndpoint: '${AppConstants.apiBaseUrl}/pusher/auth',
      );

      await _pusher!.connect();

      // S'abonner au canal privé de l'utilisateur
      await _pusher!.subscribe(
        channelName: 'private-user.$_currentUserId',
        onEvent: _handleEvent,
      );
    } catch (e) {
      debugPrint('Erreur Pusher: $e');
      _isInitialized = false;
      _isConnecting = false;
    }
  }

  void _handleEvent(PusherEvent event) {
    try {
      if (event.data == null || event.data!.isEmpty) return;

      final data = jsonDecode(event.data!);
      debugPrint('Événement Pusher reçu: ${event.eventName}');

      if (_messageProvider == null || _currentUserId == null) return;

      switch (event.eventName) {
        case 'new-message':
          _handleNewMessage(data);
          break;
        case 'typing-indicator':
          _handleTypingIndicator(data);
          break;
        case 'user-status':
          _handleUserStatus(data);
          break;
        case 'messages-read':
          _handleMessagesRead(data);
          break;
      }
    } catch (e) {
      debugPrint('Erreur traitement événement Pusher: $e');
    }
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final messageData =
        (data['message'] is Map) ? data['message'] as Map<String, dynamic> : data;
    final conversationId =
        data['conversation_id']?.toString() ??
        messageData['conversation_id']?.toString() ??
        '';

    if (conversationId.isEmpty) return;

    final senderId = messageData['sender_id']?.toString() ?? '';

    // Ne pas re-afficher nos propres messages (déjà ajoutés en optimiste)
    if (senderId == _currentUserId) return;

    final message = MessageModel.fromJson(
      Map<String, dynamic>.from(messageData),
      _currentUserId!,
    );
    _messageProvider!.receiveMessage(message, conversationId);
  }

  void _handleTypingIndicator(Map<String, dynamic> data) {
    final userId = data['user_id']?.toString();
    final isTyping = data['is_typing'] == true;
    final conversationId = data['conversation_id']?.toString() ?? '';

    if (userId == null || userId == _currentUserId || conversationId.isEmpty) {
      return;
    }

    _messageProvider!.setTypingIndicator(conversationId, userId, isTyping);
  }

  /// Met à jour le statut en ligne d'un utilisateur en temps réel
  void _handleUserStatus(Map<String, dynamic> data) {
    final userId = data['user_id']?.toString();
    final isOnline = data['is_online'] == true;
    final lastSeenRaw = data['last_seen'];

    if (userId == null) return;

    DateTime? lastSeen;
    if (lastSeenRaw != null) {
      lastSeen = DateTime.tryParse(lastSeenRaw.toString());
    }

    _messageProvider!.updateUserOnlineStatus(userId, isOnline, lastSeen);
  }

  void _handleMessagesRead(Map<String, dynamic> data) {
    // Optionnel : mettre à jour les coches de lecture dans la conversation
    debugPrint('Messages lus dans conv ${data['conversation_id']}');
  }

  Future<void> subscribeToConversation(String conversationId) async {
    if (!_isInitialized) return;
    try {
      await _pusher?.subscribe(
        channelName: 'private-conversation.$conversationId',
        onEvent: _handleEvent,
      );
    } catch (e) {
      debugPrint('Erreur subscription conversation: $e');
    }
  }

  Future<void> disconnect() async {
    if (_isInitialized) {
      await _pusher?.disconnect();
      _isInitialized = false;
    }
  }
}