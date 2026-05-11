import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class NotificationPrefsService {
  static const _aOpts = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOpts =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  static const _storage =
      FlutterSecureStorage(aOptions: _aOpts, iOptions: _iOpts);

  // Cache en mémoire pour éviter les I/O répétées
  static Map<String, bool>? _channelsCache;
  static Map<String, bool>? _typesCache;
  static DateTime?          _lastFetch;

  static const _cacheKey   = 'notif_prefs_cache';
  static const _cacheTTL   = Duration(minutes: 10);

  // ─── Chargement ──────────────────────────────────────────────────────
  static Future<void> load({bool force = false}) async {
    if (!force &&
        _channelsCache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheTTL) {
      return; // encore frais
    }

    // 1. Essayer depuis l'API
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        final resp = await http
            .get(
              Uri.parse('${AppConstants.apiBaseUrl}/user/notification-settings'),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 5));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          _updateFromJson(data);
          // Mettre en cache local
          await _storage.write(key: _cacheKey, value: resp.body);
          _lastFetch = DateTime.now();
          return;
        }
      }
    } catch (e) {
      debugPrint('[NotifPrefsService] API unavailable, using local cache: $e');
    }

    // 2. Fallback sur le cache local
    try {
      final cached = await _storage.read(key: _cacheKey);
      if (cached != null) {
        _updateFromJson(jsonDecode(cached) as Map<String, dynamic>);
        _lastFetch = DateTime.now();
      }
    } catch (_) {}

    // 3. Defaults si rien
    _channelsCache ??= {
      'email': true, 'sms': false, 'whatsapp': true, 'push': true
    };
    _typesCache ??= {
      'message': true, 'rdv': true, 'reminder': true, 'new_service': true
    };
  }

  static void _updateFromJson(Map<String, dynamic> json) {
    final ch = json['channels'] as Map<String, dynamic>? ?? {};
    final ty = json['types']   as Map<String, dynamic>? ?? {};

    // Rétro-compat
    if (ch.isEmpty && json.containsKey('email')) {
      _channelsCache = {
        'email':    (json['email']    as bool?) ?? true,
        'sms':      (json['sms']      as bool?) ?? false,
        'whatsapp': (json['whatsapp'] as bool?) ?? true,
        'push':     (json['push']     as bool?) ?? true,
      };
    } else {
      _channelsCache = {
        'email':    (ch['email']    as bool?) ?? true,
        'sms':      (ch['sms']      as bool?) ?? false,
        'whatsapp': (ch['whatsapp'] as bool?) ?? true,
        'push':     (ch['push']     as bool?) ?? true,
      };
    }

    _typesCache = {
      'message':     (ty['message']     as bool?) ?? true,
      'rdv':         (ty['rdv']         as bool?) ?? true,
      'reminder':    (ty['reminder']    as bool?) ?? true,
      'new_service': (ty['new_service'] as bool?) ?? true,
    };
  }

  // ─── Vérifications ────────────────────────────────────────────────────

  /// Vérifie si le push (canal) est activé par l'utilisateur.
  static Future<bool> isPushEnabled() async {
    await load();
    return _channelsCache?['push'] ?? true;
  }

  /// Vérifie si un type de notification est activé.
  /// [type] : 'message' | 'rdv' | 'reminder' | 'new_service'
  static Future<bool> isTypeEnabled(String type) async {
    await load();
    return _typesCache?[type] ?? true;
  }

  /// Vérifie si une notification push doit être affichée.
  /// Combine canal push + type.
  static Future<bool> canShow({required String type}) async {
    await load();
    final pushOn = _channelsCache?['push'] ?? true;
    final typeOn = _typesCache?[type]      ?? true;
    return pushOn && typeOn;
  }

  /// Invalide le cache pour forcer un rechargement.
  static void invalidate() {
    _channelsCache = null;
    _typesCache    = null;
    _lastFetch     = null;
  }

  // ─── Mapping type de notification → clé de type ───────────────────────

  /// Convertit un type FCM/Pusher en clé de type préférence.
  static String mapEventToType(String eventType) {
    if (eventType.startsWith('rdv_') || eventType == 'rdv-pending' ||
        eventType == 'rdv-confirmed' || eventType == 'rdv-cancelled' ||
        eventType == 'rdv-completed') {
      return 'rdv';
    }
    if (eventType == 'message' || eventType == 'new-message') {
      return 'message';
    }
    if (eventType == 'rdv_reminder' || eventType == 'inactivity_reminder' ||
        eventType == 'rdv_complete_reminder') {
      return 'reminder';
    }
    if (eventType == 'new_service') {
      return 'new_service';
    }
    return 'message'; // défaut
  }
}