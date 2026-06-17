import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../models/user_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ChatLocalDb — base SQLite locale pour messages + conversations
//
//  Principe :
//   • Ouverture du chat  → afficher immédiatement le cache, puis rafraîchir
//     silencieusement depuis l'API (stratégie cache-first).
//   • Envoi optimiste    → insérer le message temp en base; remplacer à la
//     confirmation serveur.
//   • Modification/supp  → patcher en base sans recharger tous les messages.
//   • Conversations       → stocker l'aperçu (dernier message + unread) pour
//     afficher la liste instantanément au démarrage.
// ─────────────────────────────────────────────────────────────────────────────

class ChatLocalDb {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final ChatLocalDb _i = ChatLocalDb._();
  factory ChatLocalDb() => _i;
  ChatLocalDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  // ── Ouverture / migrations ─────────────────────────────────────────────────

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'careasy_chat_v2.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (d) async => await d.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _onCreate(Database d, int version) async {
    await d.execute('''
      CREATE TABLE messages (
        id             TEXT    PRIMARY KEY,
        conversation_id TEXT   NOT NULL,
        sender_id      TEXT    NOT NULL,
        content        TEXT    NOT NULL DEFAULT '',
        type           TEXT    NOT NULL DEFAULT 'text',
        file_url       TEXT,
        file_path      TEXT,
        latitude       REAL,
        longitude      REAL,
        read_at        TEXT,
        is_me          INTEGER NOT NULL DEFAULT 0,
        status         TEXT    DEFAULT 'sent',
        temporary_id   TEXT,
        reply_to_json  TEXT,
        created_at     TEXT    NOT NULL
      )
    ''');

    await d.execute('''
      CREATE INDEX idx_messages_conv
        ON messages(conversation_id, created_at)
    ''');

