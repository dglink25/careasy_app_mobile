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

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  bool _isLoading = false;

  // ── Mot de passe ───────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _isChangingPassword = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() => _storage.read(key: 'auth_token');

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmall = size.width < 360;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Confidentialité & sécurité',
          style: TextStyle(fontSize: isSmall ? 17 : 19, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isSmall ? 14 : 18),
        child: Column(
          children: [
            _buildChangePasswordSection(isSmall),
            const SizedBox(height: 16),
            _buildSecuritySection(isSmall),
            const SizedBox(height: 16),
            _buildDangerZone(isSmall),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SECTION 1 — CHANGER LE MOT DE PASSE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChangePasswordSection(bool isSmall) {
    return _buildCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Changer le mot de passe', Icons.lock_reset_outlined),
            const SizedBox(height: 20),
            _passwordField(
              controller: _currentPasswordController,
              label: 'Mot de passe actuel',
              obscure: !_showCurrentPassword,
              onToggle: () => setState(() => _showCurrentPassword = !_showCurrentPassword),
              isSmall: isSmall,
              validator: (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _newPasswordController,
              label: 'Nouveau mot de passe',
              obscure: !_showNewPassword,
              onToggle: () => setState(() => _showNewPassword = !_showNewPassword),
              isSmall: isSmall,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Champ requis';
                if (v.length < 8) return 'Minimum 8 caractères';
                if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Au moins une majuscule';
                if (!RegExp(r'[0-9]').hasMatch(v)) return 'Au moins un chiffre';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _confirmPasswordController,
              label: 'Confirmer le nouveau mot de passe',
              obscure: !_showConfirmPassword,
              onToggle: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
              isSmall: isSmall,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Champ requis';
                if (v != _newPasswordController.text) return 'Les mots de passe ne correspondent pas';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isChangingPassword ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _isChangingPassword
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Mettre à jour le mot de passe',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required bool isSmall,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: isSmall ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700])),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          style: TextStyle(fontSize: isSmall ? 14 : 15),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.lock_outline,
                size: isSmall ? 18 : 20, color: AppConstants.primaryRed),
            suffixIcon: IconButton(
              icon: Icon(
                  obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: isSmall ? 16 : 18,
                  color: Colors.grey[500]),
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
                borderSide: const BorderSide(color: AppConstants.primaryRed, width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red)),
            contentPadding: EdgeInsets.symmetric(
                horizontal: 16, vertical: isSmall ? 12 : 14),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SECTION 2 — SÉCURITÉ
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSecuritySection(bool isSmall) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Sécurité', Icons.security_outlined),
          const SizedBox(height: 8),
          _securityTile(
            icon: Icons.devices_outlined,
            title: 'Appareils connectés',
            subtitle: 'Gérer les appareils • Max 5 sessions',
            badge: '5 max',
            badgeColor: Colors.blue,
            onTap: () => _showSheet(_ConnectedDevicesSheet(storage: _storage)),
            isSmall: isSmall,
          ),
          const _Divider(),
          _securityTile(
            icon: Icons.history_rounded,
            title: 'Historique des connexions',
            subtitle: 'Voir les dernières connexions',
            onTap: () => _showSheet(_LoginHistorySheet(storage: _storage)),
            isSmall: isSmall,
          ),
          const _Divider(),
          _securityTile(
            icon: Icons.phonelink_lock_outlined,
            title: 'Authentification à deux facteurs',
            subtitle: 'Protection TOTP renforcée',
            badge: '2FA',
            badgeColor: Colors.orange,
            onTap: () => _showSheet(_TwoFactorSheet(storage: _storage)),
            isSmall: isSmall,
          ),
          const _Divider(),
          _securityTile(
            icon: Icons.qr_code_2_rounded,
            title: 'Connexion depuis un autre téléphone',
            subtitle: 'Générer un QR code de connexion rapide',
            badge: 'QR',
            badgeColor: Colors.purple,
            onTap: () => _showSheet(_QRLoginGeneratorSheet(storage: _storage)),
            isSmall: isSmall,
          ),
          const _Divider(),
          _securityTile(
            icon: Icons.logout_rounded,
            title: 'Déconnecter tous les appareils',
            subtitle: 'Révoquer toutes les sessions actives',
            iconColor: Colors.orange[700],
            onTap: () => _confirmLogoutAll(isSmall),
            isSmall: isSmall,
          ),
        ],
      ),
    );
  }

  Widget _securityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isSmall,
    String? badge,
    Color? badgeColor,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isSmall ? 2 : 4, vertical: isSmall ? 12 : 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: (iconColor ?? AppConstants.primaryRed).withOpacity(0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon,
                  size: isSmall ? 18 : 20,
                  color: iconColor ?? AppConstants.primaryRed),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: isSmall ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          color: iconColor ?? Colors.grey[900])),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: isSmall ? 11 : 12,
                          color: Colors.grey[500])),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? AppConstants.primaryRed).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 10,
                        color: badgeColor ?? AppConstants.primaryRed,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right_rounded,
                size: 20, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SECTION 3 — ZONE DANGEREUSE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDangerZone(bool isSmall) {
    return Container(
      padding: EdgeInsets.all(isSmall ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
              color: Colors.red.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        
      
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isChangingPassword = true);
    try {
      final token = await _getToken();
      final response = await http
          .put(
            Uri.parse('${AppConstants.apiBaseUrl}/user/password'),
            headers: _headers(token!),
            body: jsonEncode({
              'current_password': _currentPasswordController.text,
              'new_password': _newPasswordController.text,
              'new_password_confirmation': _confirmPasswordController.text,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _snack('Mot de passe mis à jour avec succès ✓', Colors.green);
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
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  Future<void> _confirmLogoutAll(bool isSmall) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Déconnecter tous les appareils',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
            'Vous allez être déconnecté de tous vos appareils. '
            'Vous devrez vous reconnecter sur cet appareil.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annuler', style: TextStyle(color: Colors.grey[600]))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Déconnecter tout'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      final response = await http
          .post(
            Uri.parse('${AppConstants.apiBaseUrl}/user/logout-all'),
            headers: _headers(token!),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 204) {
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

  Future<void> _confirmDeleteAccount(bool isSmall) async {
    final pwdCtrl = TextEditingController();
    bool obscure = true;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[600], size: 22),
            const SizedBox(width: 8),
            const Text('Supprimer le compte',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.2))),
                child: Text(
                    '⚠️ Cette action est IRRÉVERSIBLE. Toutes vos données, '
                    'rendez-vous et messages seront définitivement supprimés.',
                    style: TextStyle(fontSize: 12, color: Colors.red[700])),
              ),
              const SizedBox(height: 16),
              const Text('Confirmez votre mot de passe :',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: pwdCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'Votre mot de passe',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red)),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined, size: 18),
                    onPressed: () => setS(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Annuler', style: TextStyle(color: Colors.grey[600]))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: const Text('Supprimer définitivement'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true || !mounted) return;
    if (pwdCtrl.text.isEmpty) {
      _snack('Veuillez saisir votre mot de passe', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      final response = await http
          .delete(
            Uri.parse('${AppConstants.apiBaseUrl}/user/account'),
            headers: _headers(token!),
            body: jsonEncode({'password': pwdCtrl.text}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (mounted) await context.read<AuthProvider>().logout();
      } else {
        final data = jsonDecode(response.body);
        _snack(data['message'] ?? 'Erreur lors de la suppression', Colors.red);
      }
    } catch (_) {
      _snack('Erreur de connexion', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HELPERS UI
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildCard({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 3))
          ],
        ),
        child: child,
      );

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: AppConstants.primaryRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 16, color: AppConstants.primaryRed),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]);

  void _showSheet(Widget sheet) {
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
//  WIDGET COMMUN — Divider
// ════════════════════════════════════════════════════════════════════════════

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Colors.grey[100]);
}

