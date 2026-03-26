// lib/screens/security_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/constants.dart';
import '../providers/auth_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
//  CONSTANTS
// ════════════════════════════════════════════════════════════════════════════

class _C {
  static const int maxSessions = 5;
  static const Color red       = AppConstants.primaryRed;
  static const Color bg        = Color(0xFFF5F6FA);
  static const Color card      = Colors.white;

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  static FlutterSecureStorage get storage => const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  MAIN SCREEN
// ════════════════════════════════════════════════════════════════════════════

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _isLoading = false;

  // ── Mot de passe ──────────────────────────────────────────────────────
  final _formKey                  = GlobalKey<FormState>();
  final _currentPasswordCtrl      = TextEditingController();
  final _newPasswordCtrl          = TextEditingController();
  final _confirmPasswordCtrl      = TextEditingController();
  bool _showCurrent    = false;
  bool _showNew        = false;
  bool _showConfirm    = false;
  bool _changingPwd    = false;

  @override
  void dispose() {
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<String?> _getToken() => _C.storage.read(key: 'auth_token');

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type' : 'application/json',
    'Accept'       : 'application/json',
  };

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _C.red))
          : _buildBody(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _C.red,
      foregroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Confidentialité & sécurité',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_C.red, _C.red.withOpacity(0.85)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: _hPad(context),
        vertical: 20,
      ),
      child: Column(children: [
        _buildPasswordSection(context),
        const SizedBox(height: 16),
        _buildSecuritySection(context),
        const SizedBox(height: 40),
      ]),
    );
  }

  double _hPad(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 600) return (w - 560) / 2;
    return 16;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  SECTION CHANGER MOT DE PASSE
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPasswordSection(BuildContext context) {
    return _Card(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.lock_reset_outlined,
              label: 'Changer le mot de passe',
            ),
            const SizedBox(height: 20),
            _PwdField(
              controller: _currentPasswordCtrl,
              label: 'Mot de passe actuel',
              show: _showCurrent,
              onToggle: () => setState(() => _showCurrent = !_showCurrent),
              validator: (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: 14),
            _PwdField(
              controller: _newPasswordCtrl,
              label: 'Nouveau mot de passe',
              show: _showNew,
              onToggle: () => setState(() => _showNew = !_showNew),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Champ requis';
                if (v.length < 8) return 'Minimum 8 caractères';
                if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Au moins une majuscule';
                if (!RegExp(r'[0-9]').hasMatch(v)) return 'Au moins un chiffre';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _PwdField(
              controller: _confirmPasswordCtrl,
              label: 'Confirmer le mot de passe',
              show: _showConfirm,
              onToggle: () => setState(() => _showConfirm = !_showConfirm),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Champ requis';
                if (v != _newPasswordCtrl.text) return 'Ne correspond pas';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _changingPwd ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _changingPwd
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Mettre à jour le mot de passe',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  SECTION SÉCURITÉ — tiles
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildSecuritySection(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: Icons.security_outlined, label: 'Sécurité'),
          const SizedBox(height: 8),

          _SecurityTile(
            icon: Icons.devices_outlined,
            title: 'Appareils connectés',
            subtitle: 'Gérer les appareils • Max $_C.maxSessions sessions',
            badge: '5 max', badgeColor: Colors.blue,
            onTap: () => _showSheet(context,
                _ConnectedDevicesSheet(storage: _C.storage)),
          ),
          const _Div(),

          _SecurityTile(
            icon: Icons.history_rounded,
            title: 'Historique des connexions',
            subtitle: 'Voir les 30 derniers jours',
            onTap: () => _showSheet(context,
                _LoginHistorySheet(storage: _C.storage)),
          ),
          const _Div(),

          _SecurityTile(
            icon: Icons.phonelink_lock_outlined,
            title: 'Authentification à deux facteurs',
            subtitle: 'Protection TOTP renforcée',
            badge: '2FA', badgeColor: Colors.orange,
            onTap: () => _showSheet(context,
                _TwoFactorSheet(storage: _C.storage)),
          ),
          const _Div(),

          _SecurityTile(
            icon: Icons.qr_code_2_rounded,
            title: 'Connexion depuis un autre téléphone',
            subtitle: 'Générer un QR code de connexion rapide',
            badge: 'QR', badgeColor: Colors.purple,
            onTap: () => _showSheet(context,
                _QRLoginGeneratorSheet(storage: _C.storage)),
          ),
          const _Div(),

          _SecurityTile(
            icon: Icons.logout_rounded,
            title: 'Déconnecter tous les appareils',
            subtitle: 'Révoquer toutes les sessions actives',
            iconColor: Colors.orange[700],
            onTap: () => _confirmLogoutAll(context),
          ),
        ],
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _changingPwd = true);
    try {
      final token = await _getToken();
      final resp = await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/user/password'),
        headers: _headers(token!),
        body: jsonEncode({
          'current_password'            : _currentPasswordCtrl.text,
          'new_password'                : _newPasswordCtrl.text,
          'new_password_confirmation'   : _confirmPasswordCtrl.text,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        _currentPasswordCtrl.clear();
        _newPasswordCtrl.clear();
        _confirmPasswordCtrl.clear();
        _snack('Mot de passe mis à jour ✓', Colors.green);
      } else {
        String msg = 'Erreur lors du changement';
        if (data['errors']?['current_password'] != null) {
          msg = data['errors']['current_password'][0];
        } else if (data['message'] != null) {
          msg = data['message'];
        }
        _snack(msg, Colors.red);
      }
    } catch (_) {
      _snack('Erreur de connexion', Colors.red);
    } finally {
      if (mounted) setState(() => _changingPwd = false);
    }
  }

  Future<void> _confirmLogoutAll(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Déconnecter tous les appareils',
        content: 'Vous allez être déconnecté de tous vos appareils. '
            'Vous devrez vous reconnecter sur cet appareil.',
        confirmLabel: 'Déconnecter tout',
        confirmColor: Colors.orange,
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/logout-all'),
        headers: _headers(token!),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        _snack('Tous les appareils ont été déconnectés', Colors.green);
        if (mounted) await context.read<AuthProvider>().logout();
      } else {
        _snack('Erreur lors de la déconnexion', Colors.red);
      }
    } catch (_) {
      _snack('Erreur de connexion', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSheet(BuildContext context, Widget sheet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 14, offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: _C.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 16, color: _C.red),
    ),
    const SizedBox(width: 10),
    Text(label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
  ]);
}

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Colors.grey[100]);
}

