// lib/models/message_model.dart
// ═══════════════════════════════════════════════════════════════════════
// CORRECTIONS:
// 1. isMe : détection robuste via is_me flag ET comparaison sender_id
// 2. Location: détection automatique si lat/lng présents ET type='text'
// 3. Heure: toujours convertie en heure locale du téléphone
// 4. createdAt: gestion correcte UTC → local sans ambiguïté
// ═══════════════════════════════════════════════════════════════════════

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
      id:         json['id']?.toString() ?? '',
      senderId:   json['sender_id']?.toString() ?? '',
      senderName: json['sender']?['name'] ?? 'Inconnu',
      content:    json['content'] ?? '',
      type:       json['type'] ?? 'text',
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
  final DateTime createdAt;     // toujours heure locale téléphone
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

    // ─── Détection isMe robuste ────────────────────────────────────────
    // Priorité 1 : flag explicite is_me du serveur
    // Priorité 2 : comparaison sender_id avec currentUserId
    // Ne jamais retourner true si currentUserId est vide
    bool isMe;
    if (json.containsKey('is_me') && json['is_me'] != null) {
      isMe = json['is_me'] == true;
    } else if (currentUserId.isNotEmpty && senderId.isNotEmpty) {
      isMe = senderId == currentUserId;
    } else {
      isMe = false;
    }

    ReplyToModel? replyTo;
    if (json['reply_to'] != null && json['reply_to'] is Map) {
      try { replyTo = ReplyToModel.fromJson(
          Map<String, dynamic>.from(json['reply_to'] as Map)); } catch (_) {}
    }

    // ─── Parse des coordonnées ──────────────────────────────────────
    final lat = json['latitude']  != null ? double.tryParse(json['latitude'].toString())  : null;
    final lng = json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null;

    // ─── Détection automatique du type 'location' ──────────────────
    String msgType = json['type']?.toString() ?? 'text';
    if (msgType == 'text' && lat != null && lng != null) {
      msgType = 'location';
    }

    // ─── Heure locale ──────────────────────────────────────────────
    // Laravel envoie toujours en UTC (format ISO 8601 sans 'Z' parfois).
    // On force la lecture en UTC puis conversion locale.
    DateTime createdAt = DateTime.now();
    if (json['created_at'] != null) {
      final raw = json['created_at'].toString().trim();
      DateTime? parsed;

      // Essai direct
      parsed = DateTime.tryParse(raw);

      // Si pas de suffix timezone, ajouter 'Z' pour forcer UTC
      if (parsed != null && !raw.contains('Z') && !raw.contains('+') && !raw.contains('-', 10)) {
        parsed = DateTime.tryParse('${raw}Z');
      }

      if (parsed != null) {
        createdAt = parsed.toLocal();
      }
    }

    DateTime? readAt;
    if (json['read_at'] != null) {
      final raw = json['read_at'].toString().trim();
      DateTime? parsed = DateTime.tryParse(raw);
      if (parsed != null && !raw.contains('Z') && !raw.contains('+') && !raw.contains('-', 10)) {
        parsed = DateTime.tryParse('${raw}Z');
      }
      readAt = parsed?.toLocal();
    }

    return MessageModel(
      id:             json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId:       senderId,
      content:        json['content'] ?? json['message'] ?? '',
      type:           msgType,
      fileUrl:        json['file_url'] ?? json['url'],
      filePath:       json['file_path'],
      createdAt:      createdAt,
      readAt:         readAt,
      isMe:           isMe,
      status:         json['status']?.toString(),
      temporaryId:    json['temporary_id']?.toString(),
      latitude:       lat,
      longitude:      lng,
      replyTo:        replyTo,
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
      id:             id             ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId:       senderId       ?? this.senderId,
      content:        content        ?? this.content,
      type:           type           ?? this.type,
      fileUrl:        fileUrl        ?? this.fileUrl,
      filePath:       filePath       ?? this.filePath,
      createdAt:      createdAt      ?? this.createdAt,
      readAt:         readAt         ?? this.readAt,
      isMe:           isMe           ?? this.isMe,
      status:         status         ?? this.status,
      latitude:       latitude       ?? this.latitude,
      longitude:      longitude      ?? this.longitude,
      temporaryId:    temporaryId    ?? this.temporaryId,
      replyTo:        replyTo        ?? this.replyTo,
    );
  }
}