    await d.execute('''
      CREATE TABLE conversations (
        id              TEXT PRIMARY KEY,
        other_user_json TEXT NOT NULL,
        last_msg_json   TEXT,
        unread_count    INTEGER NOT NULL DEFAULT 0,
        updated_at      TEXT    NOT NULL,
        service_name    TEXT,
        entreprise_name TEXT,
        service_id      TEXT,
        entreprise_id   TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database d, int oldV, int newV) async {
    if (oldV < 2) {
      // Migration v1 → v2 : ajout colonne reply_to_json si elle manque
      try {
        await d.execute('ALTER TABLE messages ADD COLUMN reply_to_json TEXT');
      } catch (_) {} // colonne déjà présente sur une install fraîche
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  MESSAGES
  // ──────────────────────────────────────────────────────────────────────────

  /// Insère ou remplace une liste de messages (upsert).
  Future<void> saveMessages(String convId, List<MessageModel> msgs) async {
    if (msgs.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final m in msgs) {
      batch.insert(
        'messages',
        _msgToRow(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Insère/remplace un seul message.
  Future<void> saveMessage(MessageModel m) async {
    final d = await db;
    await d.insert(
      'messages',
      _msgToRow(m),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Charge les N derniers messages d'une conversation (cache-first).
  /// [limit] = 60 par défaut — assez pour remplir un écran sans lag.
  Future<List<MessageModel>> loadMessages(
    String convId, {
    int limit = 60,
    String currentUserId = '',
  }) async {
    final d = await db;
    final rows = await d.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [convId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.reversed
        .map((r) => _rowToMsg(r, currentUserId))
        .toList();
  }

  /// Charge une page supplémentaire (pagination infinie vers le haut).
  Future<List<MessageModel>> loadOlderMessages(
    String convId, {
    required String beforeId,
    int limit = 30,
    String currentUserId = '',
  }) async {
    final d = await db;
    // Trouver la date du message pivot
    final pivot = await d.query(
      'messages',
      columns: ['created_at'],
      where: 'id = ?',
      whereArgs: [beforeId],
      limit: 1,
    );
    if (pivot.isEmpty) return [];
    final pivotDate = pivot.first['created_at'] as String;

    final rows = await d.query(
      'messages',
      where: 'conversation_id = ? AND created_at < ?',
      whereArgs: [convId, pivotDate],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.reversed
        .map((r) => _rowToMsg(r, currentUserId))
        .toList();
  }

  /// Met à jour le contenu d'un message (edit).
  Future<void> updateMessageContent(String id, String newContent) async {
    final d = await db;
    await d.update(
      'messages',
      {'content': newContent},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Supprime un message.
  Future<void> deleteMessage(String id) async {
    final d = await db;
    await d.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  /// Supprime tous les messages d'une conversation (ex: conversation supprimée).
  Future<void> deleteConversationMessages(String convId) async {
    final d = await db;
    await d.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [convId],
    );
  }

  /// Met à jour le statut d'un message (sending → sent → error).
  Future<void> updateMessageStatus(String id, String status) async {
    final d = await db;
    await d.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remplace un message temporaire par sa version confirmée.
  Future<void> confirmMessage(String tempId, MessageModel confirmed) async {
    final d = await db;
    await d.delete('messages', where: 'id = ?', whereArgs: [tempId]);
    await d.insert(
      'messages',
      _msgToRow(confirmed),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marque tous les messages reçus d'une conv comme lus.
  Future<void> markAllRead(String convId) async {
    final d = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(
      'messages',
      {'read_at': now},
      where: 'conversation_id = ? AND is_me = 0 AND read_at IS NULL',
      whereArgs: [convId],
    );
  }

  /// Marque nos messages comme lus par l'autre (read receipts).
  Future<void> markSentMessagesRead(String convId) async {
    final d = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(
      'messages',
      {'read_at': now},
      where: 'conversation_id = ? AND is_me = 1 AND read_at IS NULL',
      whereArgs: [convId],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  CONVERSATIONS
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> saveConversations(List<ConversationModel> convs) async {
    if (convs.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final c in convs) {
      batch.insert(
        'conversations',
        _convToRow(c),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveConversation(ConversationModel c) async {
    final d = await db;
    await d.insert(
      'conversations',
      _convToRow(c),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ConversationModel>> loadConversations(
      String currentUserId) async {
    final d = await db;
    final rows = await d.query(
      'conversations',
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((r) => _rowToConv(r, currentUserId))
        .toList();
  }

  Future<void> updateConversationLastMessage(
    String convId,
    MessageModel msg,
    int unreadCount,
  ) async {
    final d = await db;
    await d.update(
      'conversations',
      {
        'last_msg_json': jsonEncode(_msgToRow(msg)),
        'unread_count' : unreadCount,
        'updated_at'   : msg.createdAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [convId],
    );
  }

  Future<void> resetUnreadCount(String convId) async {
    final d = await db;
    await d.update(
      'conversations',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [convId],
    );
  }

  Future<void> deleteConversation(String convId) async {
    final d = await db;
    await d.delete('conversations', where: 'id = ?', whereArgs: [convId]);
    await deleteConversationMessages(convId);
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  SÉRIALISATION
  // ──────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _msgToRow(MessageModel m) => {
    'id'             : m.id,
    'conversation_id': m.conversationId,
    'sender_id'      : m.senderId,
    'content'        : m.content,
    'type'           : m.type,
    'file_url'       : m.fileUrl,
    'file_path'      : m.filePath,
    'latitude'       : m.latitude,
    'longitude'      : m.longitude,
    'read_at'        : m.readAt?.toIso8601String(),
    'is_me'          : m.isMe ? 1 : 0,
    'status'         : m.status ?? 'sent',
    'temporary_id'   : m.temporaryId,
    'reply_to_json'  : m.replyTo != null ? jsonEncode({
      'id'        : m.replyTo!.id,
      'sender_id' : m.replyTo!.senderId,
      'sender_name': m.replyTo!.senderName,
      'content'   : m.replyTo!.content,
      'type'      : m.replyTo!.type,
    }) : null,
    'created_at'     : m.createdAt.toIso8601String(),
  };

  MessageModel _rowToMsg(Map<String, dynamic> r, String currentUserId) {
    ReplyToModel? replyTo;
    if (r['reply_to_json'] != null) {
      try {
        final j = jsonDecode(r['reply_to_json'] as String)
            as Map<String, dynamic>;
        replyTo = ReplyToModel(
          id        : j['id']          ?? '',
          senderId  : j['sender_id']   ?? '',
          senderName: j['sender_name'] ?? '',
          content   : j['content']     ?? '',
          type      : j['type']        ?? 'text',
        );
      } catch (_) {}
    }

    return MessageModel(
      id            : r['id'] as String,
      conversationId: r['conversation_id'] as String,
      senderId      : r['sender_id'] as String,
      content       : r['content'] as String? ?? '',
      type          : r['type'] as String? ?? 'text',
      fileUrl       : r['file_url'] as String?,
      filePath      : r['file_path'] as String?,
      latitude      : r['latitude'] != null
          ? (r['latitude'] as num).toDouble() : null,
      longitude     : r['longitude'] != null
          ? (r['longitude'] as num).toDouble() : null,
      readAt        : r['read_at'] != null
          ? DateTime.tryParse(r['read_at'] as String)?.toLocal() : null,
      isMe          : (r['is_me'] as int? ?? 0) == 1,
      status        : r['status'] as String?,
      temporaryId   : r['temporary_id'] as String?,
      replyTo       : replyTo,
      createdAt     : DateTime.tryParse(r['created_at'] as String)?.toLocal()
          ?? DateTime.now(),
    );
  }

  Map<String, dynamic> _convToRow(ConversationModel c) => {
    'id'             : c.id,
    'other_user_json': jsonEncode({
      'id'      : c.otherUser.id,
      'name'    : c.otherUser.name,
      'email'   : c.otherUser.email,
      'photoUrl': c.otherUser.photoUrl,
      'isOnline': c.otherUser.isOnline,
      'lastSeen': c.otherUser.lastSeen?.toIso8601String(),
      'role'    : c.otherUser.role,
      'phone'   : c.otherUser.phone,
    }),
    'last_msg_json'  : c.lastMessage != null
        ? jsonEncode(_msgToRow(c.lastMessage!)) : null,
    'unread_count'   : c.unreadCount,
    'updated_at'     : c.updatedAt.toIso8601String(),
    'service_name'   : c.serviceName,
    'entreprise_name': c.entrepriseName,
    'service_id'     : c.serviceId,
    'entreprise_id'  : c.entrepriseId,
  };

  ConversationModel _rowToConv(
      Map<String, dynamic> r, String currentUserId) {
    UserModel otherUser;
    try {
      final j = jsonDecode(r['other_user_json'] as String)
          as Map<String, dynamic>;
      DateTime? lastSeen;
      if (j['lastSeen'] != null) {
        lastSeen = DateTime.tryParse(j['lastSeen'] as String)?.toLocal();
      }
      otherUser = UserModel(
        id      : j['id']?.toString() ?? '',
        name    : j['name']?.toString() ?? '',
        email   : j['email']?.toString(),
        photoUrl: j['photoUrl']?.toString(),
        isOnline: j['isOnline'] == true,
        lastSeen: lastSeen,
        role    : j['role']?.toString(),
        phone   : j['phone']?.toString(),
      );
    } catch (_) {
      otherUser = UserModel(id: '', name: 'Inconnu');
    }

    MessageModel? lastMsg;
    if (r['last_msg_json'] != null) {
      try {
        final j = jsonDecode(r['last_msg_json'] as String)
            as Map<String, dynamic>;
        lastMsg = _rowToMsg(j, currentUserId);
      } catch (_) {}
    }

    return ConversationModel(
      id            : r['id'] as String,
      otherUser     : otherUser,
      lastMessage   : lastMsg,
      unreadCount   : r['unread_count'] as int? ?? 0,
      updatedAt     : DateTime.tryParse(r['updated_at'] as String)?.toLocal()
          ?? DateTime.now(),
      serviceName   : r['service_name'] as String?,
      entrepriseName: r['entreprise_name'] as String?,
      serviceId     : r['service_id'] as String?,
      entrepriseId  : r['entreprise_id'] as String?,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  UTILITAIRES
  // ──────────────────────────────────────────────────────────────────────────

  /// Vide tout (déconnexion utilisateur).
  Future<void> clearAll() async {
    final d = await db;
    await d.delete('messages');
    await d.delete('conversations');
    debugPrint('[ChatLocalDb] base vidée');
  }

  /// Nombre de messages stockés pour une conversation.
  Future<int> messageCount(String convId) async {
    final d = await db;
    final r = await d.rawQuery(
      'SELECT COUNT(*) as cnt FROM messages WHERE conversation_id = ?',
      [convId],
    );
    return (r.first['cnt'] as int?) ?? 0;
  }
}
