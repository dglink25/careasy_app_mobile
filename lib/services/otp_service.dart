// services/otp_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:careasy_app_mobile/utils/constants.dart';

class OtpService {
  Future<Map<String, dynamic>> sendOtp({
    required String identifier,
    required String type,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/verify-contact/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': identifier,
        'type': type,
      }),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'message': data['message'] ?? 'Erreur lors de l\'envoi du code'};
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String identifier,
    required String type,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/verify-contact/check'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': identifier,
        'type': type,
        'code': code,
      }),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      return {'success': true, 'verifyToken': data['verify_token']};
    } else {
      return {
        'success': false,
        'message': data['message'] ?? 'Code invalide',
        'attemptsRemaining': data['attempts_remaining'],
      };
    }
  }
}