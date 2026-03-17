// providers/auth_provider.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';

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

  UserModel? get currentUser   => _currentUser;
  String?    get token         => _token;
  bool       get isLoading     => _isLoading;
  String?    get error         => _error;
  bool       get isAuthenticated => _token != null && _currentUser != null;

  Future<void> loadUserData() async {
    _isLoading = true; notifyListeners();
    try {
      final token      = await _storage.read(key: 'auth_token');
      final userString = await _storage.read(key: 'user_data');
      if (token != null && token.isNotEmpty && userString != null && userString.isNotEmpty) {
        _token       = token;
        _currentUser = UserModel.fromJson(jsonDecode(userString) as Map<String, dynamic>);
        debugPrint('✅ Session restaurée: ${_currentUser?.name}');
      } else {
        _token = null; _currentUser = null;
      }
    } catch (e) {
      debugPrint('❌ loadUserData: $e');
      _error = e.toString();
    } finally {
      _isLoading = false; notifyListeners();
    }
  }

  Future<void> login(String token, Map<String, dynamic> userData) async {
    _isLoading = true; notifyListeners();
    try {
      await _storage.write(key: 'auth_token', value: token);
      await _storage.write(key: 'user_data',  value: jsonEncode(userData));
      _token       = token;
      _currentUser = UserModel.fromJson(userData);
      _error       = null;
      debugPrint('✅ Login: ${_currentUser?.name}');
    } catch (e) {
      debugPrint('❌ login: $e'); _error = e.toString();
    } finally {
      _isLoading = false; notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true; notifyListeners();
    try {
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'user_data');
      await _storage.delete(key: 'fcm_token_pending');
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