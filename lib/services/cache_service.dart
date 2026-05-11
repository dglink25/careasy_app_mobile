// lib/services/cache_service.dart
//
// Service de cache local pour les données de l'API.
// Stocke services, entreprises et domaines dans SharedPreferences
// afin de les afficher en mode hors-ligne.
//
// Dépendance : shared_preferences: ^2.3.2

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  // ── Clés ───────────────────────────────────────────────────────────────────
  static const _kServices    = 'cache_services';
  static const _kEntreprises = 'cache_entreprises';
  static const _kDomaines    = 'cache_domaines';
  static const _kLastSync    = 'cache_last_sync';

  // ── ÉCRITURE ───────────────────────────────────────────────────────────────
  Future<void> saveServices(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServices, jsonEncode(data));
    await _touchSync();
  }

  Future<void> saveEntreprises(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEntreprises, jsonEncode(data));
    await _touchSync();
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

  // ── LECTURE ────────────────────────────────────────────────────────────────
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

  /// Retourne la date de la dernière synchronisation (null si jamais synchronisé)
  Future<DateTime?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastSync);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Vérifie si le cache existe (au moins services ou entreprises sauvegardés)
  Future<bool> hasCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kServices) || prefs.containsKey(_kEntreprises);
  }

  // ── SUPPRESSION ────────────────────────────────────────────────────────────
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kServices);
    await prefs.remove(_kEntreprises);
    await prefs.remove(_kDomaines);
    await prefs.remove(_kLastSync);
  }
}