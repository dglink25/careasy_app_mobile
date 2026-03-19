import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';

/// Singleton — un seul polling global pour toute l'app
class MessagePollingService {
  static final MessagePollingService _instance = MessagePollingService._internal();
  factory MessagePollingService() => _instance;
  MessagePollingService._internal();

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  // ── État interne ──────────────────────────────────────────────────────
  Timer? _pollingTimer;
  Timer? _conversationTimer;
  bool _isPolling = false;
  String? _currentUserId;

  // Derniers IDs connus par conversation pour détecter les nouveaux messages
  // { conversationId: lastMessageId }
  final Map<String, String> _lastKnownMessageIds = {};
  // Timestamp du dernier message connu par conversation
  final Map<String, DateTime> _lastKnownTimestamps = {};

  // ID de la conversation actuellement ouverte (pour ne PAS notifier si on y est)
  String? _activeConversationId;

  // Callback appelé quand un nouveau message arrive
  // Le provider peut s'y abonner
  final List<Function(List<ConversationModel>)> _conversationListeners = [];
  final Map<String, List<Function(List<MessageModel>)>> _messageListeners = {};

  // ── Getters ───────────────────────────────────────────────────────────
  bool get isRunning => _pollingTimer?.isActive ?? false;
  String? get activeConversationId => _activeConversationId;

  // ── Configuration ─────────────────────────────────────────────────────

