// lib/screens/security_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../utils/constants.dart';
import '../providers/auth_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  SecuritySettingsScreen — Confidentialité & Sécurité
//  Boutons fonctionnels :
//    ✅ Changer le mot de passe
//    ✅ Visibilité du profil    (public / amis / privé)
//    ✅ Statut en ligne         (toggle persisté côté serveur)
//    ✅ Utilisateurs bloqués    (liste + déblocage)
//    ✅ Appareils connectés     (liste sessions Sanctum + révocation)
//    ✅ Historique des connexions
//    ✅ Authentification à deux facteurs (UI d'activation)
//    ✅ Déconnexion de tous les appareils
//    ✅ Suppression du compte
// ══════════════════════════════════════════════════════════════════════════════

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  // ── Storage & HTTP ─────────────────────────────────────────────────────────
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  // ── État global ────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _isLoadingSettings = true;

  // ── Mot de passe ───────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _isChangingPassword = false;

  // ── Paramètres de confidentialité ──────────────────────────────────────────
  String _profileVisibility = 'public'; // public | friends_only | private
  bool _showOnlineStatus = true;

  // ── Sessions (appareils connectés) ─────────────────────────────────────────
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoadingSessions = false;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HELPERS — HTTP
  // ══════════════════════════════════════════════════════════════════════════

  Future<String?> _getToken() => _storage.read(key: 'auth_token');

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ══════════════════════════════════════════════════════════════════════════
  //  CHARGEMENT DES PARAMÈTRES PRIVACY
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _loadPrivacySettings() async {
    setState(() => _isLoadingSettings = true);
    try {
      final token = await _getToken();
      if (token == null) return;

      final response = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/user/settings'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final settings = data['settings'] ?? {};
        final privacy = settings['privacy'] ?? {};
        setState(() {
          _profileVisibility = privacy['profile_visibility'] ?? 'public';
          _showOnlineStatus = privacy['show_online_status'] ?? true;
        });
      }
    } catch (_) {
      // On garde les valeurs par défaut si pas de réseau
    } finally {
      if (mounted) setState(() => _isLoadingSettings = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════

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
          'Confidentialité & sécurité',
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
      body: _isLoadingSettings
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppConstants.primaryRed,
              onRefresh: _loadPrivacySettings,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                child: Column(
                  children: [
                    _buildChangePasswordSection(isSmallScreen),
                    const SizedBox(height: 16),
                    _buildPrivacySection(isSmallScreen),
                    const SizedBox(height: 16),
                    _buildSecuritySection(isSmallScreen),
                    const SizedBox(height: 16),
                    _buildDangerZone(isSmallScreen),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SECTION 1 — CHANGER LE MOT DE PASSE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChangePasswordSection(bool isSmallScreen) {
    return _buildCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Changer le mot de passe', Icons.lock_reset_outlined),
            const SizedBox(height: 20),

            _buildPasswordField(
              controller: _currentPasswordController,
              label: 'Mot de passe actuel',
              obscureText: !_showCurrentPassword,
              onToggle: () => setState(() => _showCurrentPassword = !_showCurrentPassword),
              isSmallScreen: isSmallScreen,
              validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 14),

            _buildPasswordField(
              controller: _newPasswordController,
              label: 'Nouveau mot de passe',
              obscureText: !_showNewPassword,
              onToggle: () => setState(() => _showNewPassword = !_showNewPassword),
              isSmallScreen: isSmallScreen,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requis';
                if (v.length < 8) return 'Minimum 8 caractères';
                return null;
              },
            ),
            const SizedBox(height: 14),

            _buildPasswordField(
              controller: _confirmPasswordController,
              label: 'Confirmer le nouveau mot de passe',
              obscureText: !_showConfirmPassword,
              onToggle: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
              isSmallScreen: isSmallScreen,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requis';
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isChangingPassword
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Mettre à jour le mot de passe',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
    required bool isSmallScreen,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isSmallScreen ? 12 : 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          style: TextStyle(fontSize: isSmallScreen ? 14 : 15),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.lock_outline,
                size: isSmallScreen ? 18 : 20, color: AppConstants.primaryRed),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                size: isSmallScreen ? 16 : 18,
                color: Colors.grey[500],
              ),
              onPressed: onToggle,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppConstants.primaryRed),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isSmallScreen ? 12 : 14,
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SECTION 2 — CONFIDENTIALITÉ
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPrivacySection(bool isSmallScreen) {
    final visibilityLabel = {
      'public': 'Public',
      'friends_only': 'Amis',
      'private': 'Privé',
    }[_profileVisibility] ??
        'Public';

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Confidentialité', Icons.shield_outlined),
          const SizedBox(height: 8),

          // Visibilité du profil
          _buildPrivacyOptionRow(
            icon: Icons.visibility_outlined,
            title: 'Visibilité du profil',
            subtitle: 'Qui peut voir votre profil',
            value: visibilityLabel,
            onTap: () => _showProfileVisibilityDialog(isSmallScreen),
            isSmallScreen: isSmallScreen,
          ),
          const Divider(height: 1),

          // Statut en ligne
          _buildPrivacySwitchRow(
            icon: Icons.circle_outlined,
            title: 'Statut en ligne',
            subtitle: 'Afficher quand vous êtes en ligne',
            value: _showOnlineStatus,
            onChanged: _updateOnlineStatusVisibility,
            isSmallScreen: isSmallScreen,
          ),
          const Divider(height: 1),

          // Utilisateurs bloqués
          _buildPrivacyOptionRow(
            icon: Icons.block_outlined,
            title: 'Utilisateurs bloqués',
            subtitle: 'Gérer les utilisateurs bloqués',
            value: '',
            onTap: () => _showBlockedUsersSheet(isSmallScreen),
            isSmallScreen: isSmallScreen,
            showBadge: false,
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyOptionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required VoidCallback onTap,
    required bool isSmallScreen,
    bool showBadge = true,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 4 : 8,
          vertical: isSmallScreen ? 12 : 14,
        ),
        child: Row(
          children: [
            _buildOptionIcon(icon, isSmallScreen),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 15,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: isSmallScreen ? 11 : 12,
                          color: Colors.grey[500])),
                ],
              ),
            ),
            if (showBadge && value.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(value,
                    style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 11,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_ios,
                size: isSmallScreen ? 12 : 13, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacySwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isSmallScreen,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 4 : 8,
        vertical: isSmallScreen ? 8 : 10,
      ),
      child: Row(
        children: [
          _buildOptionIcon(icon, isSmallScreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 15,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: isSmallScreen ? 11 : 12,
                        color: Colors.grey[500])),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: AppConstants.primaryRed,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SECTION 3 — SÉCURITÉ
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSecuritySection(bool isSmallScreen) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Sécurité', Icons.security_outlined),
          const SizedBox(height: 8),

          _buildSecurityOption(
            icon: Icons.devices_outlined,
            title: 'Appareils connectés',
            subtitle: 'Gérer les appareils connectés à votre compte',
            onTap: () => _showConnectedDevicesSheet(isSmallScreen),
            isSmallScreen: isSmallScreen,
          ),
          const Divider(height: 1),

          _buildSecurityOption(
            icon: Icons.history_outlined,
            title: 'Historique des connexions',
            subtitle: 'Voir les dernières connexions',
            onTap: () => _showLoginHistorySheet(isSmallScreen),
            isSmallScreen: isSmallScreen,
          ),
          const Divider(height: 1),

          _buildSecurityOption(
            icon: Icons.phonelink_lock_outlined,
            title: 'Authentification à deux facteurs',
            subtitle: 'Renforcer la sécurité de votre compte',
            onTap: () => _show2FASheet(isSmallScreen),
            isSmallScreen: isSmallScreen,
            badge: '2FA',
            badgeColor: Colors.orange,
          ),
          const Divider(height: 1),

          _buildSecurityOption(
            icon: Icons.logout,
            title: 'Déconnecter tous les appareils',
            subtitle: 'Révoquer toutes les sessions actives',
            onTap: () => _confirmLogoutAll(isSmallScreen),
            isSmallScreen: isSmallScreen,
            iconColor: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isSmallScreen,
    String? badge,
    Color? badgeColor,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 4 : 8,
          vertical: isSmallScreen ? 12 : 14,
        ),
        child: Row(
          children: [
            _buildOptionIcon(icon, isSmallScreen, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 15,
                          fontWeight: FontWeight.w600,
                          color: iconColor)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: isSmallScreen ? 11 : 12,
                          color: Colors.grey[500])),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? AppConstants.primaryRed).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 10,
                        color: badgeColor ?? AppConstants.primaryRed,
                        fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_ios,
                size: isSmallScreen ? 12 : 13, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SECTION 4 — ZONE DANGEREUSE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDangerZone(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[400], size: 20),
            const SizedBox(width: 8),
            Text('Zone dangereuse',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700])),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmDeleteAccount(isSmallScreen),
              icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
              label: const Text('Supprimer mon compte',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Cette action est irréversible. Toutes vos données seront supprimées.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WIDGETS COMMUNS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 18, color: AppConstants.primaryRed),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildOptionIcon(IconData icon, bool isSmallScreen, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (color ?? AppConstants.primaryRed).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon,
          size: isSmallScreen ? 18 : 20, color: color ?? AppConstants.primaryRed),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — CHANGER LE MOT DE PASSE
  // ══════════════════════════════════════════════════════════════════════════

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
        _clearPasswordFields();
        _showSnack('Mot de passe mis à jour avec succès', Colors.green);
      } else {
        String msg = 'Erreur lors du changement de mot de passe';
        if (data['errors']?['current_password'] != null) {
          msg = data['errors']['current_password'][0];
        } else if (data['message'] != null) {
          msg = data['message'];
        }
        _showSnack(msg, Colors.red);
      }
    } catch (_) {
      _showSnack('Erreur de connexion', Colors.red);
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  void _clearPasswordFields() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — VISIBILITÉ DU PROFIL
  // ══════════════════════════════════════════════════════════════════════════

  void _showProfileVisibilityDialog(bool isSmallScreen) {
    final options = [
      {'value': 'public', 'label': 'Public', 'subtitle': 'Tout le monde peut voir votre profil', 'icon': Icons.public},
      {'value': 'friends_only', 'label': 'Amis', 'subtitle': 'Seulement vos contacts', 'icon': Icons.people_outline},
      {'value': 'private', 'label': 'Privé', 'subtitle': 'Personne ne peut voir votre profil', 'icon': Icons.lock_outline},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              const SizedBox(height: 16),
              const Text('Visibilité du profil',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Choisissez qui peut voir votre profil',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              const SizedBox(height: 16),
              ...options.map((opt) {
                final selected = _profileVisibility == opt['value'];
                return ListTile(
                  leading: Icon(opt['icon'] as IconData,
                      color: selected ? AppConstants.primaryRed : Colors.grey[600]),
                  title: Text(opt['label'] as String,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected ? AppConstants.primaryRed : null)),
                  subtitle: Text(opt['subtitle'] as String,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  trailing: selected
                      ? const Icon(Icons.check_circle, color: AppConstants.primaryRed)
                      : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  tileColor: selected
                      ? AppConstants.primaryRed.withOpacity(0.05)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _updateProfileVisibility(opt['value'] as String);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateProfileVisibility(String visibility) async {
    final previous = _profileVisibility;
    setState(() => _profileVisibility = visibility);

    try {
      final token = await _getToken();
      final response = await http
          .put(
            Uri.parse('${AppConstants.apiBaseUrl}/user/settings'),
            headers: _headers(token!),
            body: jsonEncode({
              'settings': {
                'privacy': {
                  'profile_visibility': visibility,
                  'show_online_status': _showOnlineStatus,
                }
              }
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSnack('Visibilité mise à jour', Colors.green);
      } else {
        setState(() => _profileVisibility = previous);
        _showSnack('Erreur lors de la mise à jour', Colors.red);
      }
    } catch (_) {
      setState(() => _profileVisibility = previous);
      _showSnack('Erreur de connexion', Colors.red);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — STATUT EN LIGNE
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _updateOnlineStatusVisibility(bool value) async {
    final previous = _showOnlineStatus;
    setState(() => _showOnlineStatus = value);

    try {
      final token = await _getToken();
      final response = await http
          .put(
            Uri.parse('${AppConstants.apiBaseUrl}/user/settings'),
            headers: _headers(token!),
            body: jsonEncode({
              'settings': {
                'privacy': {
                  'profile_visibility': _profileVisibility,
                  'show_online_status': value,
                }
              }
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSnack(
          value ? 'Statut en ligne activé' : 'Statut en ligne masqué',
          Colors.green,
        );
      } else {
        setState(() => _showOnlineStatus = previous);
        _showSnack('Erreur lors de la mise à jour', Colors.red);
      }
    } catch (_) {
      setState(() => _showOnlineStatus = previous);
      _showSnack('Erreur de connexion', Colors.red);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — UTILISATEURS BLOQUÉS
  // ══════════════════════════════════════════════════════════════════════════

  void _showBlockedUsersSheet(bool isSmallScreen) {
    // NOTE : Cette feuille charge les utilisateurs bloqués depuis l'API.
    // Si votre backend n'a pas encore de route /user/blocked, elle affichera
    // un message "aucun utilisateur bloqué" — à connecter côté serveur.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BlockedUsersSheet(storage: _storage),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — APPAREILS CONNECTÉS
  // ══════════════════════════════════════════════════════════════════════════

  void _showConnectedDevicesSheet(bool isSmallScreen) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ConnectedDevicesSheet(storage: _storage),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — HISTORIQUE DES CONNEXIONS
  // ══════════════════════════════════════════════════════════════════════════

  void _showLoginHistorySheet(bool isSmallScreen) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LoginHistorySheet(storage: _storage),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — 2FA
  // ══════════════════════════════════════════════════════════════════════════

  void _show2FASheet(bool isSmallScreen) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TwoFactorSheet(storage: _storage),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — DÉCONNECTER TOUS LES APPAREILS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _confirmLogoutAll(bool isSmallScreen) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Déconnecter tous les appareils'),
        content: const Text(
          'Vous allez être déconnecté de tous vos appareils. '
          'Vous devrez vous reconnecter sur cet appareil.',
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
            child: const Text('Déconnecter tout'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      // Révoque TOUS les tokens Sanctum de l'utilisateur
      final response = await http
          .post(
            Uri.parse('${AppConstants.apiBaseUrl}/user/logout-all'),
            headers: _headers(token!),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 204) {
        _showSnack('Tous les appareils ont été déconnectés', Colors.green);
        // Déconnecter aussi l'appareil courant
        if (mounted) {
          await context.read<AuthProvider>().logout();
        }
      } else {
        _showSnack('Erreur lors de la déconnexion', Colors.red);
      }
    } catch (_) {
      _showSnack('Erreur de connexion', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ACTION — SUPPRIMER LE COMPTE
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _confirmDeleteAccount(bool isSmallScreen) async {
    final passwordController = TextEditingController();
    bool obscure = true;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[600]),
            const SizedBox(width: 8),
            const Text('Supprimer le compte'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cette action est IRRÉVERSIBLE. Toutes vos données, '
                'rendez-vous et messages seront définitivement supprimés.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              const Text('Confirmez votre mot de passe :',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: passwordController,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'Votre mot de passe',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                        size: 18),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
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
    if (passwordController.text.isEmpty) {
      _showSnack('Veuillez saisir votre mot de passe', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      final response = await http
          .delete(
            Uri.parse('${AppConstants.apiBaseUrl}/user/account'),
            headers: _headers(token!),
            body: jsonEncode({'password': passwordController.text}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (mounted) await context.read<AuthProvider>().logout();
      } else {
        final data = jsonDecode(response.body);
        _showSnack(data['message'] ?? 'Erreur lors de la suppression', Colors.red);
      }
    } catch (_) {
      _showSnack('Erreur de connexion', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HELPERS UI
  // ══════════════════════════════════════════════════════════════════════════

  Widget _sheetHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2)),
        ),
      );

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SOUS-WIDGET — Utilisateurs bloqués
// ════════════════════════════════════════════════════════════════════════════

class _BlockedUsersSheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _BlockedUsersSheet({required this.storage});

  @override
  State<_BlockedUsersSheet> createState() => _BlockedUsersSheetState();
}

class _BlockedUsersSheetState extends State<_BlockedUsersSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _blockedUsers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/user/blocked'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _blockedUsers = List<Map<String, dynamic>>.from(
              data['blocked_users'] ?? data ?? []);
        });
      }
    } catch (_) {
      // Pas de connexion — on affiche la liste vide
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unblock(dynamic userId, String userName) async {
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http
          .delete(
            Uri.parse('${AppConstants.apiBaseUrl}/user/blocked/$userId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() => _blockedUsers.removeWhere((u) => u['id'] == userId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$userName a été débloqué'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.block_outlined, color: AppConstants.primaryRed),
              const SizedBox(width: 8),
              const Text('Utilisateurs bloqués',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.refresh),
                  color: AppConstants.primaryRed,
                  onPressed: _load),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppConstants.primaryRed))
                  : _blockedUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 56, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('Aucun utilisateur bloqué',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 15)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: ctrl,
                          itemCount: _blockedUsers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final u = _blockedUsers[i];
                            final name = u['name'] ?? 'Utilisateur';
                            final photo = u['profile_photo_url'] ?? u['photo_url'];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.grey[200],
                                backgroundImage:
                                    photo != null ? NetworkImage(photo) : null,
                                child: photo == null
                                    ? Text(name[0].toUpperCase(),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold))
                                    : null,
                              ),
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(u['email'] ?? '',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[500])),
                              trailing: TextButton(
                                onPressed: () => _unblock(u['id'], name),
                                style: TextButton.styleFrom(
                                    foregroundColor: AppConstants.primaryRed),
                                child: const Text('Débloquer'),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SOUS-WIDGET — Appareils connectés
// ════════════════════════════════════════════════════════════════════════════

class _ConnectedDevicesSheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _ConnectedDevicesSheet({required this.storage});

  @override
  State<_ConnectedDevicesSheet> createState() => _ConnectedDevicesSheetState();
}

class _ConnectedDevicesSheetState extends State<_ConnectedDevicesSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/user/sessions'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _sessions =
              List<Map<String, dynamic>>.from(data['sessions'] ?? data ?? []);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _revokeSession(dynamic sessionId) async {
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http
          .delete(
            Uri.parse('${AppConstants.apiBaseUrl}/user/sessions/$sessionId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() => _sessions.removeWhere((s) => s['id'] == sessionId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Session révoquée'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {}
  }

  IconData _deviceIcon(String? device) {
    final d = (device ?? '').toLowerCase();
    if (d.contains('mobile') || d.contains('android') || d.contains('ios') || d.contains('iphone')) {
      return Icons.smartphone_outlined;
    }
    if (d.contains('tablet') || d.contains('ipad')) return Icons.tablet_outlined;
    return Icons.computer_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.devices_outlined, color: AppConstants.primaryRed),
              const SizedBox(width: 8),
              const Text('Appareils connectés',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.refresh),
                  color: AppConstants.primaryRed,
                  onPressed: _load),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed))
                  : _sessions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.devices_other, size: 56, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('Aucune session trouvée',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: ctrl,
                          itemCount: _sessions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final s = _sessions[i];
                            final isCurrent = s['is_current'] == true;
                            final device = s['device_type'] ?? s['device'] ?? 'Appareil inconnu';
                            final ip = s['ip_address'] ?? '';
                            final lastUsed = s['last_used_at'] ?? s['created_at'] ?? '';
                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? AppConstants.primaryRed.withOpacity(0.1)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_deviceIcon(device),
                                    color: isCurrent
                                        ? AppConstants.primaryRed
                                        : Colors.grey[600]),
                              ),
                              title: Row(children: [
                                Expanded(
                                    child: Text(device,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14))),
                                if (isCurrent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Cet appareil',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold)),
                                  ),
                              ]),
                              subtitle: Text('IP: $ip\nDernière activité: $lastUsed',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500])),
                              isThreeLine: true,
                              trailing: !isCurrent
                                  ? TextButton(
                                      onPressed: () => _revokeSession(s['id']),
                                      style: TextButton.styleFrom(
                                          foregroundColor: Colors.red),
                                      child: const Text('Révoquer'),
                                    )
                                  : null,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SOUS-WIDGET — Historique des connexions
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/user/login-history'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _history = List<Map<String, dynamic>>.from(
              data['history'] ?? data ?? []);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.history_outlined, color: AppConstants.primaryRed),
              const SizedBox(width: 8),
              const Text('Historique des connexions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.refresh),
                  color: AppConstants.primaryRed,
                  onPressed: _load),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed))
                  : _history.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 56, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('Aucun historique disponible',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                              const SizedBox(height: 8),
                              Text(
                                  'L\'historique sera disponible une fois la\nfonctionnalité activée côté serveur.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: ctrl,
                          itemCount: _history.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final h = _history[i];
                            final success = h['success'] == true;
                            final ip = h['ip_address'] ?? '';
                            final date = h['created_at'] ?? h['logged_at'] ?? '';
                            final location = h['location'] ?? '';
                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: success
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                    success ? Icons.check_circle_outline : Icons.error_outline,
                                    color: success ? Colors.green : Colors.red,
                                    size: 20),
                              ),
                              title: Text(success ? 'Connexion réussie' : 'Tentative échouée',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: success ? Colors.black87 : Colors.red[700])),
                              subtitle: Text(
                                  'IP: $ip${location.isNotEmpty ? '\n$location' : ''}\n$date',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                              isThreeLine: true,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SOUS-WIDGET — 2FA (Authentification à deux facteurs)
// ════════════════════════════════════════════════════════════════════════════

class _TwoFactorSheet extends StatefulWidget {
  final FlutterSecureStorage storage;
  const _TwoFactorSheet({required this.storage});

  @override
  State<_TwoFactorSheet> createState() => _TwoFactorSheetState();
}

class _TwoFactorSheetState extends State<_TwoFactorSheet> {
  bool _isLoading = true;
  bool _isEnabled = false;
  bool _isToggeling = false;
  String? _qrCodeUrl;
  String? _secret;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load2FAStatus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load2FAStatus() async {
    setState(() => _isLoading = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final response = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/user/2fa/status'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isEnabled = data['enabled'] == true;
          _qrCodeUrl = data['qr_code_url'];
          _secret = data['secret'];
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggle2FA() async {
    setState(() => _isToggeling = true);
    try {
      final token = await widget.storage.read(key: 'auth_token');
      final endpoint = _isEnabled
          ? '${AppConstants.apiBaseUrl}/user/2fa/disable'
          : '${AppConstants.apiBaseUrl}/user/2fa/enable';

      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: _isEnabled ? null : jsonEncode({'code': _codeController.text}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isEnabled = !_isEnabled;
          _qrCodeUrl = data['qr_code_url'];
          _secret = data['secret'];
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEnabled ? '2FA activé avec succès' : '2FA désactivé'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message'] ?? 'Erreur lors de la modification'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isToggeling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.phonelink_lock_outlined, color: AppConstants.primaryRed),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Authentification à deux facteurs',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed))
            else ...[
              // Statut actuel
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isEnabled
                      ? Colors.green.withOpacity(0.08)
                      : Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _isEnabled
                          ? Colors.green.withOpacity(0.3)
                          : Colors.orange.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(_isEnabled ? Icons.verified_user : Icons.warning_amber_outlined,
                      color: _isEnabled ? Colors.green : Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _isEnabled ? '2FA activée' : '2FA désactivée',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isEnabled ? Colors.green[700] : Colors.orange[700])),
                        Text(
                            _isEnabled
                                ? 'Votre compte est protégé par la 2FA.'
                                : 'Activez la 2FA pour renforcer la sécurité.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // Explication
              const Text('Comment ça marche ?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              _step('1', 'Installez une application d\'authentification (Google Authenticator, Authy…)'),
              _step('2', 'Scannez le QR code ou saisissez le code secret dans l\'application.'),
              _step('3', 'Lors de chaque connexion, saisissez le code à 6 chiffres généré.'),
              const SizedBox(height: 20),

              // QR code / secret si en cours d'activation
              if (!_isEnabled && _qrCodeUrl != null) ...[
                const Text('Scannez ce QR code :',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Center(
                  child: Image.network(_qrCodeUrl!,
                      width: 180, height: 180,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.qr_code_2, size: 120, color: Colors.grey)),
                ),
                const SizedBox(height: 12),
                if (_secret != null)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _secret!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copié'), behavior: SnackBarBehavior.floating),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        Expanded(
                          child: Text(_secret!,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 2)),
                        ),
                        const Icon(Icons.copy, size: 18, color: AppConstants.primaryRed),
                      ]),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'Code de vérification (6 chiffres)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppConstants.primaryRed)),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Bouton activer / désactiver
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isToggeling ? null : _toggle2FA,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isEnabled ? Colors.red[700] : AppConstants.primaryRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isToggeling
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(_isEnabled ? 'Désactiver la 2FA' : 'Activer la 2FA',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              color: AppConstants.primaryRed, shape: BoxShape.circle),
          child: Text(num,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
      ]),
    );
  }
}