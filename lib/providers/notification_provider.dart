// lib/providers/notification_provider.dart
// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER NOTIFICATIONS — gestion de la liste, du badge et des rappels
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

// ─── Modèle notification ────────────────────────────────────────────────────
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> data;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    required this.data,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final d = json['data'] as Map<String, dynamic>? ?? {};
    return AppNotification(
      id        : json['id']?.toString() ?? '',
      type      : d['type']?.toString() ?? json['type']?.toString() ?? '',
      title     : d['title']?.toString() ?? '',
      body      : d['body']?.toString() ?? '',
      isRead    : json['read_at'] != null,
      createdAt : DateTime.tryParse(json['created_at']?.toString() ?? '') ??
                  DateTime.now(),
      data      : d,
    );
  }

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id, type: type, title: title, body: body,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt, data: data,
  );

  // Icône selon le type
  IconData get icon {
    if (type.contains('rdv') || type.contains('rendez')) {
      return Icons.calendar_month_rounded;
    }
    if (type.contains('message')) return Icons.chat_bubble_rounded;
    if (type.contains('entreprise')) return Icons.business_rounded;
    return Icons.notifications_rounded;
  }

  Color get iconColor {
    if (type.contains('rdv_confirmed')) return const Color(0xFF22C55E);
    if (type.contains('rdv_cancelled')) return const Color(0xFFEF4444);
    if (type.contains('rdv_completed')) return const Color(0xFF8B5CF6);
    if (type.contains('rdv_pending'))   return const Color(0xFFF59E0B);
    if (type.contains('rdv_reminder'))  return const Color(0xFF3B82F6);
    if (type.contains('review'))        return const Color(0xFFEC4899);
    if (type.contains('message'))       return const Color(0xFF3B82F6);
    if (type.contains('entreprise_approved')) return const Color(0xFF22C55E);
    if (type.contains('entreprise_rejected')) return const Color(0xFFEF4444);
    return AppConstants.primaryRed;
  }
}

// ─── PROVIDER ───────────────────────────────────────────────────────────────
class NotificationProvider extends ChangeNotifier {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  static const _storage = FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );

  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  bool _hasError = false;
  Timer? _pollTimer;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;

  // 3 dernières pour le dropdown
  List<AppNotification> get recentThree =>
      _notifications.take(3).toList();

  // ─── Initialisation + polling ──────────────────────────────────────
  void startPolling() {
    fetchNotifications();
    _pollTimer?.cancel();
    // Rafraîchir le badge toutes les 30s
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchUnreadCount();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<Map<String, String>?> _authHeaders() async {
    final token = await _storage.read(key: 'auth_token');
    if (token == null || token.isEmpty) return null;
    return {
      'Authorization': 'Bearer $token',
      'Accept'       : 'application/json',
      'Content-Type' : 'application/json',
    };
  }

  // ─── Charger les notifications ─────────────────────────────────────
  Future<void> fetchNotifications({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final headers = await _authHeaders();
      if (headers == null) return;

      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/notifications?limit=50'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final list  = (body['notifications'] as List? ?? [])
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        _notifications = list;
        _unreadCount   = (body['unread_count'] as int?) ?? 0;
        _hasError      = false;
      }
    } catch (e) {
      debugPrint('[NotifProvider] fetchNotifications: $e');
      _hasError = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Badge uniquement (léger) ──────────────────────────────────────
  Future<void> _fetchUnreadCount() async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/notifications/unread-count'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final count = (body['unread_count'] as int?) ?? 0;
        if (count != _unreadCount) {
          _unreadCount = count;
          notifyListeners();
          // Si le count a augmenté, recharger la liste
          if (count > _unreadCount) fetchNotifications(silent: true);
        }
      }
    } catch (_) {}
  }

  // ─── Marquer une comme lue ─────────────────────────────────────────
  Future<void> markAsRead(String id) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/notifications/$id/mark-read'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));

      // Mise à jour optimiste
      _notifications = _notifications.map((n) =>
          n.id == id ? n.copyWith(isRead: true) : n).toList();
      _unreadCount = _notifications.where((n) => !n.isRead).length;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotifProvider] markAsRead: $e');
    }
  }

  // ─── Tout marquer comme lu ─────────────────────────────────────────
  Future<void> markAllAsRead() async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/notifications/mark-all-read'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));

      _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotifProvider] markAllAsRead: $e');
    }
  }

  // ─── Supprimer ─────────────────────────────────────────────────────
  Future<void> delete(String id) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      await http.delete(
        Uri.parse('${AppConstants.apiBaseUrl}/notifications/$id'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));

      final notif = _notifications.firstWhere(
          (n) => n.id == id,
          orElse: () => AppNotification(
              id: '', type: '', title: '', body: '',
              isRead: true,
              createdAt: DateTime.fromMillisecondsSinceEpoch(0),
              data: {}));
      if (!notif.isRead && _unreadCount > 0) _unreadCount--;
      _notifications = _notifications.where((n) => n.id != id).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[NotifProvider] delete: $e');
    }
  }

  /// Ajouter en temps réel (depuis Pusher)
  void addFromPusher(Map<String, dynamic> data) {
    final notif = AppNotification(
      id       : data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type     : data['type']?.toString() ?? '',
      title    : data['title']?.toString() ?? '',
      body     : data['body']?.toString() ?? '',
      isRead   : false,
      createdAt: DateTime.now(),
      data     : data,
    );
    _notifications = [notif, ..._notifications];
    _unreadCount++;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}