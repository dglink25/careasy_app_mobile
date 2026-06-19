import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AudioMetadataCache
//
//  Pré-charge la durée de tous les audios/vocaux d'une conversation dès
//  l'ouverture de l'écran, sans bloquer l'UI.
//
//  Principe :
//   - On crée un AudioPlayer temporaire par fichier, on lit sa durée, on le
//     dispose immédiatement.  Mémoire : ~0 B après dispose.
//   - La durée est stockée en mémoire dans une Map<msgId, Duration>.
//   - Le widget lit la durée depuis ce cache → affichage instantané.
//   - Priorité : fichier local (hors-ligne) → URL réseau.
// ─────────────────────────────────────────────────────────────────────────────

class AudioMetadataCache {
  static final AudioMetadataCache _i = AudioMetadataCache._();
  factory AudioMetadataCache() => _i;
  AudioMetadataCache._();

  final Map<String, Duration> _durations = {};
  final Set<String> _loading = {};

  // ── API publique ──────────────────────────────────────────────────────────

  /// Retourne la durée mise en cache, ou null si pas encore chargée.
  Duration? getDuration(String msgId) => _durations[msgId];

  /// Pré-charge la durée d'un audio (fire-and-forget).
  /// [src] peut être un chemin local ou une URL https://.
  /// [notify] est appelé une fois la durée disponible pour déclencher un rebuild.
  void preload(String msgId, String src, {VoidCallback? notify}) {
    if (_durations.containsKey(msgId) || _loading.contains(msgId)) return;
    if (src.isEmpty) return;
    _loading.add(msgId);
    _fetchDuration(msgId, src, notify: notify);
  }

  /// Pré-charge une liste d'audios en parallèle (max 4 à la fois).
  void preloadBatch(List<({String msgId, String src})> items,
      {VoidCallback? notify}) {
    const maxConcurrent = 4;
    int running = 0;
    int index   = 0;

    void next() {
      while (running < maxConcurrent && index < items.length) {
        final item = items[index++];
        if (!_durations.containsKey(item.msgId) &&
            !_loading.contains(item.msgId) &&
            item.src.isNotEmpty) {
          running++;
          _loading.add(item.msgId);
          _fetchDuration(item.msgId, item.src, notify: notify).then((_) {
            running--;
            next();
          });
        }
      }
    }

    next();
  }

  Future<void> _fetchDuration(String msgId, String src,
      {VoidCallback? notify}) async {
    final player = AudioPlayer();
    try {
      if (src.startsWith('http')) {
        await player.setUrl(src).timeout(const Duration(seconds: 10));
      } else {
        if (!File(src).existsSync()) return;
        await player.setFilePath(src).timeout(const Duration(seconds: 5));
      }
      final dur = player.duration;
      if (dur != null && dur.inMilliseconds > 0) {
        _durations[msgId] = dur;
        notify?.call();
      }
    } catch (e) {
      debugPrint('[AudioMeta] Erreur durée $msgId: $e');
    } finally {
      _loading.remove(msgId);
      await player.dispose();
    }
  }

  bool isLoading(String msgId) => _loading.contains(msgId);

  /// Met en cache une durée directement (appelé par le player actif).
  void cacheDuration(String msgId, Duration dur) {
    if (dur.inMilliseconds > 0) _durations[msgId] = dur;
  }

  /// Invalide une entrée (ex: message supprimé).
  void invalidate(String msgId) {
    _durations.remove(msgId);
    _loading.remove(msgId);
  }

  void clear() {
    _durations.clear();
    _loading.clear();
  }
}
