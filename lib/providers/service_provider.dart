// providers/service_provider.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';

class ServiceProvider extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  List<dynamic> _services = [];
  List<dynamic> _entreprises = [];
  List<dynamic> _domaines = [];
  
  bool _isLoading = false;
  String? _error;

  List<dynamic> get services => _services;
  List<dynamic> get entreprises => _entreprises;
  List<dynamic> get domaines => _domaines;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadServices() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/services'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        _services = jsonDecode(response.body);
        _error = null;
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadEntreprises() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/entreprises'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        _entreprises = jsonDecode(response.body);
        _error = null;
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDomaines() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/domaines'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        _domaines = jsonDecode(response.body);
        _error = null;
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> getServiceDetails(String serviceId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/services/$serviceId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Erreur getServiceDetails: $e');
    }
    return null;
  }
}