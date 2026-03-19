// lib/providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'app_theme_mode';
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _storage = FlutterSecureStorage(aOptions: _androidOptions);

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final saved = await _storage.read(key: _key);
    switch (saved) {
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      case 'system':
        _themeMode = ThemeMode.system;
        break;
      default:
        _themeMode = ThemeMode.light;
    }
    notifyListeners(); // rebuild immédiat au démarrage
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners(); // rebuild immédiat dans toute l'app
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.system
            ? 'system'
            : 'light';
    await _storage.write(key: _key, value: value);
  }

  /// Valeur string pour synchro avec l'API
  String get themeModeString {
    switch (_themeMode) {
      case ThemeMode.dark:   return 'dark';
      case ThemeMode.system: return 'system';
      default:               return 'light';
    }
  }
}