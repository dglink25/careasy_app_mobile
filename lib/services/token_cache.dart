import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cache mémoire du token JWT et de l'userId.
///
/// FlutterSecureStorage fait un accès I/O chiffré (keychain/keystore) à chaque
/// lecture → ~5-30 ms par appel. Sur une conversation avec typing, read-receipts
/// et ping toutes les 3 min, cela s'accumule vite.
///
/// Ce singleton lit une seule fois au démarrage et garde les valeurs en mémoire.
/// Appeler [invalidate] à la déconnexion.
class TokenCache {
  static final TokenCache _i = TokenCache._();
  factory TokenCache() => _i;
  TokenCache._();

  static const _ao = AndroidOptions(encryptedSharedPreferences: true);
  static const _io = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _store = const FlutterSecureStorage(aOptions: _ao, iOptions: _io);

  String? _token;
  String? _userId;

  // ── API publique ──────────────────────────────────────────────────────────

  /// Token Bearer — lecture keystore uniquement à la première invocation.
  Future<String?> getToken() async {
    _token ??= await _store.read(key: 'auth_token');
    return _token;
  }

  /// userId courant — lecture keystore uniquement à la première invocation.
  Future<String?> getUserId() async {
    if (_userId != null) return _userId;
    final raw = await _store.read(key: 'user_data');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) _userId = decoded['id']?.toString();
      } catch (_) {}
    }
    return _userId;
  }

  /// Précharger explicitement les deux valeurs (appeler au login/boot).
  Future<void> preload() async {
    await getToken();
    await getUserId();
  }

  /// Mettre à jour le token après un refresh OAuth.
  void setToken(String token) => _token = token;

  /// Vider le cache à la déconnexion.
  void invalidate() {
    _token  = null;
    _userId = null;
  }
}
