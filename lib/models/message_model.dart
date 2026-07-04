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
  final String? localFilePath; // chemin disque local après téléchargement
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
    this.localFilePath,
    required this.createdAt,
    this.readAt,
    required this.isMe,
    this.status,
    this.latitude,
    this.longitude,
    this.temporaryId,
    this.replyTo,
  });

  /// URL/chemin à utiliser pour la lecture :
  ///   1. fichier local s'il existe
  ///   2. sinon URL réseau
  String? get effectiveMediaUrl {
    if (localFilePath != null && localFilePath!.isNotEmpty) {
      return localFilePath;
    }
    return fileUrl;
  }

  bool get hasLocalMedia =>
      localFilePath != null && localFilePath!.isNotEmpty;

  factory MessageModel.fromJson(Map<String, dynamic> json, String currentUserId) {
    final senderId = json['sender_id']?.toString() ?? json['user_id']?.toString() ?? '';


    bool isMe;
    if (currentUserId.isNotEmpty && senderId.isNotEmpty) {
      // Toujours recalculer depuis sender_id — plus fiable que is_me du JSON
      // (is_me dans Pusher est calculé du point de vue de l'émetteur, pas du récepteur)
      isMe = senderId == currentUserId;
    } else if (json.containsKey('is_me') && json['is_me'] != null) {
      // Fallback uniquement si on n'a pas le currentUserId
      isMe = json['is_me'] == true;
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

    DateTime createdAt = DateTime.now();
    if (json['created_at'] != null) {
      createdAt = _parseDate(json['created_at'].toString()) ?? DateTime.now();
    }

    DateTime? readAt;
    if (json['read_at'] != null) {
      readAt = _parseDate(json['read_at'].toString());
    }

    return MessageModel(
      id:             json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId:       senderId,
      content:        json['content'] ?? json['message'] ?? '',
      type:           msgType,
      fileUrl:        json['file_url'] ?? json['url'],
      filePath:       json['file_path'],
      localFilePath:  json['local_file_path'],
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

  /// Parse une chaîne de date depuis l'API et retourne un DateTime local.
  ///
  /// Gère les formats :
  ///   • ISO 8601 avec Z ou offset  : "2026-06-18T19:40:05Z"  → UTC → toLocal()
  ///   • Chaîne sans suffixe (legacy): "2026-06-18 20:40:05"  → traitée comme UTC
  ///     (avec le fix backend BaseModel, ce cas ne devrait plus arriver)
  static DateTime? _parseDate(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) return null;

    // 1. Essai direct — fonctionne avec Z, +HH:MM, etc.
    DateTime? dt = DateTime.tryParse(raw);
    if (dt != null) return dt.toLocal();

    // 2. Remplacer l'espace par T (format MySQL/PostgreSQL sans T)
    final withT = raw.replaceFirst(' ', 'T');
    dt = DateTime.tryParse(withT);
    if (dt != null) return dt.toLocal();

    // 3. Chaîne sans suffixe timezone → supposer UTC (comportement du nouveau backend)
    dt = DateTime.tryParse('${withT}Z');
    if (dt != null) return dt.toLocal();

    return null;
  }

  MessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    String? type,
    String? fileUrl,
    String? filePath,
    String? localFilePath,
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
      id            : id             ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId      : senderId       ?? this.senderId,
      content       : content        ?? this.content,
      type          : type           ?? this.type,
      fileUrl       : fileUrl        ?? this.fileUrl,
      filePath      : filePath       ?? this.filePath,
      localFilePath : localFilePath  ?? this.localFilePath,
      createdAt     : createdAt      ?? this.createdAt,
      readAt        : readAt         ?? this.readAt,
      isMe          : isMe           ?? this.isMe,
      status        : status         ?? this.status,
      latitude      : latitude       ?? this.latitude,
      longitude     : longitude      ?? this.longitude,
      temporaryId   : temporaryId    ?? this.temporaryId,
      replyTo       : replyTo        ?? this.replyTo,
    );
  }
}