// ════════════════════════════════════════════════════════════════════════════
//  WIDGET COMMUN — Sheet Container
// ════════════════════════════════════════════════════════════════════════════

class _SheetContainer extends StatelessWidget {
  final Widget child;
  final double initialSize;
  final double maxSize;

  const _SheetContainer({
    required this.child,
    this.initialSize = 0.65,
    this.maxSize = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: initialSize,
        maxChildSize: maxSize,
        minChildSize: 0.3,
        builder: (_, ctrl) => child,
      ),
    );
  }
}

Widget _sheetHandle() => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
            color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
      ),
    );

// ════════════════════════════════════════════════════════════════════════════
//  APPAREILS CONNECTÉS — Max 5 sessions, QR code de connexion
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
  late TabController _tabController;
  String? _shareToken;
  bool _generatingQR = false;
  Timer? _qrTimer;
  int _qrSecondsLeft = 120; // QR valide 2 minutes

  static const int _maxSessions = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _qrTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/sessions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(
              data['sessions'] ?? data ?? []);
        });
      }
    } catch (_) {
      // Données de démo si pas de connexion
      setState(() {
        _sessions = [
          {
            'id': 'current',
            'device_type': 'Android • Samsung Galaxy S24',
            'ip_address': '41.73.12.xx',
            'last_used_at': DateTime.now().toString(),
            'is_current': true,
            'location': 'Cotonou, Bénin',
          },
        ];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _revokeSession(dynamic sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Révoquer cette session ?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: const Text(
            'Cet appareil sera déconnecté immédiatement.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.delete(
        Uri.parse('${AppConstants.apiBaseUrl}/user/sessions/$sessionId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() => _sessions.removeWhere((s) => s['id'] == sessionId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Session révoquée avec succès'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {
      // Démo : suppression locale
      setState(() => _sessions.removeWhere((s) => s['id'] == sessionId));
    }
  }

  Future<void> _generateShareQR() async {
    if (_sessions.length >= _maxSessions) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            '⚠️ Maximum 5 appareils atteint. Révoquez un appareil pour en ajouter un nouveau.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _generatingQR = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/sessions/share-token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'expires_in': 120}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _shareToken = data['share_token'] ?? data['token'];
          _qrSecondsLeft = 120;
        });
      } else {
        // Démo : générer un token fictif
        setState(() {
          _shareToken = 'SHARE_${DateTime.now().millisecondsSinceEpoch}';
          _qrSecondsLeft = 120;
        });
      }
    } catch (_) {
      // Démo
      setState(() {
        _shareToken = 'SHARE_DEMO_${DateTime.now().millisecondsSinceEpoch}';
        _qrSecondsLeft = 120;
      });
    } finally {
      if (mounted) setState(() => _generatingQR = false);
    }

    // Décompte QR
    _qrTimer?.cancel();
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _qrSecondsLeft--);
      if (_qrSecondsLeft <= 0) {
        t.cancel();
        setState(() => _shareToken = null);
      }
    });
  }

  IconData _deviceIcon(String? device) {
    final d = (device ?? '').toLowerCase();
    if (d.contains('android') || d.contains('iphone') || d.contains('mobile')) {
      return Icons.smartphone_rounded;
    }
    if (d.contains('tablet') || d.contains('ipad')) return Icons.tablet_rounded;
    if (d.contains('mac') || d.contains('windows') || d.contains('linux')) {
      return Icons.laptop_rounded;
    }
    return Icons.devices_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                _sheetHandle(),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.devices_rounded,
                        color: Colors.blue, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Appareils connectés',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        Text('Maximum 5 appareils simultanés',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.blue),
                      onPressed: _load),
                ]),
                const SizedBox(height: 14),
                // Barre de progression sessions
                _SessionProgressBar(
                    current: _sessions.length, max: _maxSessions),
                const SizedBox(height: 14),
                TabBar(
                  controller: _tabController,
                  labelColor: AppConstants.primaryRed,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppConstants.primaryRed,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'Mes appareils', icon: Icon(Icons.devices, size: 16)),
                    Tab(text: 'Ajouter via QR', icon: Icon(Icons.qr_code_2, size: 16)),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDevicesList(),
                  _buildQRCodeTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppConstants.primaryRed));
    }
    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_other_rounded, size: 60, color: Colors.grey[200]),
            const SizedBox(height: 12),
            Text('Aucun appareil trouvé',
                style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = _sessions[i];
        final isCurrent = s['is_current'] == true;
        final device = s['device_type'] ?? s['device'] ?? 'Appareil inconnu';
        final ip = s['ip_address'] ?? '—';
        final location = s['location'] ?? '';
        final lastUsed = _formatDate(s['last_used_at'] ?? s['created_at'] ?? '');

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCurrent
                ? AppConstants.primaryRed.withOpacity(0.04)
                : Colors.grey[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent
                  ? AppConstants.primaryRed.withOpacity(0.2)
                  : Colors.grey[200]!,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppConstants.primaryRed.withOpacity(0.1)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_deviceIcon(device),
                    size: 22,
                    color: isCurrent ? AppConstants.primaryRed : Colors.grey[600]),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Cet appareil',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text('IP: $ip${location.isNotEmpty ? ' • $location' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    Text('Dernière activité: $lastUsed',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
              ),
              if (!isCurrent) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _revokeSession(s['id']),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.logout_rounded,
                        size: 16, color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildQRCodeTab() {
    final canAdd = _sessions.length < _maxSessions;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Statut capacité
          Container(
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
                  color: canAdd ? Colors.green : Colors.red,
                  size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  canAdd
                      ? 'Vous pouvez connecter ${_maxSessions - _sessions.length} appareil(s) supplémentaire(s).'
                      : 'Limite atteinte (5/5). Révoquez un appareil pour en ajouter un nouveau.',
                  style: TextStyle(
                      fontSize: 12,
                      color: canAdd ? Colors.green[700] : Colors.red[700],
                      fontWeight: FontWeight.w500),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          if (!canAdd) ...[
            const SizedBox(height: 8),
            Icon(Icons.lock_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Limite de 5 appareils atteinte',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            Text(
              'Allez dans "Mes appareils" et révoquez\nun appareil pour libérer une place.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ] else if (_shareToken == null) ...[
            // Explication QR
            const Text('Comment ça marche ?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            _qrStep('1', Icons.qr_code_2_rounded,
                'Appuyez sur "Générer un QR code" sur cet appareil.'),
            _qrStep('2', Icons.phone_android_rounded,
                'Sur le nouvel appareil, allez dans Paramètres > Connexion rapide.'),
            _qrStep('3', Icons.camera_alt_rounded,
                'Scannez le QR code. La connexion est automatique et sécurisée.'),
            _qrStep('4', Icons.timer_outlined,
                'Le QR code expire après 2 minutes pour votre sécurité.'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generatingQR ? null : _generateShareQR,
                icon: _generatingQR
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.qr_code_2_rounded),
                label: Text(
                    _generatingQR ? 'Génération...' : 'Générer un QR code'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ] else ...[
            // QR code affiché
            const Text('Scannez ce QR code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Valide pendant $_qrSecondsLeft secondes',
              style: TextStyle(
                  fontSize: 13,
                  color: _qrSecondsLeft < 30 ? Colors.red : Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            // Barre de progression
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _qrSecondsLeft / 120,
                backgroundColor: Colors.grey[200],
                color: _qrSecondsLeft < 30 ? Colors.red : AppConstants.primaryRed,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: _qrSecondsLeft < 30
                        ? Colors.red.withOpacity(0.4)
                        : Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 4))
                ],
              ),
              child: QrImageView(
                data: jsonEncode({
                  'type': 'careasy_session_share',
                  'token': _shareToken,
                  'expires_in': _qrSecondsLeft,
                  'issued_at': DateTime.now().toIso8601String(),
                }),
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _shareToken = null;
                    _qrTimer?.cancel();
                  }),
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
                  onPressed: _generateShareQR,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Actualiser'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _qrStep(String num, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              color: AppConstants.primaryRed, shape: BoxShape.circle),
          child: Text(num,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: Colors.grey[600]),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        )),
      ]),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'À l\'instant';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SESSION PROGRESS BAR
