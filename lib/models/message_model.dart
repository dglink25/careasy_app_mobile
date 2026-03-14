// models/message_model.dart
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
  });

  factory MessageModel.fromJson(Map<String, dynamic> json, String currentUserId) {
    final senderId = json['sender_id']?.toString() ?? json['user_id']?.toString() ?? '';
    
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
      isMe: senderId == currentUserId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'type': type,
      'file_url': fileUrl,
      'file_path': filePath,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
    };
  }
}