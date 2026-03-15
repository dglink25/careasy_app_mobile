// models/message_model.dart
class ReplyToModel {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final String type;

  ReplyToModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.type,
  });

  factory ReplyToModel.fromJson(Map<String, dynamic> json) {
    return ReplyToModel(
      id: json['id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender']?['name'] ?? 'Inconnu',
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
    );
  }
}

class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String type;
  final String? fileUrl;
  final String? filePath;
  final DateTime createdAt;
  final DateTime? readAt;
  final bool isMe;
  final String? status;
  final double? latitude;
  final double? longitude;
  final String? temporaryId;
  final ReplyToModel? replyTo;

  MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.type,
    this.fileUrl,
    this.filePath,
    required this.createdAt,
    this.readAt,
    required this.isMe,
    this.status,
    this.latitude,
    this.longitude,
    this.temporaryId,
    this.replyTo,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json, String currentUserId) {
    final senderId = json['sender_id']?.toString() ?? json['user_id']?.toString() ?? '';

    // Priorité à is_me si fourni par le serveur (ex: sendMessageMobile retourne is_me: true)
    bool isMe;
    if (json.containsKey('is_me') && json['is_me'] != null) {
      isMe = json['is_me'] == true;
    } else if (currentUserId.isNotEmpty) {
      isMe = senderId == currentUserId;
    } else {
      isMe = false;
    }

    ReplyToModel? replyTo;
    if (json['reply_to'] != null && json['reply_to'] is Map) {
      try {
        replyTo = ReplyToModel.fromJson(json['reply_to']);
      } catch (_) {}
    }

    return MessageModel(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: senderId,
      content: json['content'] ?? json['message'] ?? '',
      type: json['type'] ?? 'text',
      fileUrl: json['file_url'] ?? json['url'],
      filePath: json['file_path'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'].toString())
          : null,
      isMe: isMe,
      temporaryId: json['temporary_id'],
      latitude: json['latitude'] != null
          ? double.tryParse(json['latitude'].toString())
          : null,
      longitude: json['longitude'] != null
          ? double.tryParse(json['longitude'].toString())
          : null,
      replyTo: replyTo,
    );
  }

  MessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    String? type,
    String? fileUrl,
    String? filePath,
    DateTime? createdAt,
    DateTime? readAt,
    bool? isMe,
    String? status,
    double? latitude,
    double? longitude,
    String? temporaryId,
    ReplyToModel? replyTo,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      fileUrl: fileUrl ?? this.fileUrl,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      isMe: isMe ?? this.isMe,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      temporaryId: temporaryId ?? this.temporaryId,
      replyTo: replyTo ?? this.replyTo,
    );
  }
}