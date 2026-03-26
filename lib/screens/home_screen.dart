import '../services/notification_service.dart';
import '../main.dart' show setupNotificationNavigation;
import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:careasy_app_mobile/screens/service_detail_screen.dart';
import 'package:careasy_app_mobile/screens/messages_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import 'package:careasy_app_mobile/screens/all_services_screen.dart';
import 'package:careasy_app_mobile/screens/all_entreprises_screen.dart';
import 'package:careasy_app_mobile/screens/entreprise_detail_screen.dart';
import '../models/user_model.dart';
import './settings_screen.dart';
import '../providers/rendez_vous_provider.dart';
import '../providers/notification_provider.dart';
import 'package:careasy_app_mobile/screens/rendez_vous/rendez_vous_list_screen.dart';
import 'package:careasy_app_mobile/screens/create_entreprise_screen.dart';
import 'package:careasy_app_mobile/screens/mes_entreprises_screen.dart';
import 'package:careasy_app_mobile/screens/plans_abonnement_screen.dart';
import '../widgets/notification_bell.dart';
import 'welcome_screen.dart';
import 'chat_screen.dart';
import 'rendez_vous/create_rendez_vous_screen.dart'; // ← AJOUT pour la redirection

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int _currentIndex = 0;

  List<dynamic> _services = [];
  List<dynamic> _entreprises = [];
  List<dynamic> _domaines = [];
  String? _selectedDomaine;

  bool _isLoadingServices = true;
  bool _isLoadingEntreprises = true;
  bool _isLoadingDomaines = true;

  final ScrollController _serviceScrollController = ScrollController();
  final Map<int, Timer> _imageTimers = {};
  final Map<int, int> _currentImageIndex = {};

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<dynamic> _searchResults = [];
  Timer? _debounceTimer;



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuth();
      context.read<NotificationProvider>().startPolling();
      setupNotificationNavigation(context);
      NotificationService().refreshTokenAfterLogin();
    });
    _loadUserData();
    _fetchData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _serviceScrollController.dispose();
    _imageTimers.forEach((_, timer) => timer.cancel());
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(_searchController.text);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) { setState(() => _searchResults = []); return; }
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/search?q=$query&type=all'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (response.statusCode == 200) setState(() => _searchResults = jsonDecode(response.body));
    } catch (e) { debugPrint('Erreur recherche: $e'); }
  }

  Future<void> _loadUserData() async {
    try {
      final userDataString = await _storage.read(key: 'user_data');
      if (userDataString != null) setState(() => _userData = jsonDecode(userDataString));
    } catch (e) { debugPrint('Erreur chargement user data: $e'); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _fetchData() async {
    await Future.wait([_fetchServices(), _fetchEntreprises(), _fetchDomaines()]);
  }

  Future<void> _fetchServices() async {
    setState(() => _isLoadingServices = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/services'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() { _services = data; _isLoadingServices = false; });
        for (int i = 0; i < data.length; i++) { _startImageCarousel(i); }
      } else { setState(() => _isLoadingServices = false); }
    } catch (e) { debugPrint('Erreur chargement services: $e'); setState(() => _isLoadingServices = false); }
  }

  Future<void> _fetchEntreprises() async {
    setState(() => _isLoadingEntreprises = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/entreprises'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        setState(() { _entreprises = jsonDecode(response.body); _isLoadingEntreprises = false; });
      } else { setState(() => _isLoadingEntreprises = false); }
    } catch (e) { debugPrint('Erreur chargement entreprises: $e'); setState(() => _isLoadingEntreprises = false); }
  }

  Future<void> _fetchDomaines() async {
    setState(() => _isLoadingDomaines = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/domaines'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() { _domaines = data; _domaines.insert(0, {'id': null, 'name': 'Tous'}); _isLoadingDomaines = false; });
      } else { setState(() => _isLoadingDomaines = false); }
    } catch (e) { debugPrint('Erreur chargement domaines: $e'); setState(() => _isLoadingDomaines = false); }
  }

  void _startImageCarousel(int serviceIndex) {
    if (serviceIndex >= _services.length) return;
    final service = _services[serviceIndex];
    final medias = service['medias'] is List ? service['medias'] : [];
    if (medias.length <= 1) return;
    _currentImageIndex[serviceIndex] = 0;
    _imageTimers[serviceIndex] = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && serviceIndex < _services.length) {
        setState(() {
          int current = _currentImageIndex[serviceIndex] ?? 0;
          _currentImageIndex[serviceIndex] = ((current + 1) % medias.length).toInt();
        });
      } else { timer.cancel(); }
    });
  }

  Future<void> _checkAuth() async {
    final token = await _storage.read(key: 'auth_token');
    if ((token == null || token.isEmpty) && mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
    }
  }

  Future<void> _logout() async {
    if (mounted) Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst || r.settings.name == null);
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        try { await http.post(Uri.parse('${AppConstants.apiBaseUrl}/logout'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 5)); } catch (_) {}
      }
    } catch (_) {}
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_data');
    await _storage.delete(key: 'fcm_token_pending');
    await _storage.delete(key: 'remember_me');
    await _storage.delete(key: 'login_time');
    if (mounted) {
      try { context.read<AuthProvider>().clearError(); } catch (_) {}
      try { context.read<MessageProvider>().stopOnlineTimer(); } catch (_) {}
      try { context.read<NotificationProvider>().stopPolling(); } catch (_) {}
    }
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
  }

  List<dynamic> get _filteredServices {
    if (_selectedDomaine == null || _selectedDomaine == 'Tous') return _services;
    return _services.where((s) => (s['domaine'] ?? {})['name'] == _selectedDomaine).toList();
  }

  String _formatPhoneNumber(String phone) {
    if (phone.isEmpty) return '';
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.startsWith('+')) return phone;
    if (cleaned.startsWith('229') && cleaned.length >= 11) return '+$cleaned';
    if (cleaned.startsWith('0') && cleaned.length == 10) return '+229${cleaned.substring(1)}';
    if (cleaned.length == 8) return '+229$cleaned';
    if (cleaned.startsWith('00229')) return '+${cleaned.substring(2)}';
    return '+229$cleaned';
  }

  Future<bool> _requestPhonePermission() async {
    if (kIsWeb) return true;
    try {
      var status = await Permission.phone.status;
      if (!status.isGranted) status = await Permission.phone.request();
      return status.isGranted;
    } catch (_) { return false; }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      if (phoneNumber.isEmpty) { _showError('Numéro de téléphone non disponible'); return; }
      if (!kIsWeb) { if (!await _requestPhonePermission()) { _showError('Permission d\'appel refusée'); return; } }
      final formattedNumber = _formatPhoneNumber(phoneNumber);
      try { await launchUrl(Uri.parse('tel:$formattedNumber'), mode: LaunchMode.externalApplication); }
      catch (_) {
        try { await launchUrl(Uri.parse('tel:${formattedNumber.replaceAll('+', '')}'), mode: LaunchMode.externalApplication); }
        catch (_) { _showPhoneFallback(formattedNumber); }
      }
    } catch (_) { _showPhoneFallback(phoneNumber); }
  }

  void _showPhoneFallback(String phoneNumber) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Icon(Icons.phone, color: Colors.green, size: 50),
            const SizedBox(height: 16),
            const Text('Composez le numéro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Impossible de lancer l\'appel automatiquement.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(child: Text(phoneNumber, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16))),
                IconButton(icon: const Icon(Icons.copy, color: AppConstants.primaryRed), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro copié !'), duration: Duration(seconds: 1)))),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)), child: const Text('Fermer'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: () { Navigator.pop(context); _makePhoneCall(phoneNumber); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)), child: const Text('Réessayer'))),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _startConversationWithEntreprise(Map<String, dynamic> service) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      final userId = _userData?['id'];
      Map<String, dynamic>? entreprise;
      if (service['entreprise'] != null) {
        entreprise = service['entreprise'] is Map ? Map<String, dynamic>.from(service['entreprise']) : null;
      } else if (service['entreprise_id'] != null) {
        entreprise = {'id': service['entreprise_id']};
      }
      if (entreprise == null) { _showError('Entreprise non identifiée'); return; }
      final entrepriseId = entreprise['id']?.toString();
      if (entrepriseId == null || entrepriseId.isEmpty) { _showError('ID entreprise manquant'); return; }

      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed)));

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/service/${service['id']}/start'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'service_id': service['id'], 'entreprise_id': entrepriseId, 'user_id': userId}),
      );
      if (context.mounted) Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        String conversationId;
        if (data['conversation_id'] != null) conversationId = data['conversation_id'].toString();
        else if (data['conversation']?['id'] != null) conversationId = data['conversation']['id'].toString();
        else if (data['id'] != null) conversationId = data['id'].toString();
        else throw Exception('Format de réponse inattendu');

        if (context.mounted) {
          final otherUser = UserModel(id: entrepriseId, name: entreprise['name'] ?? service['entreprise_name'] ?? 'Entreprise', email: '', photoUrl: entreprise['logo'] ?? service['entreprise_logo'], role: 'entreprise', isOnline: false);
          Navigator.push(context, MaterialPageRoute(builder: (context) => ChangeNotifierProvider.value(
            value: context.read<MessageProvider>(),
            child: ChatScreen(conversationId: conversationId, otherUser: otherUser, serviceName: service['name']?.toString() ?? '', entrepriseName: entreprise!['name']?.toString() ?? 'Entreprise'),
          )));
        }
      } else { _showError('Impossible de démarrer la conversation (${response.statusCode})'); }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showError('Erreur de connexion: ${e.toString()}');
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    try {
      if (phoneNumber.isEmpty) { _showError('Numéro WhatsApp non disponible'); return; }
      final cleanNumber = _formatPhoneNumber(phoneNumber).replaceAll('+', '').replaceAll(' ', '');
      bool launched = false;
      for (final url in ['whatsapp://send?phone=$cleanNumber', 'https://wa.me/$cleanNumber', 'https://api.whatsapp.com/send?phone=$cleanNumber']) {
        try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); launched = true; break; } catch (_) {}
      }
      if (!launched) _showWhatsAppFallback(cleanNumber);
    } catch (_) { _showWhatsAppFallback(phoneNumber); }
  }

  void _showWhatsAppFallback(String phoneNumber) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.chat, color: Color(0xFF25D366), size: 40)),
            const SizedBox(height: 16),
            const Text('Ouvrir WhatsApp', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _buildWhatsAppOption(icon: Icons.business_center, title: 'WhatsApp Business', subtitle: 'Ouvrir avec WhatsApp Business', onTap: () { Navigator.pop(context); _launchWhatsAppWithPackage(phoneNumber, 'com.whatsapp.w4b'); }),
            const SizedBox(height: 8),
            _buildWhatsAppOption(icon: Icons.chat, title: 'WhatsApp', subtitle: 'Ouvrir avec WhatsApp standard', onTap: () { Navigator.pop(context); _launchWhatsAppWithPackage(phoneNumber, 'com.whatsapp'); }),
            const SizedBox(height: 8),
            _buildWhatsAppOption(icon: Icons.public, title: 'WhatsApp Web', subtitle: 'Ouvrir dans le navigateur', onTap: () { Navigator.pop(context); _launchWhatsAppWeb(phoneNumber); }),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(child: Text(phoneNumber, style: const TextStyle(fontWeight: FontWeight.w500))),
                IconButton(icon: const Icon(Icons.copy, color: AppConstants.primaryRed), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro copié !'), duration: Duration(seconds: 1)))),
              ]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryRed, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Fermer')),
          ],
        ),
      ),
    );
  }

  Future<void> _launchWhatsAppWithPackage(String phoneNumber, String package) async {
    try {
      final cleanNumber = phoneNumber.replaceAll('+', '').replaceAll(' ', '');
      try { await launchUrl(Uri.parse('intent://send?phone=$cleanNumber#Intent;package=$package;scheme=whatsapp;end'), mode: LaunchMode.externalApplication); }
      catch (_) { await _launchWhatsAppWeb(phoneNumber); }
    } catch (_) { _showError('Impossible d\'ouvrir WhatsApp'); }
  }

  Future<void> _launchWhatsAppWeb(String phoneNumber) async {
    try {
      final cleanNumber = phoneNumber.replaceAll('+', '').replaceAll(' ', '');
      await launchUrl(Uri.parse('https://web.whatsapp.com/send?phone=$cleanNumber'), mode: LaunchMode.externalApplication);
    } catch (_) { _showError('Impossible d\'ouvrir WhatsApp Web'); }
  }

  Widget _buildWhatsAppOption({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: const Color(0xFF25D366), size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]))])),
            Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey[400]),
          ]),
        ),
      ),
    );
  }

  void _showContactModal(Map<String, dynamic> service) {
    final entreprise = service['entreprise'] ?? {};
    final whatsapp = entreprise['whatsapp_phone'] ?? '';
    final phone    = entreprise['call_phone'] ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(margin: const EdgeInsets.only(top: 12), height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Hero(
                  tag: 'service-${service['id']}',
                  child: Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16),
                        image: service['medias'] != null && (service['medias'] as List).isNotEmpty
                            ? DecorationImage(image: NetworkImage((service['medias'] as List).first), fit: BoxFit.cover)
                            : null),
                    child: service['medias'] == null || (service['medias'] as List).isEmpty ? Icon(Icons.build_circle, size: 30, color: AppConstants.primaryRed) : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(service['name'] ?? 'Service', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(children: [Icon(Icons.business, size: 14, color: Colors.grey[600]), const SizedBox(width: 4), Expanded(child: Text(entreprise['name'] ?? 'Entreprise', style: TextStyle(fontSize: 14, color: Colors.grey[600])))]),
                ])),
                IconButton(icon: Icon(Icons.close, color: Colors.grey[600]), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (phone.isNotEmpty) ...[
                  _buildContactButton(icon: Icons.phone, color: Colors.green, title: 'Appeler', subtitle: phone, onTap: () async {
                    Navigator.pop(context);
                    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                    await _makePhoneCall(phone);
                    if (context.mounted) Navigator.pop(context);
                  }),
                  const SizedBox(height: 12),
                ],
                if (whatsapp.isNotEmpty) ...[
                  _buildContactButton(icon: Icons.chat, color: const Color(0xFF25D366), title: 'WhatsApp', subtitle: whatsapp, onTap: () async {
                    Navigator.pop(context);
                    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                    await _openWhatsApp(whatsapp);
                    if (context.mounted) Navigator.pop(context);
                  }),
                  const SizedBox(height: 12),
                ],
                _buildContactButton(icon: Icons.calendar_month, color: Colors.blue, title: 'Prendre rendez-vous', subtitle: 'Planifier une intervention', onTap: () { 
                  Navigator.pop(context); 
                  // ← MODIFICATION : redirection directe vers l'écran de création de rendez-vous
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider(
                      create: (_) => RendezVousProvider(),
                      child: CreateRendezVousScreen(service: service),
                    ),
                  ));
                }),
                const SizedBox(height: 12),
                _buildContactButton(icon: Icons.message, color: Colors.purple, title: 'Message', subtitle: 'Envoyer un message à l\'entreprise pour ce service', onTap: () { Navigator.pop(context); _startConversationWithEntreprise(service); }),
              ]),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildContactButton({required IconData icon, required Color color, required String title, required String subtitle, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!, width: 1), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 24)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[600]))])),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
          ]),
        ),
      ),
    );
  }

  void _showServiceDetails(Map<String, dynamic> service) => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailScreen(service: service)));

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  Widget build(BuildContext context) {
    final userName      = _userData?['name'] ?? 'Utilisateur';
    final userPhoto     = _userData?['profile_photo_url'] ?? '';
    final hasEntreprise = _userData?['has_entreprise'] ?? false;
    final size          = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        title: _isSearching
            ? AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: _isSearching ? size.width * 0.75 : 0,
                height: 45,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))]),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un service...',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: AppConstants.primaryRed, size: 20),
                    suffixIcon: IconButton(icon: Icon(Icons.close, color: Colors.grey[600], size: 18), onPressed: () { _searchController.clear(); setState(() => _isSearching = false); }),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              )
            : Row(children: [
                Container(
                  height: 32, width: 32,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/images/logo.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.car_repair, color: AppConstants.primaryRed, size: 20))),
                ),
                const SizedBox(width: 8),
                Text('CarEasy', style: TextStyle(fontSize: isSmallScreen ? 18 : 20, fontWeight: FontWeight.bold, color: Colors.white)),
              ]),
        actions: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white, size: 24),
              onPressed: () {
                setState(() {
                  if (_isSearching) { _isSearching = false; _searchController.clear(); _searchFocusNode.unfocus(); }
                  else { _isSearching = true; _searchFocusNode.requestFocus(); }
                });
              },
            ),
          ),
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _fetchData();
                if (mounted) context.read<NotificationProvider>().fetchNotifications(silent: true);
              },
              color: AppConstants.primaryRed,
              child: _isSearching && _searchController.text.isNotEmpty
                  ? _buildSearchResults()
                  : CustomScrollView(
                      controller: _serviceScrollController,
                      slivers: [
                        SliverAppBar(
                          pinned: true, floating: true, elevation: 2,
                          backgroundColor: Colors.white,
                          automaticallyImplyLeading: false,
                          expandedHeight: 60,
                          flexibleSpace: FlexibleSpaceBar(
                            background: Container(
                              height: 60,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: _isLoadingDomaines
                                  ? const Center(child: CircularProgressIndicator())
                                  : ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _domaines.length,
                                      itemBuilder: (_, index) {
                                        final domaine = _domaines[index];
                                        final isSelected = _selectedDomaine == domaine['name'];
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: FilterChip(
                                            label: Text(domaine['name'] ?? '', style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, fontSize: 13)),
                                            selected: isSelected,
                                            onSelected: (selected) => setState(() => _selectedDomaine = selected ? domaine['name'] : null),
                                            backgroundColor: Colors.grey[100],
                                            selectedColor: AppConstants.primaryRed,
                                            checkmarkColor: Colors.white,
                                            elevation: isSelected ? 2 : 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? AppConstants.primaryRed : Colors.grey[300]!)),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.all(size.width * 0.04),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              _buildSectionHeader('Services populaires', onSeeAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AllServicesScreen(initialServices: _services, initialDomaines: _domaines)))),
                              const SizedBox(height: 12),
                              _isLoadingServices
                                  ? _buildServicesShimmer()
                                  : _filteredServices.isEmpty
                                      ? _buildEmptyState('Aucun service trouvé', Icons.search_off)
                                      : _buildServicesList(),
                              const SizedBox(height: 24),
                              _buildSectionHeader('Entreprises', onSeeAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AllEntreprisesScreen(initialEntreprises: _entreprises, initialDomaines: _domaines)))),
                              const SizedBox(height: 12),
                              _isLoadingEntreprises
                                  ? _buildEntreprisesShimmer()
                                  : _entreprises.isEmpty
                                      ? _buildEmptyState('Aucune entreprise trouvée', Icons.business)
                                      : _buildEntreprisesList(),
                              const SizedBox(height: 20),
                            ]),
                          ),
                        ),
                      ],
                    ),
            ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))]),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.home, 'Accueil', 0),
                _buildNavItem(Icons.message, 'Messages', 1),
                _buildNavItem(Icons.calendar_today, 'Rendez-vous', 2),
                _buildNavItem(hasEntreprise ? Icons.business : Icons.add_business, hasEntreprise ? 'Entreprise' : 'Créer', 3),
                _buildProfileNavItem(userName, userPhoto, 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text('Aucun résultat trouvé', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
        const SizedBox(height: 8),
        Text('Essayez avec d\'autres mots-clés', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (_, index) {
        final item = _searchResults[index];
        final isService = item['type'] == 'service';
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: InkWell(
            onTap: () => isService ? _showServiceDetails(item) : null,
            borderRadius: BorderRadius.circular(15),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12),
                      image: item['logo'] != null || (isService && item['medias'] != null && (item['medias'] as List).isNotEmpty)
                          ? DecorationImage(image: NetworkImage(isService ? (item['medias'] as List).first : item['logo']), fit: BoxFit.cover)
                          : null),
                  child: (item['logo'] == null && (!isService || ((item['medias'] as List?)?.isEmpty ?? true))) ? Icon(isService ? Icons.build : Icons.business, size: 24, color: Colors.grey[400]) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: isService ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text(isService ? 'Service' : 'Entreprise', style: TextStyle(fontSize: 11, color: isService ? Colors.blue : Colors.green, fontWeight: FontWeight.w600))),
                    if (isService && item['price'] != null) ...[const SizedBox(width: 8), Text('${item['price']} FCFA', style: TextStyle(fontSize: 12, color: AppConstants.primaryRed, fontWeight: FontWeight.w600))],
                  ]),
                ])),
                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);
          if (index == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesScreen())).then((_) { if (mounted) context.read<MessageProvider>().loadConversations(); });
          if (index == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeNotifierProvider.value(value: context.read<RendezVousProvider>(), child: const RendezVousListScreen())));
          if (index == 3) _handleEntrepriseTap();
          if (index == 4) _showProfileDialog();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: isSelected ? AppConstants.primaryRed : Colors.grey, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: isSelected ? AppConstants.primaryRed : Colors.grey, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _buildProfileNavItem(String userName, String userPhoto, int index) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () { setState(() => _currentIndex = index); _showProfileDialog(); },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 11, backgroundImage: userPhoto.isNotEmpty ? NetworkImage(userPhoto) : null, backgroundColor: Colors.grey[200], child: userPhoto.isEmpty ? Icon(Icons.person, size: 12, color: Colors.grey[600]) : null),
            const SizedBox(height: 2),
            Text('Profil', style: TextStyle(fontSize: 10, color: isSelected ? AppConstants.primaryRed : Colors.grey, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (onSeeAll != null) TextButton(onPressed: onSeeAll, style: TextButton.styleFrom(foregroundColor: AppConstants.primaryRed, padding: EdgeInsets.zero, minimumSize: const Size(50, 30)), child: const Text('Voir plus')),
      ],
    );
  }

  Widget _buildServicesList() => ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _filteredServices.length, itemBuilder: (_, i) => _buildServiceCard(_filteredServices[i], i));

  Widget _buildServiceCard(Map<String, dynamic> service, int index) {
    final entreprise    = service['entreprise'] ?? {};
    final hasPromo      = service['has_promo'] ?? false;
    final isPromoActive = service['is_promo_active'] ?? false;
    final medias        = service['medias'] is List ? service['medias'] : [];
    final curIdx        = _currentImageIndex[index] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Container(height: 160, width: double.infinity, color: Colors.grey[200],
                  child: medias.isNotEmpty
                      ? Image.network(medias[curIdx % medias.length], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey[400])))
                      : Center(child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey[400]))),
            ),
            if (medias.length > 1)
              Positioned(bottom: 8, left: 0, right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(medias.length, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: i == curIdx % medias.length ? Colors.white : Colors.white.withOpacity(0.5)))))),
            if (hasPromo && isPromoActive)
              Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)), child: Text('-${service['discount_percentage'] ?? 0}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
          ]),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10), image: entreprise['logo'] != null ? DecorationImage(image: NetworkImage(entreprise['logo']), fit: BoxFit.cover) : null), child: entreprise['logo'] == null ? Icon(Icons.business, size: 20, color: Colors.grey[600]) : null),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(service['name'] ?? 'Service', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(entreprise['name'] ?? 'Entreprise', style: TextStyle(fontSize: 13, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(service['is_always_open'] == true ? '24h/24' : service['start_time'] != null && service['end_time'] != null ? '${service['start_time']} - ${service['end_time']}' : 'Horaires variables', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ]),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (service['is_price_on_request'] == true)
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)), child: Text('Sur devis', style: TextStyle(fontSize: 11, color: Colors.blue[700], fontWeight: FontWeight.w600)))
                  else if (hasPromo && isPromoActive)
                    Column(children: [Text('${service['price_promo']} FCFA', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppConstants.primaryRed)), Text('${service['price']} FCFA', style: TextStyle(fontSize: 11, color: Colors.grey[500], decoration: TextDecoration.lineThrough))])
                  else
                    Text(service['price'] != null ? '${service['price']} FCFA' : '---', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppConstants.primaryRed)),
                ]),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ElevatedButton.icon(onPressed: () => _showContactModal(service), icon: const Icon(Icons.contact_phone, size: 16), label: const Text('Contacter'), style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 10)))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: () => _showServiceDetails(service), icon: const Icon(Icons.info_outline, size: 16), label: const Text('Détails'), style: OutlinedButton.styleFrom(foregroundColor: AppConstants.primaryRed, side: const BorderSide(color: AppConstants.primaryRed), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 10)))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildEntreprisesList() => SizedBox(height: 200, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _entreprises.length, itemBuilder: (_, i) => _buildEntrepriseCard(_entreprises[i])));

  Widget _buildEntrepriseCard(Map<String, dynamic> entreprise) {
    return Container(
      width: 160, margin: const EdgeInsets.only(right: 12),
      child: Card(
        elevation: 2, shadowColor: Colors.black.withOpacity(0.05), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntrepriseDetailScreen(entreprise: entreprise))),
          borderRadius: BorderRadius.circular(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: Container(height: 100, width: double.infinity, color: Colors.grey[200],
                child: entreprise['logo'] != null && entreprise['logo'].toString().isNotEmpty
                    ? Image.network(entreprise['logo'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Icon(Icons.business, size: 30, color: Colors.grey[400])))
                    : Center(child: Icon(Icons.business, size: 30, color: Colors.grey[400])))),
            Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entreprise['name'] ?? 'Entreprise', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _buildServicesShimmer() => ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: 3, itemBuilder: (_, __) => Container(height: 200, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey[200]!, blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 120, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: const BorderRadius.vertical(top: Radius.circular(16)))), Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 16, width: 150, color: Colors.grey[300]), const SizedBox(height: 8), Container(height: 12, width: 100, color: Colors.grey[300])]))])));

  Widget _buildEntreprisesShimmer() => SizedBox(height: 200, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: 3, itemBuilder: (_, __) => Container(width: 160, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.grey[200]!, blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 100, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: const BorderRadius.vertical(top: Radius.circular(12)))), Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 12, width: 100, color: Colors.grey[300]), const SizedBox(height: 8), Container(height: 10, width: 60, color: Colors.grey[300])]))]))));

  Widget _buildEmptyState(String message, IconData icon) => Container(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Column(children: [Icon(icon, size: 48, color: Colors.grey[400]), const SizedBox(height: 8), Text(message, style: TextStyle(fontSize: 14, color: Colors.grey[600]))])));

  void _handleEntrepriseTap() => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesEntreprisesScreen()));

  void _showComingSoon(String feature) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feature - Bientôt disponible'), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 2)));

  void _showProfileDialog() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => _loadUserData());

  Widget _buildInfoRow(IconData icon, String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Icon(icon, size: 16, color: Colors.grey[600]), const SizedBox(width: 8), Text('$label: ', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: 13)), Expanded(child: Text(value, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))]));
}