// providers/auth_provider.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  UserModel? _currentUser;
  String? _token;
  bool _isLoading = false;
  String? _error;

  UserModel? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null && _currentUser != null;

  Future<void> loadUserData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.read(key: 'auth_token');
      final userDataString = await _storage.read(key: 'user_data');

      if (token != null && userDataString != null) {
        _token = token;
        final Map<String, dynamic> userMap = jsonDecode(userDataString);
        _currentUser = UserModel.fromJson(userMap);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String token, Map<String, dynamic> userData) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _storage.write(key: 'auth_token', value: token);
      await _storage.write(key: 'user_data', value: jsonEncode(userData));
      
      _token = token;
      _currentUser = UserModel.fromJson(userData);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'user_data');
      
      _token = null;
      _currentUser = null;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}