import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;

import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../utils/constants.dart';
import '../theme/app_theme.dart';
import 'edit_profile_screen.dart';
import 'welcome_screen.dart';
import 'home_screen.dart';
import 'messages_screen.dart';

import 'notifications_settings_screen.dart' as notifications;
import 'security_settings_screen.dart' as security;
import 'appearance_settings_screen.dart' as appearance;
import 'privacy_settings_screen.dart' as privacy;
import 'help_screen.dart' as help;
import 'about_screen.dart' as about;
import 'mes_entreprises_screen.dart' as entreprises;
import 'plans_abonnement_screen.dart' as plans;
import 'package:careasy_app_mobile/screens/mes_entreprises_screen.dart' as entreprises;
import 'package:careasy_app_mobile/screens/create_entreprise_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ⭐ Même options de stockage sécurisé que le reste de l'app
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );

  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int  _currentIndex = 4; // Profil sélectionné par défaut

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final s = await _storage.read(key: 'user_data');
      if (s != null && s.isNotEmpty) {
        setState(() { _userData = jsonDecode(s); _isLoading = false; });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Erreur loadUserData: $e');
      setState(() => _isLoading = false);
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size          = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;
    final isTablet      = size.width >= 600;

    // Données pour la bottom nav
    final userName  = _userData?['name'] ?? '';
    final userPhoto = _userData?['profile_photo_url'] ?? '';
    final hasEntreprise = _userData?['has_entreprise'] ?? false;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Paramètres',
            style: TextStyle(fontSize: isSmallScreen ? 18 : 20, fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed))
          : _buildContent(context, size, isSmallScreen, isTablet),

      // ⭐ Bottom navigation bar identique à home_screen
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5)),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(Icons.home, 'Accueil', 0),
                _navItem(Icons.message, 'Messages', 1),
                _navItem(Icons.calendar_today, 'Rendez-vous', 2),
                _navItem(
                  hasEntreprise ? Icons.business : Icons.add_business,
                  hasEntreprise ? 'Entreprise' : 'Créer',
                  3,
                ),
                _profileNavItem(userName, userPhoto, 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Navigation items (copie exacte de home_screen) ─────────────────────────
  Widget _navItem(IconData icon, String label, int index) {
    final sel = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);
          if (index == 0) {
            Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (_) => false);
          } else if (index == 1) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MessagesScreen()));
          } else if (index == 2) {
            _showComingSoon('Rendez-vous');
          } else if (index == 3) {
            _handleEntrepriseTap();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: sel ? AppConstants.primaryRed : Colors.grey, size: 22),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: sel ? AppConstants.primaryRed : Colors.grey,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal),
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _profileNavItem(String name, String photo, int index) {
    final sel = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () { setState(() => _currentIndex = index); /* déjà sur paramètres */ },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 11,
              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
              backgroundColor: Colors.grey[200],
              child: photo.isEmpty
                  ? Icon(Icons.person, size: 12, color: Colors.grey[600])
                  : null,
            ),
            const SizedBox(height: 2),
            Text('Profil',
                style: TextStyle(
                    fontSize: 10,
                    color: sel ? AppConstants.primaryRed : Colors.grey,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal),
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  void _handleEntrepriseTap() {
    final hasEnt = _userData?['has_entreprise'] ?? false;
    if (hasEnt) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const entreprises.MesEntreprisesScreen()),
      );
    } else {
      _showCreateEntrepriseDialog();
    }
  }
  void _showCreateEntrepriseDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Créer votre entreprise', 
          style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Vous n\'avez pas encore d\'entreprise. Voulez-vous en créer une ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Annuler')
          ),
          ElevatedButton(
            onPressed: () { 
              Navigator.pop(context); 
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateEntrepriseScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryRed, 
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
            ),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  // ─── CONTENU PRINCIPAL ───────────────────────────────────────────────────────
  Widget _buildContent(BuildContext context, Size size, bool isSmallScreen, bool isTablet) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      child: isTablet
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: _buildProfileSection(context, size, isSmallScreen)),
              const SizedBox(width: 20),
              Expanded(flex: 7, child: _buildSettingsList(context, isSmallScreen)),
            ])
          : SingleChildScrollView(
              child: Column(children: [
                _buildProfileSection(context, size, isSmallScreen),
                const SizedBox(height: 20),
                _buildSettingsList(context, isSmallScreen),
                const SizedBox(height: 20),
              ]),
            ),
    );
  }

  // ─── SECTION PROFIL ──────────────────────────────────────────────────────────
  Widget _buildProfileSection(BuildContext context, Size size, bool isSmallScreen) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // ── Avatar + bouton caméra ──
        Stack(children: [
          Hero(
            tag: 'profile-photo',
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(color: AppConstants.primaryRed, width: 3)),
              child: CircleAvatar(
                radius: isSmallScreen ? 40 : 50,
                backgroundColor: Colors.grey[200],
                backgroundImage: _userData?['profile_photo_url'] != null &&
                    _userData!['profile_photo_url'].toString().isNotEmpty
                    ? NetworkImage(_userData!['profile_photo_url'])
                    : null,
                child: _userData?['profile_photo_url'] == null ||
                    _userData!['profile_photo_url'].toString().isEmpty
                    ? Text(
                        _userData?['name'] != null && _userData!['name'].toString().isNotEmpty
                            ? _userData!['name'][0].toUpperCase() : 'U',
                        style: TextStyle(
                            fontSize: isSmallScreen ? 32 : 40,
                            fontWeight: FontWeight.bold, color: AppConstants.primaryRed))
                    : null,
              ),
            ),
          ),
          Positioned(
            bottom: 0, right: 0,
            child: GestureDetector(
              onTap: () => _showImagePickerOptions(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // ── Nom ──
        Text(_userData?['name'] ?? 'Utilisateur',
            style: TextStyle(fontSize: isSmallScreen ? 18 : 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        // ── Email ou téléphone ──
        Text(
          _userData?['email'] ?? _userData?['phone'] ?? 'Non renseigné',
          style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        // ── Téléphone si email affiché ──
        if (_userData?['phone'] != null && _userData!['phone'].toString().isNotEmpty)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.phone, size: isSmallScreen ? 12 : 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(_userData!['phone'],
                style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey[600])),
          ]),
        const SizedBox(height: 4),
        // ── Badge rôle ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
              color: AppConstants.primaryRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Text(
            _userData?['role'] == 'prestataire' ? 'Prestataire' : 'Client',
            style: const TextStyle(fontSize: 12, color: AppConstants.primaryRed, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        // ── Bouton modifier profil ──
        OutlinedButton.icon(
          onPressed: () => _navigateToEditProfile(context),
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('Modifier le profil'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppConstants.primaryRed,
            side: const BorderSide(color: AppConstants.primaryRed),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: Size(isSmallScreen ? 150 : 200, 40),
          ),
        ),
      ]),
    );
  }

  // ─── LISTE DES PARAMÈTRES ─────────────────────────────────────────────────────
  Widget _buildSettingsList(BuildContext context, bool isSmallScreen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // ── Compte ──
        _buildSectionHeader('Compte', Icons.account_circle),
        _buildSettingsItem(
          icon: Icons.person_outline, title: 'Informations personnelles',
          subtitle: 'Nom, email, téléphone',
          onTap: () => _navigateToEditProfile(context), isSmallScreen: isSmallScreen),
        _buildSettingsItem(
          icon: Icons.business, title: 'Mes entreprises', subtitle: 'Gérer vos entreprises',
          onTap: () => _navigateToMesEntreprises(context), isSmallScreen: isSmallScreen),
        _buildSettingsItem(
          icon: Icons.subscriptions_outlined, title: 'Plans & Abonnements', subtitle: 'Gérer votre abonnement',
          onTap: () => _navigateToPlansAbonnement(context), isSmallScreen: isSmallScreen),
        _buildDivider(),

        // ── Préférences ──
        _buildSectionHeader('Préférences', Icons.settings),
        _buildSettingsItem(
          icon: Icons.notifications_none, title: 'Notifications', subtitle: 'Gérer vos alertes',
          onTap: () => _navigateToNotificationsSettings(context), isSmallScreen: isSmallScreen),
        _buildSettingsItem(
          icon: Icons.palette_outlined, title: 'Apparence', subtitle: 'Thème, langue',
          onTap: () => _navigateToAppearanceSettings(context), isSmallScreen: isSmallScreen,
          trailing: _buildThemeIndicator()),
        _buildSettingsItem(
          icon: Icons.lock_outline, title: 'Confidentialité & sécurité', subtitle: 'Mot de passe, données',
          onTap: () => _navigateToSecuritySettings(context), isSmallScreen: isSmallScreen),
        _buildDivider(),

        // ── Support ──
        _buildSectionHeader('Support', Icons.help_outline),
        _buildSettingsItem(
          icon: Icons.help_outline, title: 'Aide & support', subtitle: 'FAQ, contact',
          onTap: () => _navigateToHelp(context), isSmallScreen: isSmallScreen),
        _buildSettingsItem(
          icon: Icons.info_outline, title: 'À propos', subtitle: 'Version 1.0.0',
          onTap: () => _navigateToAbout(context), isSmallScreen: isSmallScreen),
        _buildDivider(),

        // ── Bouton déconnexion ──
        Container(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Déconnexion'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── DÉCONNEXION COMPLÈTE ─────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // Afficher un indicateur de chargement
    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed)),
    );

    try {
      // 1. Révoquer le token sur le serveur
      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('${AppConstants.apiBaseUrl}/logout'),
            headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }

      // 2. Nettoyer tout le storage local
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'user_data');
      await _storage.delete(key: 'fcm_token_pending');
      await _storage.delete(key: 'remember_me');
      await _storage.delete(key: 'login_time');

      // 3. Réinitialiser les providers
      if (mounted) {
        try { context.read<MessageProvider>().stopOnlineTimer(); } catch (_) {}
        try { context.read<AuthProvider>().clearError(); } catch (_) {}
      }
    } catch (_) {}

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    }
  }

  // ─── PHOTO DE PROFIL ──────────────────────────────────────────────────────────
  void _showImagePickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Photo de profil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _buildImagePickerOption(icon: Icons.photo_library, label: 'Galerie',
                onTap: () => _pickImage(ImageSource.gallery, ctx)),
            _buildImagePickerOption(icon: Icons.camera_alt, label: 'Appareil photo',
                onTap: () => _pickImage(ImageSource.camera, ctx)),
            _buildImagePickerOption(icon: Icons.delete, label: 'Supprimer',
                onTap: () => _deleteProfilePhoto(ctx), color: Colors.red),
          ]),
          const SizedBox(height: 20),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        ]),
      ),
    );
  }

  Widget _buildImagePickerOption({
    required IconData icon, required String label,
    required VoidCallback onTap, Color color = AppConstants.primaryRed,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Future<void> _pickImage(ImageSource source, BuildContext ctx) async {
    Navigator.pop(ctx);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
      if (file != null) await _uploadProfilePhoto(File(file.path));
    } catch (e) { _showError('Erreur lors de la sélection'); }
  }

  Future<void> _uploadProfilePhoto(File imageFile) async {
    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed)));
    try {
      final token = await _storage.read(key: 'auth_token');
      var req = http.MultipartRequest('POST',
          Uri.parse('${AppConstants.apiBaseUrl}/user/profile-photo'));
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath(
          'profile_photo', imageFile.path,
          filename: path.basename(imageFile.path),
          contentType: MediaType('image', 'jpeg')));
      var res = await req.send();
      var body = jsonDecode(await res.stream.bytesToString());
      if (context.mounted) Navigator.pop(context);
      if (res.statusCode == 200 && body['profile_photo_url'] != null) {
        setState(() { _userData!['profile_photo_url'] = body['profile_photo_url']; });
        await _storage.write(key: 'user_data', value: jsonEncode(_userData));
        _showSuccess('Photo de profil mise à jour');
      } else {
        _showError(body['message'] ?? 'Erreur lors du téléchargement');
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showError('Erreur de connexion');
    }
  }

  Future<void> _deleteProfilePhoto(BuildContext ctx) async {
    Navigator.pop(ctx);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer la photo'),
        content: const Text('Voulez-vous vraiment supprimer votre photo de profil ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed)));
    try {
      final token = await _storage.read(key: 'auth_token');
      final resp = await http.delete(
        Uri.parse('${AppConstants.apiBaseUrl}/user/profile-photo'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (context.mounted) Navigator.pop(context);
      if (resp.statusCode == 200) {
        setState(() { _userData!['profile_photo_url'] = null; });
        await _storage.write(key: 'user_data', value: jsonEncode(_userData));
        _showSuccess('Photo de profil supprimée');
      } else {
        _showError('Erreur lors de la suppression');
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showError('Erreur de connexion');
    }
  }

  // ─── NAVIGATION ────────────────────────────────────────────────────────────────
  void _navigateToEditProfile(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(userData: _userData)))
        .then((_) => _loadUserData()); // ⭐ Recharger après modification
  }

  void _navigateToMesEntreprises(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const entreprises.MesEntreprisesScreen()));

  void _navigateToPlansAbonnement(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const plans.PlansAbonnementScreen()));

  void _navigateToNotificationsSettings(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const notifications.NotificationsSettingsScreen()));

  void _navigateToAppearanceSettings(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const appearance.AppearanceSettingsScreen()));

  void _navigateToSecuritySettings(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const security.SecuritySettingsScreen()));

  void _navigateToHelp(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const help.HelpScreen()));

  void _navigateToAbout(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const about.AboutScreen()));

  // ─── WIDGETS UTILITAIRES ───────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(children: [
        Icon(icon, size: 18, color: AppConstants.primaryRed),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppConstants.primaryRed)),
      ]),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon, required String title, String? subtitle,
    required VoidCallback onTap, required bool isSmallScreen, Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 12 : 16, vertical: isSmallScreen ? 12 : 16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: isSmallScreen ? 20 : 22, color: AppConstants.primaryRed),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: isSmallScreen ? 14 : 16, fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: isSmallScreen ? 11 : 13, color: Colors.grey[600])),
              ],
            ])),
            if (trailing != null) trailing,
            Icon(Icons.arrow_forward_ios, size: isSmallScreen ? 14 : 16, color: Colors.grey[400]),
          ]),
        ),
      ),
    );
  }

  Widget _buildThemeIndicator() {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.light_mode, size: 12, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text('Clair', style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildDivider() =>
      Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey[200]);

  void _showInfoDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Paramètres'),
      content: const Text('Gérez vos préférences, vos informations personnelles et les paramètres de votre compte.'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature Bientôt disponible'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}