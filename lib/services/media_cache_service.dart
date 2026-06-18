import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'chat_local_db.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MediaCacheService
//
//  Télécharge en arrière-plan chaque média reçu (image / vidéo / audio /
//  document) et met à jour le chemin local dans SQLite (colonne file_path).
//
//  Règle de lecture :
//    1. file_path non null ET fichier présent  → lecture locale (hors-ligne OK)
//    2. sinon                                  → lecture depuis file_url (réseau)
//
//  Taille maximale par fichier : 100 Mo (même limite que le serveur).
//  Les fichiers sont stockés dans :
//    <appDocDir>/careasy_media/<convId>/<type>/<msgId>.<ext>
// ─────────────────────────────────────────────────────────────────────────────

class MediaCacheService {
  static final MediaCacheService _i = MediaCacheService._();
  factory MediaCacheService() => _i;
  MediaCacheService._();

  // Limite téléchargements simultanés pour ne pas saturer la bande passante
  static const int _maxConcurrent = 3;
  static const int _maxFileSizeBytes = 100 * 1024 * 1024; // 100 Mo

  final ChatLocalDb _db = ChatLocalDb();

  // File d'attente interne
  final List<_DownloadTask> _queue   = [];
  final Set<String>         _active  = {}; // msgIds en cours
  final Set<String>         _done    = {}; // msgIds déjà téléchargés
  int _running = 0;

  // ── API publique ──────────────────────────────────────────────────────────

  /// Déclenche le téléchargement d'un média si pas encore en cache.
  /// Fire-and-forget — ne bloque jamais l'UI.
  void enqueue({
    required String msgId,
    required String convId,
    required String url,
    required String type, // 'image' | 'video' | 'audio' | 'vocal' | 'document'
    int priority = 5,     // 1 = haute (image visible à l'écran), 10 = basse
  }) {
    // Ignorer les URLs locales (déjà sur disque) ou vides
    if (url.isEmpty || !url.startsWith('http')) return;
    if (_done.contains(msgId) || _active.contains(msgId)) return;

    _queue.add(_DownloadTask(
      msgId   : msgId,
      convId  : convId,
      url     : url,
      type    : type,
      priority: priority,
    ));
    _queue.sort((a, b) => a.priority.compareTo(b.priority));
    _pump();
  }

  /// Annule tous les téléchargements en attente (ex : écran fermé).
  void cancelAll() {
    _queue.clear();
  }

  /// Retourne le chemin local du fichier si disponible, sinon null.
  static Future<String?> localPath({
    required String msgId,
    required String convId,
    required String type,
    required String url,
  }) async {
    final ext  = _extFromUrl(url);
    final file = await _file(convId, type, msgId, ext);
    if (await file.exists()) return file.path;
    return null;
  }

  /// Vérifie si un fichier est déjà en cache (synchrone — basé sur le
  /// chemin reconstruit, pas de syscall).
  static Future<bool> isCached({
    required String msgId,
    required String convId,
    required String type,
    required String url,
  }) async {
    final path = await localPath(
        msgId: msgId, convId: convId, type: type, url: url);
    return path != null;
  }

  // ── Pompe interne ─────────────────────────────────────────────────────────

  void _pump() {
    while (_running < _maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      if (_done.contains(task.msgId) || _active.contains(task.msgId)) continue;
      _active.add(task.msgId);
      _running++;
      _download(task).then((_) {
        _active.remove(task.msgId);
        _running--;
        _pump();
      });
    }
  }

  Future<void> _download(_DownloadTask task) async {
    try {
      final ext  = _extFromUrl(task.url);
      final file = await _file(task.convId, task.type, task.msgId, ext);

      // Déjà sur disque (ex: appel redondant après redémarrage)
      if (await file.exists()) {
        _done.add(task.msgId);
        await _db.updateMessageLocalPath(task.msgId, file.path);
        return;
      }

      // Créer le répertoire parent
      await file.parent.create(recursive: true);

      // Téléchargement
      final resp = await http
          .get(Uri.parse(task.url))
          .timeout(const Duration(minutes: 5));

      if (resp.statusCode != 200) {
        debugPrint('[MediaCache] HTTP ${resp.statusCode} pour ${task.url}');
        return;
      }

      // Refuser les fichiers trop lourds
      if (resp.bodyBytes.length > _maxFileSizeBytes) {
        debugPrint('[MediaCache] Fichier trop lourd (${resp.bodyBytes.length} bytes)');
        return;
      }

      await file.writeAsBytes(resp.bodyBytes, flush: true);
      _done.add(task.msgId);

      // Mettre à jour SQLite
      await _db.updateMessageLocalPath(task.msgId, file.path);
      debugPrint('[MediaCache] ✓ ${task.type} msgId=${task.msgId} → ${file.path}');
    } catch (e) {
      debugPrint('[MediaCache] Erreur téléchargement ${task.msgId}: $e');
    }
  }

  // ── Helpers statiques ─────────────────────────────────────────────────────

  static Future<File> _file(
      String convId, String type, String msgId, String ext) async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = p.join(base.path, 'careasy_media', convId, type);
    return File(p.join(dir, '$msgId.$ext'));
  }

  static String _extFromUrl(String url) {
    try {
      final uri  = Uri.parse(url);
      final name = uri.pathSegments.last;
      final dot  = name.lastIndexOf('.');
      if (dot != -1 && dot < name.length - 1) {
        return name.substring(dot + 1).toLowerCase().split('?').first;
      }
    } catch (_) {}
    return 'bin';
  }

  /// Supprime tous les médias d'une conversation (ex: conversation supprimée).
  static Future<void> deleteConversationMedia(String convId) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir  = Directory(p.join(base.path, 'careasy_media', convId));
      if (await dir.exists()) await dir.delete(recursive: true);
      debugPrint('[MediaCache] Médias de la conv $convId supprimés');
    } catch (e) {
      debugPrint('[MediaCache] Erreur suppression médias: $e');
    }
  }

  /// Taille totale du cache sur disque (en bytes).
  static Future<int> cacheSize() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir  = Directory(p.join(base.path, 'careasy_media'));
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Vide tout le cache (ex: déconnexion ou manque d'espace).
  static Future<void> clearAll() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir  = Directory(p.join(base.path, 'careasy_media'));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}

// ── Modèle interne ────────────────────────────────────────────────────────────

class _DownloadTask {
  final String msgId;
  final String convId;
  final String url;
  final String type;
  final int    priority;

  const _DownloadTask({
    required this.msgId,
    required this.convId,
    required this.url,
    required this.type,
    required this.priority,
  });
}
