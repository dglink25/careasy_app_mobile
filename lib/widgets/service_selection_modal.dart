// lib/widgets/service_selection_modal.dart
//
// Modal de sélection de service avant :
//   - Prendre un rendez-vous  (mode: ServiceSelectionMode.rendezVous)
//   - Envoyer un message      (mode: ServiceSelectionMode.message)
//
// Usage depuis n'importe quel écran :
//   showServiceSelectionModal(
//     context: context,
//     entreprise: entrepriseMap,
//     mode: ServiceSelectionMode.rendezVous,
//   );

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/message_provider.dart';
import '../providers/rendez_vous_provider.dart';
import '../utils/constants.dart';
import '../screens/chat_screen.dart';
import '../screens/rendez_vous/create_rendez_vous_screen.dart';

// ─── Enum mode ────────────────────────────────────────────────────────────────
enum ServiceSelectionMode { rendezVous, message }

// ─── Point d'entrée public ────────────────────────────────────────────────────
Future<void> showServiceSelectionModal({
  required BuildContext context,
  required Map<String, dynamic> entreprise,
  required ServiceSelectionMode mode,
}) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useRootNavigator: true,
    builder: (_) => _ServiceSelectionModal(
      entreprise: entreprise,
      mode: mode,
    ),
  );
}

// ─── Modal principale ─────────────────────────────────────────────────────────
class _ServiceSelectionModal extends StatefulWidget {
  final Map<String, dynamic> entreprise;
  final ServiceSelectionMode mode;

  const _ServiceSelectionModal({
    required this.entreprise,
    required this.mode,
  });

  @override
  State<_ServiceSelectionModal> createState() => _ServiceSelectionModalState();
}