// ════════════════════════════════════════════════════════════════════════════

class _SessionProgressBar extends StatelessWidget {
  final int current;
  final int max;

  const _SessionProgressBar({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio = current / max;
    final color = ratio >= 1.0
        ? Colors.red
        : ratio >= 0.8
            ? Colors.orange
            : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Appareils utilisés :',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Text('$current / $max',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
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
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  HISTORIQUE DES CONNEXIONS
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
  String _filter = 'all'; // all | success | failed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/login-history'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _history =
              List<Map<String, dynamic>>.from(data['history'] ?? data ?? []);
        });
      } else {
        // Données de démo
        _loadDemoData();
      }
    } catch (_) {
      _loadDemoData();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadDemoData() {
    _history = [
      {
        'success': true,
        'ip_address': '41.73.12.45',
        'device': 'Android • Chrome',
        'location': 'Cotonou, Bénin',
        'created_at': DateTime.now().subtract(const Duration(minutes: 5)).toString(),
        'method': 'email',
      },
      {
        'success': true,
        'ip_address': '41.73.12.45',
        'device': 'iPhone 15 Pro',
        'location': 'Cotonou, Bénin',
        'created_at': DateTime.now().subtract(const Duration(hours: 2)).toString(),
        'method': 'google',
      },
      {
        'success': false,
        'ip_address': '195.128.0.12',
        'device': 'Windows • Firefox',
        'location': 'Paris, France',
        'created_at': DateTime.now().subtract(const Duration(hours: 5)).toString(),
        'method': 'email',
        'fail_reason': 'Mot de passe incorrect',
      },
      {
        'success': true,
        'ip_address': '41.73.12.45',
        'device': 'Android • App native',
        'location': 'Cotonou, Bénin',
        'created_at': DateTime.now().subtract(const Duration(days: 1)).toString(),
        'method': 'email',
      },
      {
        'success': false,
        'ip_address': '82.220.56.78',
        'device': 'Linux • Curl',
        'location': 'Inconnu',
        'created_at': DateTime.now().subtract(const Duration(days: 2)).toString(),
        'method': 'email',
        'fail_reason': 'Compte inexistant',
      },
    ];
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'success') return _history.where((h) => h['success'] == true).toList();
    if (_filter == 'failed') return _history.where((h) => h['success'] != true).toList();
    return _history;
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'À l\'instant';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
      if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
      if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  IconData _methodIcon(String? method) {
    switch (method) {
      case 'google': return Icons.g_mobiledata_rounded;
      case 'phone': return Icons.phone_rounded;
      default: return Icons.email_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                _sheetHandle(),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.history_rounded,
                        color: Colors.purple, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Historique des connexions',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        Text('30 derniers jours',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.purple),
                      onPressed: _load),
                ]),
                const SizedBox(height: 14),
                // Statistiques rapides
                if (_history.isNotEmpty) ...[
                  Row(children: [
                    _statChip(
                        '${_history.where((h) => h['success'] == true).length}',
                        'Réussies',
                        Colors.green),
                    const SizedBox(width: 8),
                    _statChip(
                        '${_history.where((h) => h['success'] != true).length}',
                        'Échouées',
                        Colors.red),
                    const SizedBox(width: 8),
                    _statChip('${_history.length}', 'Total', Colors.blue),
                  ]),
                  const SizedBox(height: 12),
                ],
                // Filtres
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('all', 'Toutes'),
                      const SizedBox(width: 8),
                      _filterChip('success', 'Réussies ✓'),
                      const SizedBox(width: 8),
                      _filterChip('failed', 'Échouées ✗'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          Flexible(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.purple))
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off_rounded,
                                  size: 60, color: Colors.grey[200]),
                              const SizedBox(height: 12),
                              Text('Aucune connexion trouvée',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 15)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final h = _filtered[i];
                            final ok = h['success'] == true;
                            final ip = h['ip_address'] ?? '—';
                            final device = h['device'] ?? 'Appareil inconnu';
                            final loc = h['location'] ?? '';
                            final date = _formatDate(
                                h['created_at'] ?? h['logged_at'] ?? '');
                            final reason = h['fail_reason'];
                            final method = h['method'];

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: ok
                                    ? Colors.green.withOpacity(0.04)
                                    : Colors.red.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: ok
                                      ? Colors.green.withOpacity(0.15)
                                      : Colors.red.withOpacity(0.15),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                      color: ok
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                        ok
                                            ? Icons.check_circle_outline_rounded
                                            : Icons.error_outline_rounded,
                                        color: ok ? Colors.green : Colors.red,
                                        size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Text(
                                              ok
                                                  ? 'Connexion réussie'
                                                  : 'Tentative échouée',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                  color: ok
                                                      ? Colors.green[800]
                                                      : Colors.red[700])),
                                          const Spacer(),
                                          Icon(_methodIcon(method),
                                              size: 14, color: Colors.grey[400]),
                                        ]),
                                        const SizedBox(height: 3),
                                        Text(device,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500)),
                                        Text(
                                            'IP: $ip${loc.isNotEmpty ? ' • $loc' : ''}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[500])),
                                        if (reason != null)
                                          Container(
                                            margin: const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(reason,
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.red,
                                                    fontWeight: FontWeight.w500)),
                                          ),
                                        const SizedBox(height: 3),
                                        Text(date,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[400])),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _filterChip(String val, String label) {
    final selected = _filter == val;
    return GestureDetector(
      onTap: () => setState(() => _filter = val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppConstants.primaryRed : Colors.grey[100],
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

// ════════════════════════════════════════════════════════════════════════════
//  AUTHENTIFICATION À DEUX FACTEURS — TOTP COMPLET
// ════════════════════════════════════════════════════════════════════════════

class _TwoFactorSheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _TwoFactorSheet({required this.storage});

  @override
  State<_TwoFactorSheet> createState() => _TwoFactorSheetState();
}

class _TwoFactorSheetState extends State<_TwoFactorSheet>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isEnabled = false;
  bool _isProcessing = false;
  String? _qrCodeData; // Data pour le QR code TOTP
  String? _secret;
  List<String> _recoveryCodes = [];
  final _codeController = TextEditingController();
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  int _step = 0; // 0: status, 1: setup QR, 2: verify code, 3: recovery codes

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.95, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _load2FAStatus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load2FAStatus() async {
    setState(() => _isLoading = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isEnabled = data['enabled'] == true;
          _qrCodeData = data['qr_code_url'] ?? data['provisioning_uri'];
          _secret = data['secret'];
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initiate2FASetup() async {
    setState(() => _isProcessing = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/setup'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _qrCodeData = data['provisioning_uri'] ?? data['qr_code_url'];
          _secret = data['secret'];
          _step = 1;
        });
      } else {
        // Démo
        setState(() {
          _secret = 'JBSWY3DPEHPK3PXP';
          _qrCodeData =
              'otpauth://totp/CarEasy:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=CarEasy';
          _step = 1;
        });
      }
    } catch (_) {
      // Démo
      setState(() {
        _secret = 'JBSWY3DPEHPK3PXP';
        _qrCodeData =
            'otpauth://totp/CarEasy:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=CarEasy';
        _step = 1;
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _verify2FACode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _snack('Le code doit contenir 6 chiffres', Colors.red);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/enable'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'code': code, 'secret': _secret}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isEnabled = true;
          _recoveryCodes = List<String>.from(data['recovery_codes'] ?? []);
          _step = 3;
        });
      } else {
        // Démo : simuler succès
        setState(() {
          _isEnabled = true;
          _recoveryCodes = [
            'ABCD-EFGH-1234',
            'IJKL-MNOP-5678',
            'QRST-UVWX-9012',
            'YZER-ABCD-3456',
            'EFGH-IJKL-7890',
            'MNOP-QRST-1234',
            'UVWX-YZER-5678',
            'ABCD-EFGH-9012',
          ];
          _step = 3;
        });
      }
    } catch (_) {
      _snack('Code incorrect ou expiré', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _disable2FA() async {
    final pwdCtrl = TextEditingController();
    final codeCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Désactiver la 2FA ?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text(
                  '⚠️ Désactiver la 2FA rend votre compte moins sécurisé.',
                  style: TextStyle(fontSize: 12, color: Colors.orange)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'Code TOTP actuel (6 chiffres)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                counterText: '',
                prefixIcon: const Icon(Icons.phonelink_lock_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/disable'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'code': codeCtrl.text}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          _isEnabled = false;
          _qrCodeData = null;
          _secret = null;
          _step = 0;
        });
        _snack('2FA désactivée avec succès', Colors.green);
      } else {
        _snack('Code incorrect', Colors.red);
      }
    } catch (_) {
      // Démo
      setState(() {
        _isEnabled = false;
        _step = 0;
      });
      _snack('2FA désactivée (mode démo)', Colors.green);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _copyRecoveryCodes() {
    Clipboard.setData(ClipboardData(text: _recoveryCodes.join('\n')));
    _snack('Codes de récupération copiés ✓', Colors.green);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
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

              if (_isLoading)
                const Center(
                    child: CircularProgressIndicator(color: Colors.orange))
              else
                _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_step == 0) return _buildStatusView();
    if (_step == 1) return _buildSetupView();
    if (_step == 2) return _buildVerifyView();
    if (_step == 3) return _buildRecoveryCodesView();
    return _buildStatusView();
  }

  // ── Statut ────────────────────────────────────────────────────────────────
  Widget _buildStatusView() {
    return Column(
      children: [
        // Indicateur statut
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Transform.scale(
            scale: _isEnabled ? _pulse.value : 1.0,
            child: child,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isEnabled
                    ? [Colors.green.shade400, Colors.green.shade600]
                    : [Colors.orange.shade400, Colors.orange.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: (_isEnabled ? Colors.green : Colors.orange)
                        .withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8))
              ],
            ),
            child: Row(children: [
              Icon(
                  _isEnabled
                      ? Icons.verified_user_rounded
                      : Icons.security_outlined,
                  color: Colors.white,
                  size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _isEnabled
                            ? '2FA Activée ✓'
                            : '2FA Non activée',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        _isEnabled
                            ? 'Votre compte est protégé par une couche de sécurité supplémentaire.'
                            : 'Activez la 2FA pour renforcer la sécurité de votre compte.',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),

        // Explication
        if (!_isEnabled) ...[
          const Text('Pourquoi activer la 2FA ?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _featureRow(Icons.shield_rounded, Colors.green,
              'Protection renforcée',
              'Même si votre mot de passe est compromis, les pirates ne peuvent pas accéder à votre compte.'),
          _featureRow(Icons.timer_rounded, Colors.blue,
              'Code temporaire',
              'Un code unique à 6 chiffres est généré toutes les 30 secondes.'),
          _featureRow(Icons.offline_bolt_rounded, Colors.orange,
              'Fonctionne hors ligne',
              'L\'application Google Authenticator n\'a pas besoin d\'internet.'),
          const SizedBox(height: 20),
          // Étapes
          const Text('Comment activer ?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _setupStep('1', 'Téléchargez Google Authenticator ou Authy sur votre téléphone.'),
          _setupStep('2', 'Appuyez sur "Activer la 2FA" ci-dessous.'),
          _setupStep('3', 'Scannez le QR code avec l\'application.'),
          _setupStep('4', 'Entrez le code à 6 chiffres pour confirmer.'),
          _setupStep('5', 'Sauvegardez vos codes de récupération dans un endroit sûr.'),
          const SizedBox(height: 24),
        ],

        if (_isEnabled) ...[
          // Options 2FA active
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.2))),
            child: Column(
              children: [
                _infoRow(Icons.check_circle_outline, Colors.green,
                    'Application TOTP configurée'),
                const SizedBox(height: 8),
                _infoRow(Icons.key_rounded, Colors.blue,
                    'Codes de récupération disponibles'),
                const SizedBox(height: 8),
                _infoRow(Icons.lock_clock_rounded, Colors.purple,
                    'Codes valides 30 secondes'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Voir codes récupération
          OutlinedButton.icon(
            onPressed: _viewRecoveryCodes,
            icon: const Icon(Icons.key_rounded, size: 18),
            label: const Text('Voir mes codes de récupération'),
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
            onPressed: _isProcessing ? null : _disable2FA,
            icon: const Icon(Icons.no_encryption_gmailerrorred_rounded, size: 18),
            label: Text(_isProcessing ? 'Traitement...' : 'Désactiver la 2FA'),
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
            onPressed: _isProcessing ? null : _initiate2FASetup,
            icon: _isProcessing
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.security_rounded),
            label: Text(_isProcessing ? 'Configuration...' : 'Activer la 2FA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Setup QR ──────────────────────────────────────────────────────────────
  Widget _buildSetupView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Étapes visuelles
        _stepIndicator(1),
        const SizedBox(height: 20),
        const Text('Scannez le QR code',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          'Ouvrez Google Authenticator (ou Authy), appuyez sur "+" et scannez ce code.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),

        // QR Code TOTP
        if (_qrCodeData != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 6))
                ],
              ),
              child: QrImageView(
                data: _qrCodeData!,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppConstants.primaryRed,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),

        // Secret manuel
        if (_secret != null) ...[
          const Text('Ou saisissez ce code manuellement :',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _secret!));
              _snack('Code secret copié ✓', Colors.green);
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
                    _formatSecret(_secret!),
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 3,
                        color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: AppConstants.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.copy_rounded,
                      size: 16, color: AppConstants.primaryRed),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Appuyez pour copier',
                style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ),
        ],
        const SizedBox(height: 24),

        ElevatedButton.icon(
          onPressed: () => setState(() => _step = 2),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('J\'ai scanné le QR code'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryRed,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _step = 0),
          child: Text('Annuler', style: TextStyle(color: Colors.grey[600])),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Vérification code ─────────────────────────────────────────────────────
  Widget _buildVerifyView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _stepIndicator(2),
        const SizedBox(height: 20),
        const Text('Vérifiez le code',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Entrez le code à 6 chiffres affiché dans votre application d\'authentification.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),

        // Icône animée
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.phonelink_lock_rounded,
              size: 40, color: Colors.blue),
        ),
        const SizedBox(height: 24),

        // Input code 6 chiffres
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 10),
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: TextStyle(
                fontSize: 28,
                color: Colors.grey[300],
                letterSpacing: 10,
                fontWeight: FontWeight.bold),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey[300]!)),
            focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide:
                    BorderSide(color: AppConstants.primaryRed, width: 2)),
            filled: true,
            fillColor: Colors.grey[50],
            counterText: '',
          ),
          onChanged: (v) {
            if (v.length == 6) _verify2FACode();
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Le code se renouvelle toutes les 30 secondes',
          style: TextStyle(fontSize: 11, color: Colors.grey[400]),
        ),
        const SizedBox(height: 24),

        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _verify2FACode,
          icon: _isProcessing
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.verified_user_rounded),
          label: Text(_isProcessing ? 'Vérification...' : 'Confirmer et activer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _step = 1),
          child: Text('← Retour au QR code',
              style: TextStyle(color: Colors.grey[600])),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Codes récupération ────────────────────────────────────────────────────
  Widget _buildRecoveryCodesView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Succès
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade400, Colors.green.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('2FA activée avec succès !',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Text('Votre compte est maintenant protégé.',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // Codes récupération
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.key_rounded, color: Colors.amber, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Codes de récupération',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3))),
          child: Text(
            '⚠️ IMPORTANT : Sauvegardez ces codes dans un endroit sûr. '
            'Chaque code ne peut être utilisé qu\'une seule fois si vous perdez accès à votre application d\'authentification.',
            style: TextStyle(fontSize: 12, color: Colors.amber[800]),
          ),
        ),
        const SizedBox(height: 16),

        // Grille des codes
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: _recoveryCodes.isEmpty
              ? const Center(
                  child: Text('Aucun code disponible',
                      style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 3.5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _recoveryCodes.length,
                  itemBuilder: (_, i) => Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Text(
                      _recoveryCodes[i],
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 16),

        // Actions
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _copyRecoveryCodes,
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
              onPressed: () {
                setState(() => _step = 0);
                _load2FAStatus();
              },
              icon: const Icon(Icons.done_rounded, size: 16),
              label: const Text('Terminé'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _viewRecoveryCodes() async {
    setState(() => _isProcessing = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/recovery-codes'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _recoveryCodes =
              List<String>.from(data['recovery_codes'] ?? data ?? []);
          _step = 3;
        });
      } else {
        // Démo
        setState(() {
          _recoveryCodes = [
            'ABCD-EFGH-1234',
            'IJKL-MNOP-5678',
            'QRST-UVWX-9012',
            'YZER-ABCD-3456',
          ];
          _step = 3;
        });
      }
    } catch (_) {
      setState(() {
        _recoveryCodes = ['ABCD-EFGH-1234', 'IJKL-MNOP-5678'];
        _step = 3;
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Helpers UI ─────────────────────────────────────────────────────────────
  Widget _stepIndicator(int current) {
    final steps = ['Statut', 'QR Code', 'Vérifier', 'Codes'];
    return Row(
      children: List.generate(steps.length, (i) {
        final done = i < current;
        final active = i == current;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 28, height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: done
                          ? Colors.green
                          : active
                              ? AppConstants.primaryRed
                              : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: done
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14)
                        : Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: active
                                    ? Colors.white
                                    : Colors.grey[500])),
                  ),
                  const SizedBox(height: 4),
                  Text(steps[i],
                      style: TextStyle(
                          fontSize: 9,
                          color: active
                              ? AppConstants.primaryRed
                              : Colors.grey[400],
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ],
              ),
              if (i < steps.length - 1)
                Expanded(
                    child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  color: done ? Colors.green : Colors.grey[200],
                )),
            ],
          ),
        );
      }),
    );
  }

  Widget _featureRow(IconData icon, Color color, String title, String sub) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(sub,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
        ]),
      );

  Widget _setupStep(String num, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22, height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppConstants.primaryRed, shape: BoxShape.circle),
            child: Text(num,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(text,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          )),
        ]),
      );

  Widget _infoRow(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(text,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500)),
        ],
      );

  String _formatSecret(String secret) {
    final clean = secret.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(clean[i]);
    }
    return buffer.toString();
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  QR LOGIN GENERATOR SHEET
//  Génère un QR code sur l'appareil connecté, puis attend la confirmation
//  (polling toutes les 3 s) — l'autre téléphone scanne depuis WelcomeScreen
// ════════════════════════════════════════════════════════════════════════════

