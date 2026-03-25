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
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/profile'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        await _storage.write(key: 'user_data', value: jsonEncode(data));
        final phone = data['phone']?.toString();
        return (phone != null && phone.isNotEmpty) ? phone : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

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

  Future<RendezVousModel> createRendezVous({
    required String serviceId,
    required String date,
    required String startTime,
    required String endTime,
    String? clientNotes,
    String? phone,
  }) async {
    final String? effectivePhone =
        (phone != null && phone.isNotEmpty) ? phone : await _getUserPhone();

    final body = <String, dynamic>{
      'service_id': serviceId,
      'date': date,
      'start_time': startTime,
      'end_time': endTime,
      if (clientNotes != null && clientNotes.isNotEmpty)
        'client_notes': clientNotes,
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

  Future<RendezVousModel> submitReview({
    required String rdvId,
    required int rating,
    String? comment,
  }) async {
    final body = <String, dynamic>{
      'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    };

    final resp = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/reviews/$rdvId'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 201 || resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['rendez_vous'] != null) {
        return RendezVousModel.fromJson(data['rendez_vous'] as Map<String, dynamic>);
      }
      return await fetchRendezVous(rdvId);
    }

    throw _apiError(resp);
  }

  Future<RendezVousModel> reportReview({
    required String rdvId,
    required String reason,
    String? details,
  }) async {
    final body = <String, dynamic>{
      'reason': reason,
      if (details != null && details.isNotEmpty) 'details': details,
    };

    final resp = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/reviews/$rdvId/report'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['rendez_vous'] != null) {
        return RendezVousModel.fromJson(data['rendez_vous'] as Map<String, dynamic>);
      }
      return await fetchRendezVous(rdvId);
    }

    throw _apiError(resp);
  }

  Exception _apiError(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;

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