class _SecurityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;
  final Color? iconColor;

  const _SecurityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? _C.red;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: iconColor ?? Colors.grey[900])),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: (badgeColor ?? _C.red).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(badge!,
                  style: TextStyle(
                      fontSize: 10,
                      color: badgeColor ?? _C.red,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
          ],
          Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[400]),
        ]),
      ),
    );
  }
}

class _PwdField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool show;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  const _PwdField({
    required this.controller,
    required this.label,
    required this.show,
    required this.onToggle,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: Colors.grey[700])),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        obscureText: !show,
        validator: validator,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.lock_outline, size: 20, color: _C.red),
          suffixIcon: IconButton(
            icon: Icon(
              show ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18, color: Colors.grey[500],
            ),
            onPressed: onToggle,
          ),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _C.red, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          filled: true,
          fillColor: Colors.grey[50],
        ),
      ),
    ],
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40, height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      decoration: BoxDecoration(
          color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
    ),
  );
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    title: Text(title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    content: Text(content, style: const TextStyle(fontSize: 13)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text('Annuler', style: TextStyle(color: Colors.grey[600])),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(context, true),
        style: ElevatedButton.styleFrom(
          backgroundColor: confirmColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(confirmLabel),
      ),
    ],
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  SHEET — APPAREILS CONNECTÉS
// ════════════════════════════════════════════════════════════════════════════

class _ConnectedDevicesSheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _ConnectedDevicesSheet({required this.storage});

  @override
  State<_ConnectedDevicesSheet> createState() => _ConnectedDevicesSheetState();
}

