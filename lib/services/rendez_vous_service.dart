// lib/services/rendez_vous_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../models/rendez_vous_model.dart';

class RendezVousService {
  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'auth_token');
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

 Future<String?> _getUserPhone() async {
  try {
    final raw = await _storage.read(key: 'user_data');
    if (raw != null && raw.isNotEmpty) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final phone = map['phone']?.toString();
      if (phone != null && phone.isNotEmpty) return phone;
    }
    // Storage vide ou phone absent → tenter un refresh depuis l'API
    final token = await _storage.read(key: 'auth_token');
    if (token == null) return null;
    final resp = await http.get(
      Uri.parse('${AppConstants.apiBaseUrl}/user/profile'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 5));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      // Mettre à jour le storage avec les données fraîches
      await _storage.write(key: 'user_data', value: jsonEncode(data));
      final phone = data['phone']?.toString();
      return (phone != null && phone.isNotEmpty) ? phone : null;
    }
    return null;
  } catch (_) {
    return null;
  }
}

  // ── GET /rendez-vous ──────────────────────────────────────────────────────
  Future<List<RendezVousModel>> fetchMesRendezVous() async {
    final resp = await http.get(
      Uri.parse('${AppConstants.apiBaseUrl}/rendez-vous'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final List data = jsonDecode(resp.body) as List;
      return data
          .map((e) => RendezVousModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    debugPrint('[RDV LIST] Status: ${resp.statusCode}');
    debugPrint('[RDV LIST] Body: ${resp.body}');
    throw _apiError(resp);
  }

  // ── GET /rendez-vous/{id} ─────────────────────────────────────────────────
  Future<RendezVousModel> fetchRendezVous(String id) async {
    final resp = await http.get(
      Uri.parse('${AppConstants.apiBaseUrl}/rendez-vous/$id'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      return RendezVousModel.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw _apiError(resp);
  }

  // ── GET /services/{serviceId}/slots/{date} ────────────────────────────────
  Future<List<TimeSlot>> fetchAvailableSlots(
      String serviceId, String date) async {
    final resp = await http.get(
      Uri.parse('${AppConstants.apiBaseUrl}/services/$serviceId/slots/$date'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final slots = (body['slots'] as List? ?? []);
      return slots
          .map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw _apiError(resp);
  }

  // ── POST /rendez-vous ─────────────────────────────────────────────────────
  Future<RendezVousModel> createRendezVous({
    required String serviceId,
    required String date,
    required String startTime,
    required String endTime,
    String? clientNotes,
    String? phone,           // ← paramètre optionnel transmis depuis l'écran
  }) async {
    // Priorité : phone passé explicitement → phone du storage → null
    final String? effectivePhone =
        (phone != null && phone.isNotEmpty) ? phone : await _getUserPhone();

    final body = <String, dynamic>{
      'service_id': serviceId,
      'date'      : date,
      'start_time': startTime,
      'end_time'  : endTime,
      if (clientNotes != null && clientNotes.isNotEmpty)
        'client_notes': clientNotes,
      // Le controller Laravel exige "phone" seulement si user.phone est vide.
      // On l'envoie systématiquement quand on l'a — ça ne pose pas de problème
      // si le backend l'ignore quand le user a déjà un numéro enregistré.
      if (effectivePhone != null) 'phone': effectivePhone,
    };

    debugPrint('[RDV] POST body: $body');

    final resp = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/rendez-vous'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 20));

    debugPrint('[RDV] Status: ${resp.statusCode}');
    debugPrint('[RDV] Body: ${resp.body}');

    if (resp.statusCode == 201 || resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return RendezVousModel.fromJson(
          data['rendez_vous'] as Map<String, dynamic>? ?? data);
    }
    throw _apiError(resp);
  }

  // ── POST /rendez-vous/{id}/confirm ────────────────────────────────────────
  Future<RendezVousModel> confirmRendezVous(String id) async {
    final resp = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/rendez-vous/$id/confirm'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return RendezVousModel.fromJson(
          data['rendez_vous'] as Map<String, dynamic>? ?? data);
    }
    throw _apiError(resp);
  }

  // ── POST /rendez-vous/{id}/cancel ─────────────────────────────────────────
  Future<RendezVousModel> cancelRendezVous(String id,
      {String? reason}) async {
    final resp = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/rendez-vous/$id/cancel'),
      headers: await _headers(),
      body: jsonEncode({
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return RendezVousModel.fromJson(
          data['rendez_vous'] as Map<String, dynamic>? ?? data);
    }
    throw _apiError(resp);
  }

  // ── POST /rendez-vous/{id}/complete ───────────────────────────────────────
  Future<RendezVousModel> completeRendezVous(String id) async {
    final resp = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/rendez-vous/$id/complete'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return RendezVousModel.fromJson(
          data['rendez_vous'] as Map<String, dynamic>? ?? data);
    }
    throw _apiError(resp);
  }

  // ── Helper ────────────────────────────────────────────────────────────────
  Exception _apiError(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      // Extraire le premier message d'erreur de validation (errors.field[0])
      if (body['errors'] != null) {
        final errors = body['errors'] as Map<String, dynamic>;
        final firstMsg = errors.values
            .whereType<List>()
            .expand((e) => e)
            .map((e) => e.toString())
            .firstOrNull;
        if (firstMsg != null) return Exception(firstMsg);
      }

      final msg = body['message']?.toString() ?? 'Erreur ${resp.statusCode}';
      return Exception(msg);
    } catch (_) {
      return Exception('Erreur ${resp.statusCode}');
    }
  }
}