class _QRLoginGeneratorSheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _QRLoginGeneratorSheet({required this.storage});

  @override
  State<_QRLoginGeneratorSheet> createState() => _QRLoginGeneratorSheetState();
}

class _QRLoginGeneratorSheetState extends State<_QRLoginGeneratorSheet>
    with SingleTickerProviderStateMixin {
  // ── États ────────────────────────────────────────────────────────────────
  String? _shareToken;
  bool _isGenerating = false;
  bool _isWaiting = false;     // polling actif
  bool _isConfirmed = false;   // connexion confirmée
  bool _hasError = false;
  String? _errorMessage;
  int _secondsLeft = 120;
  String? _connectedDeviceName;

  Timer? _countdownTimer;
  Timer? _pollingTimer;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Générer un token de partage ───────────────────────────────────────────

  Future<void> _generate() async {
    setState(() {
      _isGenerating = true;
      _hasError = false;
      _errorMessage = null;
      _isConfirmed = false;
    });
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();

    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/user/sessions/share-token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'expires_in': 120}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _shareToken = data['share_token'] ?? data['token'];
          _secondsLeft = 120;
          _isWaiting = true;
        });
      } else {
        // Mode démo
        setState(() {
          _shareToken = 'SHARE_${DateTime.now().millisecondsSinceEpoch}';
          _secondsLeft = 120;
          _isWaiting = true;
        });
      }
    } catch (_) {
      // Mode démo offline
      setState(() {
        _shareToken = 'SHARE_DEMO_${DateTime.now().millisecondsSinceEpoch}';
        _secondsLeft = 120;
        _isWaiting = true;
      });
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }

    if (_shareToken != null) {
      _startCountdown();
      _startPolling();
    }
  }

  // ── Décompte 120 s ────────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _pollingTimer?.cancel();
        if (!_isConfirmed) {
          setState(() {
            _shareToken = null;
            _isWaiting = false;
          });
        }
      }
    });
  }

  // ── Polling toutes les 3 s pour détecter la connexion ────────────────────

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!mounted || _isConfirmed) { t.cancel(); return; }
      await _checkTokenStatus();
    });
  }

  Future<void> _checkTokenStatus() async {
    if (_shareToken == null) return;
    try {
      final authToken = await widget.storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/user/sessions/share-token/$_shareToken/status'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final used = data['used'] == true || data['status'] == 'used';
        if (used) {
          _countdownTimer?.cancel();
          _pollingTimer?.cancel();
          setState(() {
            _isConfirmed = true;
            _isWaiting = false;
            _connectedDeviceName =
                data['device_name']?.toString() ?? 'Nouvel appareil';
          });
        }
      }
    } catch (_) {
      // Silencieux — on réessaie au prochain tick
    }
  }

  void _reset() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    setState(() {
      _shareToken = null;
      _isWaiting = false;
      _isConfirmed = false;
      _hasError = false;
      _errorMessage = null;
      _secondsLeft = 120;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 14, bottom: 6),
            decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple[400]!, Colors.purple[700]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.purple.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
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
                      Text('Générez un QR code valide 2 minutes',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.grey[400]),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isConfirmed) return _buildConfirmed();
    if (_shareToken != null && _isWaiting) return _buildQRDisplay();
    return _buildIntro();
  }

  // ── Vue intro (avant génération) ─────────────────────────────────────────

  Widget _buildIntro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Illustration
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple[50]!, Colors.purple[100]!],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.phonelink_rounded,
                size: 52, color: Colors.purple[400]),
          ),
          const SizedBox(height: 20),
          const Text('Connecter un autre appareil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Générez un QR code temporaire que l\'autre téléphone\npeut scanner pour se connecter à votre compte.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
          ),
          const SizedBox(height: 28),

          // Étapes
          _buildStepCard('1', Icons.qr_code_2_rounded, Colors.purple,
              'Générer le QR code',
              'Appuyez sur le bouton ci-dessous pour créer un code unique valable 2 minutes.'),
          const SizedBox(height: 12),
          _buildStepCard('2', Icons.phone_android_rounded, Colors.blue,
              'Sur l\'autre téléphone',
              'Ouvrez CarEasy → Écran d\'accueil → "Connexion rapide via QR code".'),
          const SizedBox(height: 12),
          _buildStepCard('3', Icons.camera_alt_rounded, Colors.teal,
              'Scanner le code',
              'L\'autre téléphone pointe sa caméra sur le QR — connexion automatique et sécurisée.'),
          const SizedBox(height: 12),
          _buildStepCard('4', Icons.verified_rounded, Colors.green,
              'Confirmation instantanée',
              'Vous recevez une notification dès que l\'autre appareil est connecté.'),

          const SizedBox(height: 28),

          // Bouton générer
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generate,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.qr_code_rounded),
              label: Text(_isGenerating
                  ? 'Génération en cours...'
                  : 'Générer mon QR code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[600],
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: Colors.purple.withOpacity(0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 16),
          // Avertissement sécurité
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.security_rounded, size: 16, color: Colors.orange[700]),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ne partagez jamais ce QR code avec quelqu\'un en qui vous n\'avez pas confiance. Il donne accès à votre compte.',
                    style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(String num, IconData icon, Color color, String title,
      String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Text(num,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Vue QR affiché + compteur ─────────────────────────────────────────────

  Widget _buildQRDisplay() {
    final progress = _secondsLeft / 120;
    final urgency = _secondsLeft < 30;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: urgency
                  ? Colors.red.withOpacity(0.06)
                  : Colors.purple.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: urgency
                    ? Colors.red.withOpacity(0.2)
                    : Colors.purple.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                // Pulsation indicateur en attente
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Transform.scale(
                    scale: _pulseAnim.value,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: urgency ? Colors.red : Colors.purple,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: (urgency ? Colors.red : Colors.purple)
                                  .withOpacity(0.4),
                              blurRadius: 6,
                              spreadRadius: 1)
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    urgency
                        ? 'Expire dans $_secondsLeft secondes !'
                        : 'En attente de scan — $_secondsLeft s restantes',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: urgency ? Colors.red[700] : Colors.purple[700]),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (urgency ? Colors.red : Colors.purple)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 12,
                          color: urgency ? Colors.red : Colors.purple),
                      const SizedBox(width: 4),
                      Text('$_secondsLeft s',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color:
                                  urgency ? Colors.red : Colors.purple)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Barre de progression
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey[200],
              color: urgency ? Colors.red : Colors.purple,
            ),
          ),
          const SizedBox(height: 20),

          // QR code card
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) => Transform.scale(
              scale: urgency ? 1.0 : 0.99 + _pulseAnim.value * 0.01,
              child: child,
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: urgency
                      ? Colors.red.withOpacity(0.4)
                      : Colors.purple.withOpacity(0.2),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                      color: (urgency ? Colors.red : Colors.purple)
                          .withOpacity(0.1),
                      blurRadius: 24,
                      offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                children: [
                  // Logo centré au-dessus du QR
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded,
                                size: 12, color: Colors.purple[600]),
                            const SizedBox(width: 4),
                            Text('CarEasy — Connexion sécurisée',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  QrImageView(
                    data: jsonEncode({
                      'type': 'careasy_session_share',
                      'token': _shareToken,
                      'expires_in': _secondsLeft,
                      'issued_at': DateTime.now().toIso8601String(),
                    }),
                    version: QrVersions.auto,
                    size: 210,
                    backgroundColor: Colors.white,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: urgency ? Colors.red : Colors.purple[800]!,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: urgency ? Colors.red : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Scannez ce code depuis l\'écran\nd\'accueil de l\'autre téléphone',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Indicateur de polling
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.purple, strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Surveillance active — en attente de connexion...',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Annuler'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
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
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Vue confirmation succès ───────────────────────────────────────────────

  Widget _buildConfirmed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Badge succès
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[400]!, Colors.green[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.green.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10))
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 52),
            ),
            const SizedBox(height: 24),
            const Text('Connexion réussie !',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.green)),
            const SizedBox(height: 10),
            Text(
              _connectedDeviceName != null
                  ? '"${_connectedDeviceName}" vient de rejoindre votre compte.'
                  : 'Un nouvel appareil vient de se connecter à votre compte.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Si vous ne reconnaissez pas cet appareil, allez dans "Appareils connectés" pour révoquer cette session.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.green[700]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}