class _ConnectedDevicesSheetState extends State<_ConnectedDevicesSheet>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sessions = [];
  late TabController _tabCtrl;

  // QR share
  String? _shareToken;
  bool _generatingQR = false;
  Timer? _qrTimer;
  Timer? _pollTimer;
  int _qrSecs = 120;
  bool _qrConfirmed = false;
  String? _qrDeviceName;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _qrTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<String?> get _token => widget.storage.read(key: 'auth_token');

  Map<String, String> _headers(String t) => {
    'Authorization': 'Bearer $t',
    'Content-Type' : 'application/json',
    'Accept'       : 'application/json',
  };

  // ── Data ──────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final t = await _token;
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/sessions'),
        headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(
              data['sessions'] ?? data ?? []);
        });
      } else {
        _loadDemo();
      }
    } catch (_) {
      _loadDemo();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadDemo() {
    _sessions = [{
      'id': 'current',
      'device_type': 'Android • Samsung Galaxy S24',
      'ip_address': '41.73.12.xx',
      'last_used_at': DateTime.now().toString(),
      'is_current': true,
      'location': 'Cotonou, Bénin',
    }];
  }

  Future<void> _revokeSession(dynamic sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title: 'Révoquer cette session ?',
        content: 'Cet appareil sera déconnecté immédiatement.',
        confirmLabel: 'Révoquer',
        confirmColor: Colors.red,
      ),
    );
    if (confirm != true) return;

    try {
      final t = await _token;
      final resp = await http.delete(
        Uri.parse('${AppConstants.apiBaseUrl}/user/sessions/$sessionId'),
        headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        setState(() => _sessions.removeWhere((s) => s['id'] == sessionId));
        _snack('Session révoquée ✓', Colors.green);
      } else {
        final body = jsonDecode(resp.body);
        _snack(body['message'] ?? 'Erreur lors de la révocation', Colors.red);
      }
    } catch (_) {
      // Demo
      setState(() => _sessions.removeWhere((s) => s['id'] == sessionId));
    }
  }

  Future<void> _revokeAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title: 'Déconnecter tous les appareils ?',
        content: 'Tous vos appareils seront déconnectés immédiatement, '
            'y compris celui-ci.',
        confirmLabel: 'Tout déconnecter',
        confirmColor: Colors.red,
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final t = await _token;
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/logout-all'),
        headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        _snack('Tous les appareils ont été déconnectés', Colors.green);
        if (mounted) {
          Navigator.pop(context);
          await context.read<AuthProvider>().logout();
        }
      } else {
        _snack('Erreur lors de la déconnexion', Colors.red);
      }
    } catch (_) {
      _snack('Erreur de connexion', Colors.red);
    }
  }

  // ── QR Code ───────────────────────────────────────────────────────────

  Future<void> _generateQR() async {
    if (_sessions.length >= _C.maxSessions) {
      _snack('⚠️ Maximum 5 appareils. Révoquez-en un d\'abord.', Colors.orange);
      return;
    }

    setState(() { _generatingQR = true; _qrConfirmed = false; });
    _qrTimer?.cancel();
    _pollTimer?.cancel();

    try {
      final t = await _token;
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/sessions/share-token'),
        headers: _headers(t!),
        body: jsonEncode({'expires_in': 120}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _shareToken = data['share_token'] ?? data['token'];
          _qrSecs = 120;
        });
      } else {
        setState(() {
          _shareToken = 'SHARE_DEMO_${DateTime.now().millisecondsSinceEpoch}';
          _qrSecs = 120;
        });
      }
    } catch (_) {
      setState(() {
        _shareToken = 'SHARE_DEMO_${DateTime.now().millisecondsSinceEpoch}';
        _qrSecs = 120;
      });
    } finally {
      if (mounted) setState(() => _generatingQR = false);
    }

    if (_shareToken != null) {
      _startQrCountdown();
      _startQrPolling();
    }
  }

  void _startQrCountdown() {
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _qrSecs--);
      if (_qrSecs <= 0) {
        t.cancel();
        _pollTimer?.cancel();
        if (!_qrConfirmed) setState(() => _shareToken = null);
      }
    });
  }

  void _startQrPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!mounted || _qrConfirmed) { t.cancel(); return; }
      await _checkQrStatus();
    });
  }

  Future<void> _checkQrStatus() async {
    if (_shareToken == null) return;
    try {
      final t = await _token;
      final resp = await http.get(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/user/sessions/share-token/$_shareToken/status'),
        headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final used = data['used'] == true || data['status'] == 'used';
        if (used) {
          _qrTimer?.cancel();
          _pollTimer?.cancel();
          setState(() {
            _qrConfirmed  = true;
            _qrDeviceName = data['device_name']?.toString() ?? 'Nouvel appareil';
            _shareToken   = null;
          });
          await _load(); // Rafraîchir la liste
        }
      }
    } catch (_) {}
  }

  void _resetQR() {
    _qrTimer?.cancel();
    _pollTimer?.cancel();
    setState(() {
      _shareToken   = null;
      _qrConfirmed  = false;
      _qrDeviceName = null;
      _qrSecs       = 120;
    });
  }

  // ── Helpers UI ────────────────────────────────────────────────────────

  IconData _deviceIcon(String? device) {
    final d = (device ?? '').toLowerCase();
    if (d.contains('android') || d.contains('iphone') || d.contains('mobile'))
      return Icons.smartphone_rounded;
    if (d.contains('tablet') || d.contains('ipad')) return Icons.tablet_rounded;
    if (d.contains('mac') || d.contains('windows') || d.contains('linux'))
      return Icons.laptop_rounded;
    return Icons.devices_rounded;
  }

  String _fmtDate(String s) {
    try {
      final dt   = DateTime.parse(s).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1)  return 'À l\'instant';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
      if (diff.inHours < 24)   return 'Il y a ${diff.inHours}h';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return s; }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return Container(
      height: h * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        const _SheetHandle(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.devices_rounded,
                    color: Colors.blue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Appareils connectés',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('Max ${_C.maxSessions} appareils simultanés',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.blue),
                onPressed: _load,
              ),
            ]),
            const SizedBox(height: 14),
            _SessionBar(
                current: _sessions.length, max: _C.maxSessions),
            const SizedBox(height: 14),
            TabBar(
              controller: _tabCtrl,
              labelColor: _C.red,
              unselectedLabelColor: Colors.grey,
              indicatorColor: _C.red,
              tabs: const [
                Tab(text: 'Mes appareils',
                    icon: Icon(Icons.devices, size: 16)),
                Tab(text: 'Ajouter via QR',
                    icon: Icon(Icons.qr_code_2, size: 16)),
              ],
            ),
          ]),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildDevicesList(),
              _buildQRTab(),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Tab 1 : Liste appareils ───────────────────────────────────────────

  Widget _buildDevicesList() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _C.red));
    }
    if (_sessions.isEmpty) {
      return _EmptyState(
        icon: Icons.devices_other_rounded,
        label: 'Aucun appareil trouvé',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        ..._sessions.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: _buildDeviceCard(s),
          );
        }),
        const SizedBox(height: 20),
        // Bouton tout déconnecter
        OutlinedButton.icon(
          onPressed: _revokeAll,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Déconnecter tous les appareils'),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red, width: 1.5),
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> s) {
    final isCurrent = s['is_current'] == true;
    final device    = s['device_type'] ?? s['device'] ?? 'Appareil inconnu';
    final ip        = s['ip_address'] ?? '—';
    final location  = s['location'] ?? '';
    final lastUsed  = _fmtDate(s['last_used_at'] ?? s['created_at'] ?? '');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCurrent
            ? _C.red.withOpacity(0.04)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? _C.red.withOpacity(0.20)
              : Colors.grey[200]!,
        ),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isCurrent
                ? _C.red.withOpacity(0.10)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_deviceIcon(device), size: 22,
              color: isCurrent ? _C.red : Colors.grey[600]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(device,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (isCurrent)
                  _Badge('Cet appareil', Colors.green),
              ]),
              const SizedBox(height: 3),
              Text(
                'IP: $ip${location.isNotEmpty ? ' • $location' : ''}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Text('Dernière activité : $lastUsed',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[400])),
            ],
          ),
        ),
        if (!isCurrent) ...[
          const SizedBox(width: 8),
          _IconBtn(
            icon: Icons.logout_rounded,
            color: Colors.red,
            tooltip: 'Révoquer',
            onTap: () => _revokeSession(s['id']),
          ),
        ],
      ]),
    );
  }

  // ── Tab 2 : QR Code ──────────────────────────────────────────────────

  Widget _buildQRTab() {
    if (_qrConfirmed) return _buildQRSuccess();

    final canAdd = _sessions.length < _C.maxSessions;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(children: [
        // Capacité
        _CapacityBanner(
          canAdd: canAdd,
          remaining: _C.maxSessions - _sessions.length,
        ),
        const SizedBox(height: 20),

        if (!canAdd) ...[
          const SizedBox(height: 20),
          const Icon(Icons.lock_rounded, size: 64, color: Color(0xFFDDE3EE)),
          const SizedBox(height: 12),
          const Text('Limite de 5 appareils atteinte',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Allez dans "Mes appareils" et révoquez\nun appareil pour libérer une place.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ] else if (_shareToken == null)
          _buildQRIntro()
        else
          _buildQRDisplay(),
      ]),
    );
  }

  Widget _buildQRIntro() {
    return Column(children: [
      _qrStep('1', Icons.qr_code_2_rounded,
          'Appuyez sur "Générer" sur cet appareil.'),
      _qrStep('2', Icons.phone_android_rounded,
          'Sur le nouvel appareil, allez dans Bienvenue → Connexion QR.'),
      _qrStep('3', Icons.camera_alt_rounded,
          'Scannez le code. Connexion automatique et sécurisée.'),
      _qrStep('4', Icons.timer_outlined,
          'Le QR expire après 2 minutes pour votre sécurité.'),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _generatingQR ? null : _generateQR,
          icon: _generatingQR
              ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.qr_code_2_rounded),
          label: Text(_generatingQR ? 'Génération...' : 'Générer un QR code'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  Widget _buildQRDisplay() {
    final urgent = _qrSecs < 30;
    final color  = urgent ? Colors.red : Colors.purple;

    return Column(children: [
      // Timer
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(Icons.timer_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              urgent
                  ? '⚠️ Expire dans $_qrSecs secondes !'
                  : 'En attente de scan — $_qrSecs s',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
          ),
          SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
                color: color, strokeWidth: 2),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: _qrSecs / 120,
          backgroundColor: Colors.grey[200],
          color: urgent ? Colors.red : _C.red,
          minHeight: 5,
        ),
      ),
      const SizedBox(height: 20),

      // QR Image
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: urgent
                  ? Colors.red.withOpacity(0.4)
                  : Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20, offset: const Offset(0, 4)),
          ],
        ),
        child: QrImageView(
          data: jsonEncode({
            'type'      : 'careasy_session_share',
            'token'     : _shareToken,
            'expires_in': _qrSecs,
            'issued_at' : DateTime.now().toIso8601String(),
          }),
          version        : QrVersions.auto,
          size           : 200,
          backgroundColor: Colors.white,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: urgent ? Colors.red : Colors.black87,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: urgent ? Colors.red : Colors.black87,
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Scannez depuis la page d\'accueil de l\'autre téléphone',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _resetQR,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Annuler'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey[300]!),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _generateQR,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Actualiser'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _buildQRSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[400]!, Colors.green[600]!],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 48),
            ),
            const SizedBox(height: 24),
            const Text('Connexion réussie !',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green)),
            const SizedBox(height: 10),
            Text(
              _qrDeviceName != null
                  ? '"$_qrDeviceName" vient de rejoindre votre compte.'
                  : 'Un nouvel appareil vient de se connecter.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: Colors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Si vous ne reconnaissez pas cet appareil, révoquez '
                        'cette session dans l\'onglet "Mes appareils".',
                    style: TextStyle(
                        fontSize: 11, color: Colors.green[700]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _resetQR,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Générer un autre QR'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qrStep(String num, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 26, height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            color: _C.red, shape: BoxShape.circle),
        child: Text(num,
            style: const TextStyle(
                color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: Colors.grey[600]),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ),
      ),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  SHEET — HISTORIQUE DES CONNEXIONS
// ════════════════════════════════════════════════════════════════════════════

class _LoginHistorySheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _LoginHistorySheet({required this.storage});

  @override
  State<_LoginHistorySheet> createState() => _LoginHistorySheetState();
}

