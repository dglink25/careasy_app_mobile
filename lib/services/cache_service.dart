// lib/services/cache_service.dart


import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  // ── CacheManager personnalisé (durée max 30 jours, 500 fichiers) ───────────
  static final imageCache = CacheManager(
    Config(
      'careasy_images',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
      repo: JsonCacheInfoRepository(databaseName: 'careasy_images'),
      fileService: HttpFileService(),
    ),
  );

  // ── Clés SharedPreferences ─────────────────────────────────────────────────
  static const _kServices    = 'cache_services';
  static const _kEntreprises = 'cache_entreprises';
  static const _kDomaines    = 'cache_domaines';
  static const _kLastSync    = 'cache_last_sync';


  Future<void> saveServices(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServices, jsonEncode(data));
    await _touchSync();
    // Pré-cache des images en arrière-plan
    _preCacheServiceImages(data);
  }

  Future<void> saveEntreprises(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEntreprises, jsonEncode(data));
    await _touchSync();
    // Pré-cache des logos en arrière-plan
    _preCacheEntrepriseImages(data);
  }

  Future<void> saveDomaines(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDomaines, jsonEncode(data));
    await _touchSync();
  }

  Future<void> _touchSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSync, DateTime.now().toIso8601String());
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PRÉ-CACHE IMAGES (fire & forget)
  // ══════════════════════════════════════════════════════════════════════════

  /// Télécharge toutes les images des services en arrière-plan.
  void _preCacheServiceImages(List<dynamic> services) {
    for (final service in services) {
      // Medias (carousel)
      final medias = service['medias'];
      if (medias is List) {
        for (final url in medias) {
          if (url is String && url.isNotEmpty) _downloadImage(url);
        }
      }
      // Logo de l'entreprise associée
      final logo = service['entreprise']?['logo'];
      if (logo is String && logo.isNotEmpty) _downloadImage(logo);
    }
  }

  /// Télécharge tous les logos des entreprises en arrière-plan.
  void _preCacheEntrepriseImages(List<dynamic> entreprises) {
    for (final e in entreprises) {
      final logo = e['logo'];
      if (logo is String && logo.isNotEmpty) _downloadImage(logo);
    }
  }

  /// Télécharge une URL dans le cache disque (sans bloquer).
  void _downloadImage(String url) {
    imageCache.downloadFile(url).catchError((e) {
      debugPrint('[ImageCache] Erreur pré-cache $url : $e');
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  LECTURE données JSON
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<dynamic>?> getServices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kServices);
    if (raw == null) return null;
    return jsonDecode(raw) as List<dynamic>;
  }

  Future<List<dynamic>?> getEntreprises() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kEntreprises);
    if (raw == null) return null;
    return jsonDecode(raw) as List<dynamic>;
  }

  Future<List<dynamic>?> getDomaines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDomaines);
    if (raw == null) return null;
    return jsonDecode(raw) as List<dynamic>;
  }

  /// Retourne la date de la dernière synchronisation (null si jamais synchronisé).
  Future<DateTime?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastSync);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Vérifie si le cache JSON existe.
  Future<bool> hasCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kServices) || prefs.containsKey(_kEntreprises);
  }


  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kServices);
    await prefs.remove(_kEntreprises);
    await prefs.remove(_kDomaines);
    await prefs.remove(_kLastSync);
    // Vider aussi le cache image
    await imageCache.emptyCache();
  }
}