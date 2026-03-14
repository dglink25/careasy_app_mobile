// models/conversation_model.dart
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

  factory ConversationModel.fromJson(Map<String, dynamic> json, String currentUserId) {
    return ConversationModel(
      id: json['id']?.toString() ?? '',
      otherUser: UserModel.fromJson(json['other_user'] ?? json['user'] ?? {}),
      lastMessage: json['last_message'] != null
          ? MessageModel.fromJson(json['last_message'], currentUserId)
          : null,
      unreadCount: json['unread_count'] ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      serviceName: json['service_name'],
      entrepriseName: json['entreprise_name'],
      serviceId: json['service_id']?.toString(),
      entrepriseId: json['entreprise_id']?.toString(),
    );
  }
}