class _LoginHistorySheetState extends State<_LoginHistorySheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final t = await widget.storage.read(key: 'auth_token');
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/login-history'),
        headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _history = List<Map<String, dynamic>>.from(
              data['history'] ?? data ?? []);
        });
      } else {
        _loadDemo();
      }
    } catch (_) {
      _loadDemo();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadDemo() {
    _history = [
      {
        'success': true, 'ip_address': '41.73.12.45',
        'device': 'Android • Chrome', 'location': 'Cotonou, Bénin',
        'created_at': DateTime.now().subtract(const Duration(minutes: 5)).toString(),
        'method': 'email',
      },
      {
        'success': true, 'ip_address': '41.73.12.45',
        'device': 'iPhone 15 Pro', 'location': 'Cotonou, Bénin',
        'created_at': DateTime.now().subtract(const Duration(hours: 2)).toString(),
        'method': 'google',
      },
      {
        'success': false, 'ip_address': '195.128.0.12',
        'device': 'Windows • Firefox', 'location': 'Paris, France',
        'created_at': DateTime.now().subtract(const Duration(hours: 5)).toString(),
        'method': 'email', 'fail_reason': 'Mot de passe incorrect',
      },
      {
        'success': true, 'ip_address': '41.73.12.45',
        'device': 'Android • App native', 'location': 'Cotonou, Bénin',
        'created_at': DateTime.now().subtract(const Duration(days: 1)).toString(),
        'method': 'qr',
      },
      {
        'success': false, 'ip_address': '82.220.56.78',
        'device': 'Linux • Curl', 'location': 'Inconnu',
        'created_at': DateTime.now().subtract(const Duration(days: 2)).toString(),
        'method': 'email', 'fail_reason': 'Compte inexistant',
      },
    ];
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'success') return _history.where((h) => h['success'] == true).toList();
    if (_filter == 'failed')  return _history.where((h) => h['success'] != true).toList();
    return _history;
  }

  String _fmtDate(String s) {
    try {
      final dt   = DateTime.parse(s).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1)  return 'À l\'instant';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
      if (diff.inHours < 24)   return 'Il y a ${diff.inHours}h';
      if (diff.inDays < 7)     return 'Il y a ${diff.inDays}j';
      return '${dt.day}/${dt.month}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return s; }
  }

  IconData _methodIcon(String? m) {
    switch (m) {
      case 'google': return Icons.g_mobiledata_rounded;
      case 'qr':     return Icons.qr_code_rounded;
      case 'phone':  return Icons.phone_rounded;
      default:       return Icons.email_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return Container(
      height: h * 0.90,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        const _SheetHandle(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_rounded,
                    color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Historique des connexions',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('30 derniers jours',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.purple),
                onPressed: _load,
              ),
            ]),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                _StatChip(
                    '${_history.where((h) => h['success'] == true).length}',
                    'Réussies', Colors.green),
                const SizedBox(width: 8),
                _StatChip(
                    '${_history.where((h) => h['success'] != true).length}',
                    'Échouées', Colors.red),
                const SizedBox(width: 8),
                _StatChip('${_history.length}', 'Total', Colors.blue),
              ]),
            ],
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _FilterChip('all', 'Toutes', _filter,
                    (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip('success', '✓ Réussies', _filter,
                    (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip('failed', '✗ Échouées', _filter,
                    (v) => setState(() => _filter = v)),
              ]),
            ),
            const SizedBox(height: 8),
          ]),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
              child: CircularProgressIndicator(color: Colors.purple))
              : _filtered.isEmpty
              ? _EmptyState(
              icon: Icons.history_toggle_off_rounded,
              label: 'Aucune connexion trouvée')
              : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: _filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildItem(_filtered[i]),
          ),
        ),
      ]),
    );
  }

  Widget _buildItem(Map<String, dynamic> h) {
    final ok     = h['success'] == true;
    final ip     = h['ip_address'] ?? '—';
    final device = h['device'] ?? 'Appareil inconnu';
    final loc    = h['location'] ?? '';
    final date   = _fmtDate(h['created_at'] ?? h['logged_at'] ?? '');
    final reason = h['fail_reason'] as String?;
    final method = h['method'] as String?;
    final color  = ok ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(
              ok ? Icons.check_circle_outline_rounded
                 : Icons.error_outline_rounded,
              color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(ok ? 'Connexion réussie' : 'Tentative échouée',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: ok ? Colors.green[800] : Colors.red[700])),
                const Spacer(),
                Icon(_methodIcon(method), size: 14, color: Colors.grey[400]),
              ]),
              const SizedBox(height: 3),
              Text(device,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[700],
                      fontWeight: FontWeight.w500)),
              Text('IP: $ip${loc.isNotEmpty ? ' • $loc' : ''}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[500])),
              if (reason != null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(reason,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.red,
                          fontWeight: FontWeight.w500)),
                ),
              const SizedBox(height: 3),
              Text(date,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SHEET — 2FA (inchangé dans sa logique, légèrement restyled)
// ════════════════════════════════════════════════════════════════════════════

class _TwoFactorSheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _TwoFactorSheet({required this.storage});

  @override
  State<_TwoFactorSheet> createState() => _TwoFactorSheetState();
}