  /// Définit la conversation active (pas de notification pour celle-ci)
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
    debugPrint('[Polling] Conversation active: $conversationId');
  }

  /// Abonne un listener aux nouvelles conversations
  void addConversationListener(Function(List<ConversationModel>) listener) {
    _conversationListeners.add(listener);
  }

  void removeConversationListener(Function(List<ConversationModel>) listener) {
    _conversationListeners.remove(listener);
  }

  /// Abonne un listener aux nouveaux messages d'une conversation
  void addMessageListener(String convId, Function(List<MessageModel>) listener) {
    _messageListeners[convId] ??= [];
    _messageListeners[convId]!.add(listener);
  }

  void removeMessageListener(String convId, Function(List<MessageModel>) listener) {
    _messageListeners[convId]?.remove(listener);
  }

  // ── Démarrage / Arrêt ─────────────────────────────────────────────────

  Future<void> start() async {
    if (_isPolling) {
      debugPrint('[Polling] Déjà en cours');
      return;
    }

    await _loadUserId();
    if (_currentUserId == null) {
      debugPrint('[Polling] Pas de userId → abandon');
      return;
    }

    _isPolling = true;
    debugPrint('[Polling] ▶ Démarrage (userId=$_currentUserId)');

    // Premier appel immédiat pour initialiser les baselines
    await _initBaselines();

    // Polling conversations toutes les 5 secondes
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollNewMessages(),
    );

    debugPrint('[Polling] ✓ Timer démarré (5s)');
  }

  void stop() {
    _pollingTimer?.cancel();
    _conversationTimer?.cancel();
    _pollingTimer = null;
    _conversationTimer = null;
    _isPolling = false;
    debugPrint('[Polling] ■ Arrêté');
  }

  void restart() {
    stop();
    start();
  }

  // ── Initialisation des baselines ──────────────────────────────────────

  /// Charge les conversations initiales SANS notifier (baseline)
  Future<void> _initBaselines() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        for (final item in list) {
          final convId = item['id']?.toString() ?? '';
          final lastMsg = item['last_message'];
          if (lastMsg != null && convId.isNotEmpty) {
            _lastKnownMessageIds[convId] = lastMsg['id']?.toString() ?? '';
            final ts = lastMsg['created_at'];
            if (ts != null) {
              _lastKnownTimestamps[convId] = DateTime.tryParse(ts.toString())?.toLocal() ?? DateTime.now();
            }
          }
        }
        debugPrint('[Polling] Baselines initialisées: ${_lastKnownMessageIds.length} conversations');
      }
    } catch (e) {
      debugPrint('[Polling] Erreur init baselines: $e');
    }
  }

  // ── Boucle de polling principale ──────────────────────────────────────

  Future<void> _pollNewMessages() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) {
        debugPrint('[Polling] Token absent → arrêt');
        stop();
        return;
      }

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversations'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 401) {
        debugPrint('[Polling] 401 → arrêt');
        stop();
        return;
      }

      if (resp.statusCode != 200) return;

      final list = jsonDecode(resp.body) as List;
      final conversations = list.map((item) {
        return ConversationModel.fromJson(item, _currentUserId ?? '');
      }).toList();

      // Notifier les listeners de la liste des conversations
      for (final listener in _conversationListeners) {
        listener(conversations);
      }

      // Détecter les nouveaux messages
      for (final conv in conversations) {
        await _checkForNewMessages(conv, token);
      }

    } catch (e) {
      debugPrint('[Polling] Erreur: $e');
    }
  }

  /// Vérifie si une conversation a de nouveaux messages depuis la dernière vérification
  Future<void> _checkForNewMessages(ConversationModel conv, String token) async {
    final convId = conv.id;
    final lastMsg = conv.lastMessage;

    if (lastMsg == null) return;

    final lastKnownId = _lastKnownMessageIds[convId];
    final lastKnownTs = _lastKnownTimestamps[convId];

    // Nouveau message détecté si l'ID est différent
    final isNew = lastKnownId == null ||
        (lastMsg.id != lastKnownId &&
         lastMsg.id != 'temp_${lastMsg.createdAt.millisecondsSinceEpoch}');

    // Ou si le timestamp est plus récent
    final isNewer = lastKnownTs != null && lastMsg.createdAt.isAfter(lastKnownTs);

    if (!isNew && !isNewer) return;

    // Mettre à jour la baseline
    _lastKnownMessageIds[convId] = lastMsg.id;
    _lastKnownTimestamps[convId] = lastMsg.createdAt;

    // Si c'est MON message, pas de notification
    if (lastMsg.isMe) return;

    // Si la conversation est active à l'écran, pas de notification
    if (_activeConversationId == convId) {
      debugPrint('[Polling] Nouveau message dans conv active $convId → pas de notif');
      // Mais on récupère quand même les messages pour l'UI
      await _fetchAndNotifyMessages(convId, token);
      return;
    }

    debugPrint('[Polling] 🔔 Nouveau message détecté: conv=$convId');

    // Récupérer les messages complets si des listeners sont abonnés
    if (_messageListeners.containsKey(convId)) {
      await _fetchAndNotifyMessages(convId, token);
    }

    // ⭐ Déclencher la notification push locale
    await _triggerNotification(conv, lastMsg);
  }

  /// Récupère les messages d'une conversation et notifie les listeners
  Future<void> _fetchAndNotifyMessages(String convId, String token) async {
    final listeners = _messageListeners[convId];
    if (listeners == null || listeners.isEmpty) return;

    try {
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawMsgs = data['messages'] ?? data['data'] ?? [];
        final msgs = (rawMsgs as List).map((m) {
          return MessageModel.fromJson(m is Map<String, dynamic> ? m : Map<String, dynamic>.from(m), _currentUserId ?? '');
        }).toList();

        for (final listener in List.from(listeners)) {
          listener(msgs);
        }
      }
    } catch (e) {
      debugPrint('[Polling] Erreur fetchMessages($convId): $e');
    }
  }

  /// Déclenche une notification locale pour un nouveau message
  Future<void> _triggerNotification(ConversationModel conv, MessageModel lastMsg) async {
    try {
      final senderName = conv.otherUser.name;
      String body;

      switch (lastMsg.type) {
        case 'image':    body = '📷 Image'; break;
        case 'video':    body = '🎥 Vidéo'; break;
        case 'audio':
        case 'vocal':    body = '🎤 Message vocal'; break;
        case 'document': body = '📄 Document'; break;
        case 'location': body = '📍 Localisation'; break;
        default:
          body = lastMsg.content.isNotEmpty ? lastMsg.content : 'Nouveau message';
      }

      await NotificationService().showMessageNotification(
        senderName: senderName,
        messageBody: body,
        conversationId: conv.id,
        senderPhoto: conv.otherUser.photoUrl,
        senderId: conv.otherUser.id,
      );

      debugPrint('[Polling] ✅ Notification envoyée: $senderName → $body');
    } catch (e) {
      debugPrint('[Polling] Erreur notification: $e');
    }
  }

  // ── Utilitaires ───────────────────────────────────────────────────────

  Future<void> _loadUserId() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty) {
        _currentUserId = (jsonDecode(raw) as Map<String, dynamic>)['id']?.toString();
      }
    } catch (e) {
      debugPrint('[Polling] _loadUserId: $e');
    }
  }

  /// Réinitialise la baseline pour une conversation (ex: après l'avoir ouverte)
  Future<void> resetBaselineForConversation(String convId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/$convId'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawMsgs = data['messages'] ?? data['data'] ?? [];
        if ((rawMsgs as List).isNotEmpty) {
          final lastMsg = rawMsgs.last;
          _lastKnownMessageIds[convId] = lastMsg['id']?.toString() ?? '';
          final ts = lastMsg['created_at'];
          if (ts != null) {
            _lastKnownTimestamps[convId] = DateTime.tryParse(ts.toString())?.toLocal() ?? DateTime.now();
          }
        }
      }
    } catch (e) {
      debugPrint('[Polling] resetBaseline($convId): $e');
    }
  }

  /// Force un poll immédiat (ex: après envoi d'un message)
  Future<void> pollNow() async {
    await _pollNewMessages();
  }

  void dispose() {
    stop();
    _conversationListeners.clear();
    _messageListeners.clear();
  }
}