class _ServiceSelectionModalState extends State<_ServiceSelectionModal>
    with SingleTickerProviderStateMixin {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  // ── State ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _services = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // ── Helpers ───────────────────────────────────────────────────────────────
  bool get _isRdv => widget.mode == ServiceSelectionMode.rendezVous;
  String get _entrepriseName =>
      widget.entreprise['name']?.toString() ?? 'Entreprise';
  String get _logo => widget.entreprise['logo']?.toString() ?? '';

  Color get _accentColor =>
      _isRdv ? Colors.blue.shade600 : Colors.deepPurple.shade600;

  IconData get _modeIcon =>
      _isRdv ? Icons.calendar_month_rounded : Icons.message_rounded;

  String get _modeLabel =>
      _isRdv ? 'Prendre rendez-vous' : 'Envoyer un message';

  String get _modeHint =>
      _isRdv
          ? 'Choisissez le service pour lequel vous souhaitez planifier un rendez-vous.'
          : 'Choisissez le service concerné par votre message.';

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _animCtrl.forward();
    _loadServices();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Chargement des services ───────────────────────────────────────────────
  Future<void> _loadServices() async {
    // 1. Essayer d'abord les services déjà inclus dans l'entreprise
    final inlined = widget.entreprise['services'];
    if (inlined is List && inlined.isNotEmpty) {
      if (mounted) {
        setState(() {
          _services = inlined.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
      return;
    }

    // 2. Sinon appel API
    try {
      final token = await _storage.read(key: 'auth_token');
      final id = widget.entreprise['id']?.toString() ?? '';
      final resp = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/entreprises/$id'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final raw = data['services'];
        if (mounted) {
          setState(() {
            _services = raw is List
                ? raw.cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() { _error = 'Impossible de charger les services'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Erreur réseau'; _isLoading = false; });
    }
  }

  // ── Filtrage ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _services;
    return _services
        .where((s) =>
            (s['name']?.toString() ?? '')
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            (s['description']?.toString() ?? '')
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Future<void> _onServiceSelected(Map<String, dynamic> service) async {
    HapticFeedback.lightImpact();

    if (_isRdv) {
      Navigator.pop(context);
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;

      final enriched = Map<String, dynamic>.from(service);
      enriched['entreprise'] ??= widget.entreprise;

      Navigator.push(
        context,
        _slideRoute(
          ChangeNotifierProvider(
            create: (_) => RendezVousProvider(),
            child: CreateRendezVousScreen(service: enriched),
          ),
        ),
      );
    } else {

      await _startConversation(service);
    }
  }

  
  Future<void> _startConversation(Map<String, dynamic> service) async {
    
    final navigator = Navigator.of(context, rootNavigator: true);
    final messageProvider = context.read<MessageProvider>();

    try {
      final token = await _storage.read(key: 'auth_token');
      final userRaw = await _storage.read(key: 'user_data');
      final userId =
          userRaw != null ? jsonDecode(userRaw)['id']?.toString() : null;
      final entrepriseId = widget.entreprise['id']?.toString() ?? '';

      // Afficher le loading AVANT de fermer le modal
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppConstants.primaryRed),
        ),
      );

      final resp = await http.post(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/conversation/service/${service['id']}/start'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'service_id': service['id'],
          'entreprise_id': entrepriseId,
          'user_id': userId,
        }),
      );

      navigator.pop(); // Ferme le CircularProgressIndicator

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = jsonDecode(resp.body);
        String conversationId;
        if (data['conversation_id'] != null) {
          conversationId = data['conversation_id'].toString();
        } else if (data['conversation']?['id'] != null) {
          conversationId = data['conversation']['id'].toString();
        } else if (data['id'] != null) {
          conversationId = data['id'].toString();
        } else {
          throw Exception('Format inattendu');
        }

        final otherUser = UserModel(
          id: entrepriseId,
          name: _entrepriseName,
          photoUrl: _logo.isNotEmpty ? _logo : null,
          role: 'entreprise',
          isOnline: false,
        );

        
        navigator.pop(); // Ferme le modal de sélection de service

        navigator.push(
          _slideRoute(
            ChangeNotifierProvider.value(
              value: messageProvider,
              child: ChatScreen(
                conversationId: conversationId,
                otherUser: otherUser,
                serviceName: service['name']?.toString() ?? '',
                entrepriseName: _entrepriseName,
              ),
            ),
          ),
        );
      } 
      
      else {
        
        navigator.pop(); // Ferme le modal de sélection
        ScaffoldMessenger.of(navigator.context).showSnackBar(SnackBar(
          content: Text('Impossible de démarrer la conversation (${resp.statusCode})'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      try { navigator.pop(); } catch (_) {} // Ferme le loading si encore ouvert
      try { navigator.pop(); } catch (_) {} // Ferme le modal si encore ouvert
      ScaffoldMessenger.of(navigator.context).showSnackBar(SnackBar(
        content: const Text('Erreur de connexion'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  PageRoute _slideRoute(Widget child) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => child,
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 320),
      );

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * 0.88;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Poignée ────────────────────────────────────────────────
              _buildHandle(),
              // ── Header ────────────────────────────────────────────────
              _buildHeader(),
              // ── Barre de recherche (si > 4 services) ──────────────────
              if (_services.length > 4) _buildSearchBar(),
              // ── Contenu ───────────────────────────────────────────────
              Flexible(child: _buildBody()),
              // ── Padding bas ───────────────────────────────────────────
              SizedBox(height: mq.padding.bottom + 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 14),
      child: Row(
        children: [
          // Icône mode (rdv ou message)
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_modeIcon, color: _accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _modeLabel,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                // Logo + nom entreprise
                Row(
                  children: [
                    if (_logo.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          _logo,
                          width: 16,
                          height: 16,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.business,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      )
                    else
                      Icon(Icons.business, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _entrepriseName,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Bouton fermer
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Rechercher un service…',
            hintStyle:
                TextStyle(color: Colors.grey.shade400, fontSize: 13),
            prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_services.isEmpty) return _buildEmpty();
    if (_filtered.isEmpty) return _buildNoResults();
    return _buildServiceList();
  }

  Widget _buildLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(color: AppConstants.primaryRed),
              SizedBox(height: 14),
              Text(
                'Chargement des services…',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );

  Widget _buildError() => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _error!,
              style:
                  TextStyle(color: Colors.grey.shade600, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                setState(() { _error = null; _isLoading = true; });
                _loadServices();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: TextButton.styleFrom(
                  foregroundColor: AppConstants.primaryRed),
            ),
          ],
        ),
      );

  Widget _buildEmpty() => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.storefront_outlined,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Aucun service disponible',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Cette entreprise n\'a pas encore publié de services.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _buildNoResults() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(
              'Aucun résultat pour "$_searchQuery"',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );

  Widget _buildServiceList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hint contextuel
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _accentColor.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: _accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _modeHint,
                    style: TextStyle(
                        fontSize: 11,
                        color: _accentColor,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Compteur
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            '${_filtered.length} service${_filtered.length > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),

        // Liste
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: _filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ServiceTile(
              service: _filtered[i],
              accentColor: _accentColor,
              modeIcon: _modeIcon,
              onTap: () => _onServiceSelected(_filtered[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Tuile service ────────────────────────────────────────────────────────────
class _ServiceTile extends StatefulWidget {
  final Map<String, dynamic> service;
  final Color accentColor;
  final IconData modeIcon;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.service,
    required this.accentColor,
    required this.modeIcon,
    required this.onTap,
  });

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.03,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  Map<String, dynamic> get s => widget.service;

  String get _name => s['name']?.toString() ?? 'Service';
  String? get _image {
    final medias = s['medias'];
    if (medias is List && medias.isNotEmpty) return medias.first.toString();
    return null;
  }

  String get _priceText {
    if (s['is_price_on_request'] == true) return 'Sur devis';
    final hasPromo = s['has_promo'] == true && s['is_promo_active'] == true;
    if (hasPromo) return '${s['price_promo']} FCFA';
    final price = s['price'];
    if (price != null) return '$price FCFA';
    return '—';
  }

  bool get _hasPromo =>
      s['has_promo'] == true && s['is_promo_active'] == true;

  String get _hours {
    if (s['is_always_open'] == true) return '24h/24 • 7j/7';
    final start = s['start_time']?.toString();
    final end = s['end_time']?.toString();
    if (start != null && end != null) return '$start – $end';
    return 'Horaires variables';
  }

  Color get _priceColor {
    if (s['is_price_on_request'] == true) return Colors.blue.shade600;
    return AppConstants.primaryRed;
  }

  // ── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // ── Vignette image ───────────────────────────────────────
              ClipRRect(
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(16)),
                child: Stack(
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      color: Colors.grey.shade100,
                      child: _image != null
                          ? Image.network(
                              _image!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                    // Badge promo
                    if (_hasPromo)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-${s['discount_percentage'] ?? 0}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Infos ────────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nom
                      Text(
                        _name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),

                      // Prix
                      Row(
                        children: [
                          Text(
                            _priceText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _priceColor,
                            ),
                          ),
                          if (_hasPromo &&
                              s['price'] != null) ...[
                            const SizedBox(width: 5),
                            Text(
                              '${s['price']} FCFA',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Horaires
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text(
                            _hours,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bouton action ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.modeIcon,
                    size: 18,
                    color: widget.accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Center(
        child: Icon(
          Icons.build_circle_outlined,
          size: 28,
          color: Colors.grey.shade300,
        ),
      );
}