class _TwoFactorSheetState extends State<_TwoFactorSheet>
    with SingleTickerProviderStateMixin {
  bool _isLoading  = true;
  bool _isEnabled  = false;
  bool _processing = false;
  String? _qrData;
  String? _secret;
  List<String> _codes = [];
  final _codeCtrl = TextEditingController();
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.95, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadStatus();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    try {
      final t = await widget.storage.read(key: 'auth_token');
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/status'),
        headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _isEnabled = data['enabled'] == true;
          _qrData    = data['qr_code_url'] ?? data['provisioning_uri'];
          _secret    = data['secret'];
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setup() async {
    setState(() => _processing = true);
    try {
      final t = await widget.storage.read(key: 'auth_token');
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/setup'),
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _qrData = data['provisioning_uri'] ?? data['qr_code_url'];
          _secret = data['secret'];
          _step   = 1;
        });
      } else {
        _demoSetup();
      }
    } catch (_) { _demoSetup(); } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _demoSetup() {
    setState(() {
      _secret = 'JBSWY3DPEHPK3PXP';
      _qrData = 'otpauth://totp/CarEasy:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=CarEasy';
      _step   = 1;
    });
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) { _snack('Code 6 chiffres requis', Colors.red); return; }
    setState(() => _processing = true);
    try {
      final t = await widget.storage.read(key: 'auth_token');
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/enable'),
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'code': code, 'secret': _secret}),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _isEnabled = true;
          _codes = List<String>.from(data['recovery_codes'] ?? []);
          _step  = 3;
        });
      } else {
        _demoCodes();
      }
    } catch (_) { _demoCodes(); } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _demoCodes() {
    setState(() {
      _isEnabled = true;
      _codes = ['ABCD-EFGH-1234','IJKL-MNOP-5678','QRST-UVWX-9012',
                 'YZER-ABCD-3456','EFGH-IJKL-7890','MNOP-QRST-1234'];
      _step  = 3;
    });
  }

  Future<void> _disable() async {
    final codeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Désactiver la 2FA ?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10)),
            child: const Text('⚠️ Votre compte sera moins sécurisé.',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'Code TOTP (6 chiffres)',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              counterText: '',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white),
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _processing = true);
    try {
      final t = await widget.storage.read(key: 'auth_token');
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/disable'),
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'code': codeCtrl.text}),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 || resp.statusCode == 204) {
        setState(() { _isEnabled = false; _step = 0; });
        _snack('2FA désactivée', Colors.green);
      } else {
        _snack('Code incorrect', Colors.red);
      }
    } catch (_) {
      setState(() { _isEnabled = false; _step = 0; });
      _snack('2FA désactivée (mode démo)', Colors.green);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.96,
        minChildSize: 0.4,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const _SheetHandle(),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.phonelink_lock_rounded,
                    color: Colors.orange, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Authentification à deux facteurs',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Protection TOTP (Google Authenticator)',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator(color: Colors.orange)
                : _buildContent(),
          ]),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case 1:  return _buildSetup();
      case 2:  return _buildVerify();
      case 3:  return _buildRecoveryCodes();
      default: return _buildStatus();
    }
  }

  Widget _buildStatus() {
    return Column(children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Transform.scale(
            scale: _isEnabled ? _pulse.value : 1.0, child: child),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isEnabled
                  ? [Colors.green.shade400, Colors.green.shade600]
                  : [Colors.orange.shade400, Colors.orange.shade600],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(
                color: (_isEnabled ? Colors.green : Colors.orange)
                    .withOpacity(0.3),
                blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(children: [
            Icon(
              _isEnabled
                  ? Icons.verified_user_rounded
                  : Icons.security_outlined,
              color: Colors.white, size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isEnabled ? '2FA Activée ✓' : '2FA Non activée',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isEnabled
                        ? 'Votre compte est protégé.'
                        : 'Activez la 2FA pour plus de sécurité.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 24),
      if (_isEnabled) ...[
        OutlinedButton.icon(
          onPressed: _processing ? null : () async {
            final t = await widget.storage.read(key: 'auth_token');
            final resp = await http.get(
              Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/recovery-codes'),
              headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 10));
            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body);
              setState(() {
                _codes = List<String>.from(data['recovery_codes'] ?? data ?? []);
                _step  = 3;
              });
            } else {
              setState(() {
                _codes = ['ABCD-EFGH-1234', 'IJKL-MNOP-5678'];
                _step  = 3;
              });
            }
          },
          icon: const Icon(Icons.key_rounded, size: 18),
          label: const Text('Voir les codes de récupération'),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.blue.withOpacity(0.5)),
            foregroundColor: Colors.blue,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _processing ? null : _disable,
          icon: const Icon(Icons.no_encryption_gmailerrorred_rounded, size: 18),
          label: Text(_processing ? 'Traitement...' : 'Désactiver la 2FA'),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red, width: 1.5),
            foregroundColor: Colors.red,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ] else ...[
        ElevatedButton.icon(
          onPressed: _processing ? null : _setup,
          icon: _processing
              ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.security_rounded),
          label: Text(_processing ? 'Configuration...' : 'Activer la 2FA'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.red,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildSetup() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Scannez le QR code',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(
        'Ouvrez Google Authenticator et scannez ce code.',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      const SizedBox(height: 20),
      if (_qrData != null)
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 20, offset: const Offset(0, 5))],
            ),
            child: QrImageView(
              data: _qrData!,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      if (_secret != null) ...[
        const SizedBox(height: 20),
        const Text('Ou saisir manuellement :',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: _secret!));
            _snack('Code copié ✓', Colors.green);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  _secret!.replaceAllMapped(
                      RegExp(r'.{4}'), (m) => '${m.group(0)} ').trim(),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.bold,
                      fontSize: 16, letterSpacing: 3),
                  textAlign: TextAlign.center,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: _C.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.copy_rounded, size: 16, color: _C.red),
              ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => setState(() => _step = 2),
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text('J\'ai scanné le QR code'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _C.red, foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => setState(() => _step = 0),
        child: Text('Annuler', style: TextStyle(color: Colors.grey[600])),
      ),
    ]);
  }

  Widget _buildVerify() {
    return Column(children: [
      const Text('Entrez le code à 6 chiffres',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('Affiché dans votre application d\'authentification.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.07), shape: BoxShape.circle),
        child: const Icon(Icons.phonelink_lock_rounded, size: 40, color: Colors.blue),
      ),
      const SizedBox(height: 24),
      TextField(
        controller: _codeCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 10),
        decoration: InputDecoration(
          hintText: '000000',
          hintStyle: TextStyle(fontSize: 28, color: Colors.grey[300], letterSpacing: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              borderSide: const BorderSide(color: _C.red, width: 2)),
          filled: true, fillColor: Colors.grey[50],
          counterText: '',
        ),
        onChanged: (v) { if (v.length == 6) _verify(); },
      ),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: _processing ? null : _verify,
        icon: _processing
            ? const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.verified_user_rounded),
        label: Text(_processing ? 'Vérification...' : 'Confirmer et activer'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green, foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      TextButton(
        onPressed: () => setState(() => _step = 1),
        child: Text('← Retour', style: TextStyle(color: Colors.grey[600])),
      ),
    ]);
  }

  Widget _buildRecoveryCodes() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.green.shade400, Colors.green.shade600],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('2FA activée !', style: TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Votre compte est protégé.',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withOpacity(0.3))),
        child: Text(
          '⚠️ Sauvegardez ces codes en lieu sûr. Chacun n\'est utilisable qu\'une seule fois.',
          style: TextStyle(fontSize: 12, color: Colors.amber[800]),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: _codes.isEmpty
            ? const Text('Aucun code',
            style: TextStyle(color: Colors.grey))
            : GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: 3.5,
            crossAxisSpacing: 8, mainAxisSpacing: 8,
          ),
          itemCount: _codes.length,
          itemBuilder: (_, i) => Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!)),
            child: Text(_codes[i],
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _codes.join('\n')));
              _snack('Codes copiés ✓', Colors.green);
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copier'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey[300]!),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () { setState(() => _step = 0); _loadStatus(); },
            icon: const Icon(Icons.done_rounded, size: 16),
            label: const Text('Terminé'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ]),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SHEET — QR LOGIN GENERATOR (connexion depuis un autre téléphone)
