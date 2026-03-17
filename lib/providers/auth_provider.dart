import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

class AuthProvider extends ChangeNotifier {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );

  UserModel? _currentUser;
  String?    _token;
  bool       _isLoading = false;
  String?    _error;

  UserModel? get currentUser    => _currentUser;
  String?    get token          => _token;
  bool       get isLoading      => _isLoading;
  String?    get error          => _error;
  bool       get isAuthenticated => _token != null && _currentUser != null;

  // ── Chargement initial des données ────────────────────────────────────────────
  Future<void> loadUserData() async {
    _isLoading = true; notifyListeners();
    try {
      final token      = await _storage.read(key: 'auth_token');
      final userString = await _storage.read(key: 'user_data');
      if (token != null && token.isNotEmpty && userString != null && userString.isNotEmpty) {
        _token       = token;
        _currentUser = UserModel.fromJson(jsonDecode(userString) as Map<String, dynamic>);
        debugPrint('Session restaurée: ${_currentUser?.name}');
      } else {
        _token = null; _currentUser = null;
      }
    } catch (e) {
      debugPrint('loadUserData: $e');
      _error = e.toString();
    } finally {
      _isLoading = false; notifyListeners();
    }
  }

  Future<bool> verifyToken() async {
    final token = _token ?? await _storage.read(key: 'auth_token');
    if (token == null || token.isEmpty) return false;

    try {
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/profile'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        // Profil à jour → mettre à jour le cache local
        try {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          if (data.isNotEmpty) {
            await _storage.write(key: 'user_data', value: jsonEncode(data));
            _currentUser = UserModel.fromJson(data);
            notifyListeners();
          }
        } catch (_) {}
        return true;
      }

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        debugPrint('[AuthProvider] Token révoqué (${resp.statusCode})');
        return false;
      }

      // Erreur serveur → faire confiance au token local
      debugPrint('[AuthProvider] Serveur indisponible (${resp.statusCode}) → accepté');
      return true;
    } catch (e) {
      // Pas de réseau / timeout → faire confiance au token local (offline-first)
      debugPrint('[AuthProvider] Pas de réseau: $e → token local accepté');
      return true;
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────────
  Future<void> login(String token, Map<String, dynamic> userData) async {
    _isLoading = true; notifyListeners();
    try {
      await _storage.write(key: 'auth_token', value: token);
      await _storage.write(key: 'user_data',  value: jsonEncode(userData));
      _token       = token;
      _currentUser = UserModel.fromJson(userData);
      _error       = null;
      debugPrint('Login: ${_currentUser?.name}');
    } catch (e) {
      debugPrint('login: $e'); _error = e.toString();
    } finally {
      _isLoading = false; notifyListeners();
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    _isLoading = true; notifyListeners();
    try {
      // Révoquer le token côté serveur si possible
      final token = _token;
      if (token != null && token.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('${AppConstants.apiBaseUrl}/logout'),
            headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 5));
        } catch (_) {} // Ignorer si pas de réseau
      }
      // Nettoyer le storage local
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'user_data');
      await _storage.delete(key: 'fcm_token_pending');
      await _storage.delete(key: 'remember_me');
      _token = null; _currentUser = null; _error = null;
    } catch (e) {
      debugPrint('Erreur logout: $e');
      _token = null; _currentUser = null;
    } finally {
      _isLoading = false; notifyListeners();
    }
  }

  void clearError() { _error = null; notifyListeners(); }
}