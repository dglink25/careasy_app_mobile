// lib/screens/appearance_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart'; // à adapter selon votre structure

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );

  bool _isLoading = true;
  String _selectedTheme = 'light'; // light, dark, system

  // Langue bloquée en français uniquement
  final String _selectedLanguage = 'fr';

  final List<Map<String, dynamic>> _themes = [
    {'code': 'light',  'name': 'Clair',   'icon': Icons.light_mode, 'color': Colors.amber},
    {'code': 'dark',   'name': 'Sombre',  'icon': Icons.dark_mode,  'color': Colors.indigo},
    {'code': 'system', 'name': 'Système', 'icon': Icons.settings,   'color': Colors.grey},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final token = await _storage.read(key: 'auth_token');

      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['theme'] != null) {
          setState(() {
            _selectedTheme = data['theme'];
          });
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement paramètres: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTheme(String theme) async {
    try {
      final token = await _storage.read(key: 'auth_token');

      await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/user/theme'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'theme': theme}),
      );

      setState(() => _selectedTheme = theme);

      // ── Applique le thème immédiatement dans l'application ──
      if (mounted) {
        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        switch (theme) {
          case 'dark':
            themeProvider.setThemeMode(ThemeMode.dark);
            break;
          case 'system':
            themeProvider.setThemeMode(ThemeMode.system);
            break;
          default:
            themeProvider.setThemeMode(ThemeMode.light);
        }
      }
    } catch (e) {
      _showError('Erreur lors de la sauvegarde');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Apparence',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              child: Column(
                children: [
                  _buildThemeSection(isSmallScreen),
                  const SizedBox(height: 16),
                  _buildLanguageSection(isSmallScreen),
                ],
              ),
            ),
    );
  }

  Widget _buildThemeSection(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thème',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: _themes.map((theme) {
              final isSelected = _selectedTheme == theme['code'];
              return Expanded(
                child: GestureDetector(
                  onTap: () => _saveTheme(theme['code']),
                  child: Container(
                    margin: EdgeInsets.only(
                      right: theme['code'] != _themes.last['code'] ? 12 : 0,
                    ),
                    padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppConstants.primaryRed.withOpacity(0.1)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppConstants.primaryRed
                            : Colors.grey[200]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          theme['icon'],
                          size: isSmallScreen ? 24 : 32,
                          color: isSelected
                              ? AppConstants.primaryRed
                              : theme['color'],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          theme['name'],
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? AppConstants.primaryRed
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Section langue — affichage informatif uniquement (FR bloqué)
  Widget _buildLanguageSection(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Langue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Bientôt disponible',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 12 : 16,
              vertical: isSmallScreen ? 12 : 14,
            ),
            decoration: BoxDecoration(
              color: AppConstants.primaryRed.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppConstants.primaryRed, width: 1.5),
            ),
            child: Row(
              children: [
                const Text('🇫🇷', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Français',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  Icons.check_circle,
                  color: AppConstants.primaryRed,
                  size: isSmallScreen ? 20 : 24,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'D\'autres langues seront disponibles prochainement.',
            style: TextStyle(
              fontSize: isSmallScreen ? 11 : 12,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}