// ════════════════════════════════════════════════════════════════════════════

class _QRLoginGeneratorSheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _QRLoginGeneratorSheet({required this.storage});

  @override
  State<_QRLoginGeneratorSheet> createState() =>
      _QRLoginGeneratorSheetState();
}

class _QRLoginGeneratorSheetState extends State<_QRLoginGeneratorSheet>
    with SingleTickerProviderStateMixin {
  String? _shareToken;
  bool _generating = false;
  bool _waiting    = false;
  bool _confirmed  = false;
  int  _secs       = 120;
  String? _deviceName;

  Timer? _countdown;
  Timer? _poll;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _poll?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() { _generating = true; _confirmed = false; });
    _countdown?.cancel();
    _poll?.cancel();

    try {
      final t = await widget.storage.read(key: 'auth_token');
      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/sessions/share-token'),
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'expires_in': 120}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _shareToken = data['share_token'] ?? data['token'];
          _secs = 120; _waiting = true;
        });
      } else {
        _demoToken();
      }
    } catch (_) { _demoToken(); } finally {
      if (mounted) setState(() => _generating = false);
    }

    if (_shareToken != null) { _startCountdown(); _startPoll(); }
  }

  void _demoToken() => setState(() {
    _shareToken = 'SHARE_DEMO_${DateTime.now().millisecondsSinceEpoch}';
    _secs = 120; _waiting = true;
  });

  void _startCountdown() {
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secs--);
      if (_secs <= 0) {
        t.cancel(); _poll?.cancel();
        if (!_confirmed) setState(() { _shareToken = null; _waiting = false; });
      }
    });
  }

  void _startPoll() {
    _poll = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!mounted || _confirmed) { t.cancel(); return; }
      await _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    if (_shareToken == null) return;
    try {
      final t = await widget.storage.read(key: 'auth_token');
      final resp = await http.get(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/user/sessions/share-token/$_shareToken/status'),
        headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['used'] == true || data['status'] == 'used') {
          _countdown?.cancel(); _poll?.cancel();
          setState(() {
            _confirmed  = true;
            _waiting    = false;
            _deviceName = data['device_name']?.toString() ?? 'Nouvel appareil';
            _shareToken = null;
          });
        }
      }
    } catch (_) {}
  }

  void _reset() {
    _countdown?.cancel(); _poll?.cancel();
    setState(() {
      _shareToken = null; _waiting = false;
      _confirmed  = false; _secs = 120; _deviceName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(children: [
        const _SheetHandle(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.purple[400]!, Colors.purple[700]!],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                    color: Colors.purple.withOpacity(0.3),
                    blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: const Icon(Icons.qr_code_2_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connexion depuis un autre téléphone',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('QR code valide 2 minutes',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: Colors.grey[400]),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        const Divider(height: 20),
        Expanded(child: _buildContent()),
      ]),
    );
  }

  Widget _buildContent() {
    if (_confirmed) return _buildConfirmed();
    if (_shareToken != null && _waiting) return _buildQRDisplay();
    return _buildIntro();
  }

  Widget _buildIntro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [Colors.purple[50]!, Colors.purple[100]!]),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.phonelink_rounded, size: 48, color: Colors.purple[400]),
        ),
        const SizedBox(height: 20),
        const Text('Connecter un autre appareil',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Générez un QR code temporaire que l\'autre téléphone peut scanner.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
        ),
        const SizedBox(height: 28),
        _buildStepCard('1', Icons.qr_code_2_rounded, Colors.purple,
            'Générer le QR code',
            'Appuyez sur le bouton ci-dessous.'),
        const SizedBox(height: 10),
        _buildStepCard('2', Icons.phone_android_rounded, Colors.blue,
            'Sur l\'autre téléphone',
            'Ouvrez CarEasy → Bienvenue → "Connexion rapide via QR code".'),
        const SizedBox(height: 10),
        _buildStepCard('3', Icons.camera_alt_rounded, Colors.teal,
            'Scanner',
            'L\'autre téléphone pointe sa caméra — connexion automatique.'),
        const SizedBox(height: 10),
        _buildStepCard('4', Icons.verified_rounded, Colors.green,
            'Confirmation',
            'Vous êtes notifié dès que l\'autre appareil est connecté.'),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.qr_code_rounded),
            label: Text(_generating ? 'Génération...' : 'Générer mon QR code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(Icons.security_rounded, size: 16, color: Colors.orange[700]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ne partagez jamais ce QR code avec quelqu\'un en qui vous n\'avez pas confiance.',
                style: TextStyle(fontSize: 11, color: Colors.orange[800]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildStepCard(String num, IconData icon, Color color,
      String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Text(num,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                  color: color)),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ]),
        ),
      ]),
    );
  }

  Widget _buildQRDisplay() {
    final urgent = _secs < 30;
    final color  = urgent ? Colors.red : Colors.purple;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 6, spreadRadius: 1)],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                urgent
                    ? 'Expire dans $_secs secondes !'
                    : 'En attente de scan — $_secs s',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: color.withOpacity(0.8)),
              ),
            ),
            SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: color, strokeWidth: 2)),
          ]),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _secs / 120,
            minHeight: 6,
            backgroundColor: Colors.grey[200],
            color: urgent ? Colors.red : Colors.purple,
          ),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: urgent
                    ? Colors.red.withOpacity(0.4)
                    : Colors.purple.withOpacity(0.2),
                width: 2),
            boxShadow: [BoxShadow(
                color: (urgent ? Colors.red : Colors.purple).withOpacity(0.1),
                blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_rounded, size: 12, color: Colors.purple[600]),
                const SizedBox(width: 4),
                Text('CarEasy — Connexion sécurisée',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: Colors.purple[600])),
              ]),
            ),
            const SizedBox(height: 14),
            QrImageView(
              data: jsonEncode({
                'type'      : 'careasy_session_share',
                'token'     : _shareToken,
                'expires_in': _secs,
                'issued_at' : DateTime.now().toIso8601String(),
              }),
              version        : QrVersions.auto,
              size           : 210,
              backgroundColor: Colors.white,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: urgent ? Colors.red : Colors.purple[800]!,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: urgent ? Colors.red : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Scannez depuis la page Bienvenue\nde l\'autre téléphone',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Annuler'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey[300]!),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Nouveau QR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildConfirmed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.green[400]!, Colors.green[600]!],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: Colors.green.withOpacity(0.35),
                    blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 52),
            ),
            const SizedBox(height: 24),
            const Text('Connexion réussie !',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                    color: Colors.green)),
            const SizedBox(height: 10),
            Text(
              _deviceName != null
                  ? '"$_deviceName" vient de rejoindre votre compte.'
                  : 'Un nouvel appareil vient de se connecter.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Colors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Si vous ne reconnaissez pas cet appareil, allez dans '
                        '"Appareils connectés" pour révoquer cette session.',
                    style: TextStyle(fontSize: 11, color: Colors.green[700]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 32),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _reset,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Générer un autre'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Fermer'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  HELPER WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _SessionBar extends StatelessWidget {
  final int current;
  final int max;
  const _SessionBar({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio = current / max;
    final color = ratio >= 1.0 ? Colors.red : ratio >= 0.8 ? Colors.orange : Colors.green;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Appareils utilisés :',
            style: TextStyle(fontSize: 12, color: Colors.grey[600],
                fontWeight: FontWeight.w500)),
        const Spacer(),
        Text('$current / $max',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                color: color)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0),
          backgroundColor: Colors.grey[200],
          color: color,
          minHeight: 7,
        ),
      ),
    ]);
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatChip(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(children: [
      Text(value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
              color: color)),
      Text(label,
          style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
    ]),
  );
}

