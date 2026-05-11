import 'user_model.dart';
import 'message_model.dart';

class ConversationModel {
  final String id;
  final UserModel otherUser;
  final MessageModel? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;
  final String? serviceName;
  final String? entrepriseName;
  final String? serviceId;
  final String? entrepriseId;

  ConversationModel({
    required this.id,
    required this.otherUser,
    this.lastMessage,
    this.unreadCount = 0,
    required this.updatedAt,
    this.serviceName,
    this.entrepriseName,
    this.serviceId,
    this.entrepriseId,
  });

  factory ConversationModel.fromJson(
      Map<String, dynamic> json, String currentUserId) {
        
    Map<String, dynamic>? otherUserJson;

    if (json['other_user'] is Map) {
      otherUserJson = Map<String, dynamic>.from(json['other_user'] as Map);
    } else if (json['user'] is Map) {
      otherUserJson = Map<String, dynamic>.from(json['user'] as Map);
    } else {
      // Déterminer user_one ou user_two selon currentUserId
      final userOneId = json['user_one_id']?.toString() ?? '';
      if (userOneId == currentUserId && json['user_two'] is Map) {
        otherUserJson = Map<String, dynamic>.from(json['user_two'] as Map);
      } else if (json['user_one'] is Map) {
        otherUserJson = Map<String, dynamic>.from(json['user_one'] as Map);
      }
    }

    // ── Dernier message ────────────────────────────────────────────────────
    MessageModel? lastMessage;
    final rawLast = json['last_message'] ?? json['messages'];
    if (rawLast is Map) {
      try {
        lastMessage = MessageModel.fromJson(
            Map<String, dynamic>.from(rawLast), currentUserId);
      } catch (_) {}
    } else if (rawLast is List && rawLast.isNotEmpty) {
      try {
        lastMessage = MessageModel.fromJson(
            Map<String, dynamic>.from(rawLast.first as Map), currentUserId);
      } catch (_) {}
    }

    // ── Nom du service : plusieurs clés possibles selon le backend ──────────
    final serviceName = json['service_name']?.toString()
        ?? (json['service'] is Map ? json['service']['name']?.toString() : null);

    final entrepriseName = json['entreprise_name']?.toString()
        ?? (json['entreprise'] is Map
            ? json['entreprise']['name']?.toString()
            : null);

    return ConversationModel(
      id: json['id']?.toString() ?? '',
      otherUser: otherUserJson != null
          ? UserModel.fromJson(otherUserJson)
          : UserModel(id: '', name: 'Inconnu'),
      lastMessage: lastMessage,
      unreadCount: json['unread_count'] ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      serviceName: serviceName,
      entrepriseName: entrepriseName,
      serviceId: json['service_id']?.toString(),
      entrepriseId: json['entreprise_id']?.toString(),
    );
  }

  String? get contextLabel {
    if (serviceName != null && serviceName!.isNotEmpty) return serviceName;
    if (entrepriseName != null && entrepriseName!.isNotEmpty) {
      return entrepriseName;
    }
    return null;
  }
}