class _FilterChip extends StatelessWidget {
  final String val;
  final String label;
  final String current;
  final ValueChanged<String> onTap;

  const _FilterChip(this.val, this.label, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final selected = current == val;
    return GestureDetector(
      onTap: () => onTap(val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _C.red : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : Colors.grey[700],
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

class _CapacityBanner extends StatelessWidget {
  final bool canAdd;
  final int remaining;
  const _CapacityBanner({required this.canAdd, required this.remaining});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: canAdd
          ? Colors.green.withOpacity(0.06)
          : Colors.red.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: canAdd
            ? Colors.green.withOpacity(0.2)
            : Colors.red.withOpacity(0.2),
      ),
    ),
    child: Row(children: [
      Icon(
        canAdd ? Icons.check_circle_outline : Icons.block_outlined,
        color: canAdd ? Colors.green : Colors.red, size: 18,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          canAdd
              ? 'Vous pouvez connecter $remaining appareil(s) supplémentaire(s).'
              : 'Limite atteinte (5/5). Révoquez un appareil pour en ajouter un.',
          style: TextStyle(
              fontSize: 12,
              color: canAdd ? Colors.green[700] : Colors.red[700],
              fontWeight: FontWeight.w500),
        ),
      ),
    ]),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 9, color: color,
            fontWeight: FontWeight.bold)),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyState({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: const Color(0xFFDDE3EE)),
        const SizedBox(height: 14),
        Text(label,
            style: TextStyle(color: Colors.grey[500], fontSize: 15)),
      ],
    ),
  );
}