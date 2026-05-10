import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import '../widgets/service_selection_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_model.dart';
import '../providers/message_provider.dart';
import '../providers/rendez_vous_provider.dart';
import '../utils/constants.dart';
import 'chat_screen.dart';
import 'entreprise_services_screen.dart';
import 'itinerary_screen.dart';
import 'rendez_vous/create_rendez_vous_screen.dart';
import 'service_detail_screen.dart';

// ─── Constantes ──────────────────────────────────────────────────────────────
const _kDefaultLat  = 6.3654; // Cotonou
const _kDefaultLng  = 2.4183;
const _kZoomDefault = 13.0;
const _kZoomFocus   = 16.0;

const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _mapController  = MapController();
  final _storage        = const FlutterSecureStorage(aOptions: _androidOptions, iOptions: _iOSOptions);
  final _searchCtrl     = TextEditingController();
  final _searchFocus    = FocusNode();

  // ── State ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _entreprises    = [];
  List<Map<String, dynamic>> _filtered       = [];
  List<Map<String, dynamic>> _domaines       = [];
  LatLng?   _userPosition;
  bool      _isLoading        = true;
  bool      _isLoadingLocation= false;
  String?   _selectedDomaine;
  String    _searchQuery      = '';
  Map<String, dynamic>? _selectedEntreprise;

  // ── Animation modal ────────────────────────────────────────────────────────
  late AnimationController _modalCtrl;
  late Animation<double>   _modalAnim;
  bool _modalVisible = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _modalCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _modalAnim = CurvedAnimation(parent: _modalCtrl, curve: Curves.easeOutBack);
    _init();
  }

  @override
  void dispose() {
    _modalCtrl.dispose();
    _mapController.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await Future.wait([_fetchEntreprises(), _fetchDomaines(), _getUserLocation()]);
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _fetchEntreprises() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      final resp  = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/entreprises'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        if (mounted) setState(() { _entreprises = list.cast<Map<String, dynamic>>(); _applyFilter(); });
      }
    } catch (e) { debugPrint('fetchEntreprises: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _fetchDomaines() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      final resp  = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/domaines'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        if (mounted) setState(() => _domaines = list.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  Future<void> _getUserLocation() async {
    if (mounted) setState(() => _isLoadingLocation = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (mounted) setState(() => _userPosition = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_userPosition!, _kZoomDefault);
    } catch (_) {
      if (mounted) setState(() => _userPosition = const LatLng(_kDefaultLat, _kDefaultLng));
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _applyFilter() {
    setState(() {
      _filtered = _entreprises.where((e) {
        final matchDom = _selectedDomaine == null ||
            (e['domaines'] as List?)?.any((d) => d['name'] == _selectedDomaine) == true;
        final matchQ = _searchQuery.isEmpty ||
            (e['name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
        return matchDom && matchQ;
      }).toList();
    });
  }

  // ── Entreprises avec coordonnées valides ───────────────────────────────────
  List<Map<String, dynamic>> get _geoEntreprises =>
      _filtered.where((e) => e['latitude'] != null && e['longitude'] != null).toList();

  // ── Calcul distance ────────────────────────────────────────────────────────
  double? _distanceTo(Map<String, dynamic> e) {
    if (_userPosition == null) return null;
    final lat = double.tryParse(e['latitude'].toString());
    final lng = double.tryParse(e['longitude'].toString());
    if (lat == null || lng == null) return null;
    return const Distance().as(LengthUnit.Kilometer, _userPosition!, LatLng(lat, lng));
  }

  // ── Sélection entreprise ───────────────────────────────────────────────────
  void _selectEntreprise(Map<String, dynamic> e) {
    HapticFeedback.lightImpact();
    final lat = double.tryParse(e['latitude'].toString());
    final lng = double.tryParse(e['longitude'].toString());
    if (lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng - 0.002), _kZoomFocus);
    }
    setState(() { _selectedEntreprise = e; _modalVisible = true; });
    _modalCtrl.forward(from: 0);
  }

  void _closeModal() {
    _modalCtrl.reverse().then((_) {
      if (mounted) setState(() { _modalVisible = false; _selectedEntreprise = null; });
    });
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(children: [
        // ── Carte ──────────────────────────────────────────────────────────
        _buildMap(),

        // ── Header transparent ─────────────────────────────────────────────
        _buildHeader(),

        // ── Chips domaines ─────────────────────────────────────────────────
        _buildDomaineChips(),

        // ── Compteur résultats ─────────────────────────────────────────────
        _buildResultsCount(),

        // ── Bouton ma position ─────────────────────────────────────────────
        _buildLocationButton(),

        // ── Liste bottom ───────────────────────────────────────────────────
        if (!_modalVisible) _buildBottomList(),

        // ── Modal entreprise ───────────────────────────────────────────────
        if (_modalVisible && _selectedEntreprise != null)
          _buildModal(_selectedEntreprise!),

        // ── Loading ────────────────────────────────────────────────────────
        if (_isLoading)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed)),
          ),
      ]),
    );
  }

  // ── Carte Flutter Map ──────────────────────────────────────────────────────
  Widget _buildMap() {
    final center = _userPosition ?? const LatLng(_kDefaultLat, _kDefaultLng);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: _kZoomDefault,
        onTap: (_, __) => _closeModal(),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        // Tuiles OSM
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.careasy.app',
          maxZoom: 19,
        ),

        // Marqueur utilisateur
        if (_userPosition != null)
          MarkerLayer(markers: [
            Marker(
              point: _userPosition!,
              width: 50, height: 50,
              child: _UserMarker(),
            ),
          ]),

        // Marqueurs entreprises
        MarkerLayer(
          markers: _geoEntreprises.map((e) {
            final lat = double.parse(e['latitude'].toString());
            final lng = double.parse(e['longitude'].toString());
            final isSelected = _selectedEntreprise?['id'] == e['id'];
            return Marker(
              point: LatLng(lat, lng),
              width: isSelected ? 130 : 110,
              height: isSelected ? 54 : 44,
              child: GestureDetector(
                onTap: () => _selectEntreprise(e),
                child: _EntrepriseMarker(entreprise: e, isSelected: isSelected),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Row(children: [
              // Bouton retour
              _GlassButton(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),

              // Barre de recherche
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    onChanged: (v) { _searchQuery = v; _applyFilter(); },
                    decoration: InputDecoration(
                      hintText: 'Rechercher une entreprise…',
                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: AppConstants.primaryRed, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close, color: Colors.grey[400], size: 18),
                              onPressed: () { _searchCtrl.clear(); _searchQuery = ''; _applyFilter(); },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Compteur
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Text(
                  '${_geoEntreprises.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Chips domaines ─────────────────────────────────────────────────────────
  Widget _buildDomaineChips() {
    if (_domaines.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 74,
      left: 0, right: 0,
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _domaines.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            if (i == 0) {
              final sel = _selectedDomaine == null;
              return _DomChip(label: 'Tous', selected: sel, onTap: () { setState(() => _selectedDomaine = null); _applyFilter(); });
            }
            final d = _domaines[i - 1];
            final sel = _selectedDomaine == d['name'];
            return _DomChip(label: d['name'] ?? '', selected: sel, onTap: () {
              setState(() => _selectedDomaine = sel ? null : d['name']);
              _applyFilter();
            });
          },
        ),
      ),
    );
  }

  Widget _buildResultsCount() => const SizedBox.shrink();

  // ── Bouton position ────────────────────────────────────────────────────────
  Widget _buildLocationButton() {
    return Positioned(
      right: 14,
      bottom: _modalVisible ? 380 : 230,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _GlassButton(
          key: ValueKey(_isLoadingLocation),
          onTap: _isLoadingLocation ? null : _getUserLocation,
          color: Colors.white,
          child: _isLoadingLocation
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryRed))
              : const Icon(Icons.my_location, color: AppConstants.primaryRed, size: 22),
        ),
      ),
    );
  }

  // ── Liste entreprises en bas ───────────────────────────────────────────────
  Widget _buildBottomList() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.05)],
          ),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _EntrepriseCard(
                entreprise: _filtered[i],
                distance: _distanceTo(_filtered[i]),
                onTap: () {
                  if (_filtered[i]['latitude'] != null && _filtered[i]['longitude'] != null) {
                    _selectEntreprise(_filtered[i]);
                  } else {
                    _showNoLocationSnack();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  void _showNoLocationSnack() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text("Cette entreprise n'a pas de localisation enregistrée"),
      backgroundColor: Colors.orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  // ── Modal entreprise ───────────────────────────────────────────────────────
  Widget _buildModal(Map<String, dynamic> e) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: ScaleTransition(
        scale: _modalAnim,
        alignment: Alignment.bottomCenter,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(_modalAnim),
          child: _EntrepriseModal(
            entreprise: e,
            distance: _distanceTo(e),
            userPosition: _userPosition,
            onClose: _closeModal,
          ),
        ),
      ),
    );
  }
}

class _UserMarker extends StatefulWidget {
  @override State<_UserMarker> createState() => _UserMarkerState();
}

class _UserMarkerState extends State<_UserMarker> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
    AnimatedBuilder(animation: _anim, builder: (_, __) => Container(
      width: 50 * _anim.value, height: 50 * _anim.value,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue.withOpacity(0.15 * (1 - _anim.value + 0.5)),
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
      ),
    )),
    Container(
      width: 18, height: 18,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 6)],
      ),
    ),
  ]);
}


class _EntrepriseMarker extends StatelessWidget {
  final Map<String, dynamic> entreprise;
  final bool isSelected;
  const _EntrepriseMarker({required this.entreprise, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final logo = entreprise['logo']?.toString();
    final name = entreprise['name']?.toString() ?? 'Entreprise';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      decoration: BoxDecoration(
        color: isSelected ? AppConstants.primaryRed : Colors.white,
        borderRadius: BorderRadius.circular(isSelected ? 22 : 16),
        boxShadow: [
          BoxShadow(
            color: isSelected ? AppConstants.primaryRed.withOpacity(0.5) : Colors.black.withOpacity(0.25),
            blurRadius: isSelected ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: isSelected ? null : Border.all(color: AppConstants.primaryRed.withOpacity(0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: logo != null && logo.isNotEmpty
                ? Image.network(logo, width: 22, height: 22, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultIcon(isSelected))
                : _defaultIcon(isSelected),
          ),
          const SizedBox(width: 5),
          Flexible(child: Text(
            name.length > 10 ? '${name.substring(0, 10)}…' : name,
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          )),
          if (isSelected) ...[
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white),
          ],
        ]),
      ),
    );
  }

  Widget _defaultIcon(bool sel) => Container(
    width: 22, height: 22,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      color: sel ? Colors.white.withOpacity(0.2) : AppConstants.primaryRed.withOpacity(0.1),
    ),
    child: Icon(Icons.business, size: 14, color: sel ? Colors.white : AppConstants.primaryRed),
  );
}


class _EntrepriseCard extends StatelessWidget {
  final Map<String, dynamic> entreprise;
  final double? distance;
  final VoidCallback onTap;
  const _EntrepriseCard({required this.entreprise, required this.onTap, this.distance});

  @override
  Widget build(BuildContext context) {
    final logo   = entreprise['logo']?.toString();
    final name   = entreprise['name']?.toString() ?? 'Entreprise';
    final status = entreprise['status']?.toString();
    final doms   = entreprise['domaines'] as List?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              height: 80, width: double.infinity, color: Colors.grey[100],
              child: logo != null && logo.isNotEmpty
                  ? Image.network(logo, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (doms != null && doms.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text((doms.first['name'] ?? '').toString(),
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              if (distance != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.near_me, size: 10, color: AppConstants.primaryRed),
                  const SizedBox(width: 2),
                  Text(
                    distance! < 1 ? '${(distance! * 1000).round()} m' : '${distance!.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 10, color: AppConstants.primaryRed, fontWeight: FontWeight.w600),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Center(child: Icon(Icons.business, size: 28, color: Colors.grey[300]));
}

class _EntrepriseModal extends StatefulWidget {
  final Map<String, dynamic> entreprise;
  final double? distance;
  final LatLng? userPosition;
  final VoidCallback onClose;

  const _EntrepriseModal({
    required this.entreprise,
    required this.onClose,
    this.distance,
    this.userPosition,
  });

  @override
  State<_EntrepriseModal> createState() => _EntrepriseModalState();
}

class _EntrepriseModalState extends State<_EntrepriseModal> {
  bool _isLoadingServices = false;
  List<Map<String, dynamic>> _services = [];

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String get _name    => widget.entreprise['name']?.toString() ?? 'Entreprise';
  String get _logo    => widget.entreprise['logo']?.toString() ?? '';
  String get _boutiq  => widget.entreprise['image_boutique']?.toString() ?? '';
  String get _addr    => widget.entreprise['google_formatted_address']?.toString() ?? 
                         widget.entreprise['siege']?.toString() ?? '';
  String get _whatsapp=> widget.entreprise['whatsapp_phone']?.toString() ?? '';
  String get _phone   => widget.entreprise['call_phone']?.toString() ?? '';
  String get _status  => widget.entreprise['status']?.toString() ?? '';
  List   get _doms    => (widget.entreprise['domaines'] as List?) ?? [];
  List   get _servicesList => (widget.entreprise['services'] as List?) ?? [];

  LatLng? get _position {
    final lat = double.tryParse(widget.entreprise['latitude']?.toString() ?? '');
    final lng = double.tryParse(widget.entreprise['longitude']?.toString() ?? '');
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  // ─── Formatage téléphone (identique à service_detail.dart) ─────────────────
  String _formatPhoneNumber(String phone) {
    if (phone.isEmpty) return '';
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('00')) return '+${cleaned.substring(2)}';
    if (cleaned.startsWith('0') && cleaned.length == 10) return '+229${cleaned.substring(1)}';
    if (cleaned.length == 8) return '+229$cleaned';
    if (cleaned.startsWith('229') && cleaned.length >= 11) return '+$cleaned';
    return cleaned;
  }

  // ─── APPELER ───────────────────────────────────────────────────────────────
  Future<void> _makePhoneCall() async {
    if (_phone.isEmpty) {
      _showErrorSnackbar('Aucun numéro de téléphone disponible');
      return;
    }
    try {
      final formattedNumber = _formatPhoneNumber(_phone);
      final uri = Uri.parse('tel:$formattedNumber');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showErrorSnackbar('Impossible de passer l\'appel');
      }
    } catch (e) {
      _showErrorSnackbar('Erreur lors de l\'appel');
    }
  }

  // ─── WHATSAPP avec détection d'application ─────────────────────────────────
  Future<void> _openWhatsApp() async {
    if (_whatsapp.isEmpty) {
      _showErrorSnackbar('Aucun numéro WhatsApp disponible');
      return;
    }
    try {
      final cleanNumber = _formatPhoneNumber(_whatsapp).replaceAll('+', '');
      // Essayer d'ouvrir avec l'API standard WhatsApp
      final whatsappUri = Uri.parse('https://wa.me/$cleanNumber');
      
      // Vérifier si l'application WhatsApp est installée
      bool canLaunchWhatsApp = false;
      
      // Sur Android, on peut essayer le schéma intent
      if (Platform.isAndroid) {
        try {
          final whatsAppPackage = await _getWhatsAppPackage();
          if (whatsAppPackage != null) {
            final intentUri = Uri.parse('intent://send?phone=$cleanNumber#Intent;scheme=whatsapp;package=$whatsAppPackage;end');
            if (await canLaunchUrl(intentUri)) {
              await launchUrl(intentUri, mode: LaunchMode.externalApplication);
              return;
            }
          }
        } catch (_) {}
      }
      
      // Fallback: ouvrir dans le navigateur (WhatsApp Web ou redirection)
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackbar('WhatsApp n\'est pas installé sur cet appareil');
      }
    } catch (e) {
      _showErrorSnackbar('Erreur lors de l\'ouverture de WhatsApp');
    }
  }

  // Détection du package WhatsApp (Business ou normal)
  Future<String?> _getWhatsAppPackage() async {
    // Vérifier si WhatsApp Business est installé
    if (await _isAppInstalled('com.whatsapp.w4b')) {
      return 'com.whatsapp.w4b';
    }
    // Vérifier si WhatsApp standard est installé
    if (await _isAppInstalled('com.whatsapp')) {
      return 'com.whatsapp';
    }
    return null;
  }

  Future<bool> _isAppInstalled(String packageName) async {
    try {
      final result = await MethodChannel('com.careasy.app/platform').invokeMethod<bool>('isAppInstalled', {'package': packageName});
      return result == true;
    } catch (_) {
      // Fallback: on suppose que l'app n'est pas installée
      return false;
    }
  }

  // ─── RENDEZ-VOUS : Sélection du service ────────────────────────────────────
  Future<void> _openRendezVous() async {
    await showServiceSelectionModal(
      context: context,
      entreprise: widget.entreprise,
      mode: ServiceSelectionMode.rendezVous,
    );
  }

  void _showServiceSelectionDialog() {
    final allServices = _servicesList.isNotEmpty ? _servicesList : _services;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Choisissez un service',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allServices.length,
                itemBuilder: (context, index) {
                  final service = allServices[index] as Map<String, dynamic>;
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppConstants.primaryRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getServiceIcon(service['name']?.toString() ?? ''),
                        color: AppConstants.primaryRed,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      service['name']?.toString() ?? 'Service sans nom',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _getServicePriceText(service),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToCreateRdv(service);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _getServicePriceText(Map<String, dynamic> service) {
    if (service['is_price_on_request'] == true) {
      return 'Prix sur devis';
    }
    final hasPromo = service['has_promo'] == true && service['is_promo_active'] == true;
    if (hasPromo) {
      return '${service['price_promo']} FCFA (au lieu de ${service['price']} FCFA)';
    }
    final price = service['price'];
    if (price != null && price.toString().isNotEmpty) {
      return '$price FCFA';
    }
    return 'Prix non défini';
  }

  IconData _getServiceIcon(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('lavage') || name.contains('nettoyage')) return Icons.cleaning_services;
    if (name.contains('vidange') || name.contains('entretien')) return Icons.build;
    if (name.contains('pneu') || name.contains('gomme')) return Icons.circle;
    if (name.contains('climatisation') || name.contains('clim')) return Icons.ac_unit;
    if (name.contains('diagnostic')) return Icons.medical_services;
    if (name.contains('réparation') || name.contains('reparation')) return Icons.handyman;
    return Icons.car_repair;
  }

  void _navigateToCreateRdv(Map<String, dynamic>? service) {
    final serviceToUse = service ?? _createGenericService();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => RendezVousProvider(),
          child: CreateRendezVousScreen(service: serviceToUse),
        ),
      ),
    );
  }

  Map<String, dynamic> _createGenericService() {
    return {
      'id': null,
      'name': 'Service général',
      'price': 'Sur devis',
      'is_price_on_request': true,
      'entreprise': widget.entreprise,
      'descriptions': 'Prenez rendez-vous avec ${_name} pour discuter de vos besoins.',
    };
  }

  // ─── MESSAGE / CHAT ────────────────────────────────────────────────────────
  void _openChat() async {
    await showServiceSelectionModal(
      context: context,
      entreprise: widget.entreprise,
      mode: ServiceSelectionMode.message,
    );
  }

  // ─── ITINÉRAIRE ────────────────────────────────────────────────────────────
  void _openItinerary() {
    if (_position == null) {
      _showErrorSnackbar('Adresse non disponible');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItineraryScreen(
          destination: _position!,
          destinationName: _name,
          userPosition: widget.userPosition,
        ),
      ),
    );
  }

  // ─── CONSULTER TOUS LES SERVICES ───────────────────────────────────────────
  void _openAllServices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntrepriseServicesScreen(entreprise: widget.entreprise),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allServices = _servicesList.isNotEmpty ? _servicesList : _services;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, -8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Poignée
        Container(
          margin: const EdgeInsets.only(top: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
        ),

        // Header avec image boutique ou logo
        _buildHeader(context),

        // Infos
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Domaines
            if (_doms.isNotEmpty) _buildDomaines(),

            // Adresse + distance
            if (_addr.isNotEmpty || widget.distance != null) _buildAddressRow(),

            const SizedBox(height: 14),

            // ── 5 icônes d'action ──────────────────────────────────────────
            _buildActionIcons(context),

            const SizedBox(height: 14),

            // ── Bouton Consulter les services ──────────────────────────────
            _buildServicesButton(context, allServices.length),

            const SizedBox(height: 16),
          ]),
        ),

        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final coverUrl = _boutiq.isNotEmpty ? _boutiq : (_logo.isNotEmpty ? _logo : '');
    return Stack(children: [
      // Bannière
      ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Container(
          height: 110,
          width: double.infinity,
          color: Colors.grey[100],
          child: coverUrl.isNotEmpty
              ? Image.network(coverUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverPlaceholder())
              : _coverPlaceholder(),
        ),
      ),
      // Gradient overlay
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
            ),
          ),
        ),
      ),
      // Bouton fermer
      Positioned(
        top: 10,
        right: 10,
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: const Icon(Icons.close, color: Colors.white, size: 18),
          ),
        ),
      ),
      // Logo + nom en bas de la bannière
      Positioned(
        bottom: 12,
        left: 14,
        right: 60,
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
              image: _logo.isNotEmpty
                  ? DecorationImage(image: NetworkImage(_logo), fit: BoxFit.cover, onError: (_, __) {})
                  : null,
            ),
            child: _logo.isEmpty ? const Icon(Icons.business, color: AppConstants.primaryRed, size: 24) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_status == 'validated')
                Row(children: const [
                  Icon(Icons.verified, color: Color(0xFF4CAF50), size: 12),
                  SizedBox(width: 3),
                  Text('Vérifié', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _coverPlaceholder() => Container(
    color: AppConstants.primaryRed.withOpacity(0.08),
    child: Center(
      child: Icon(Icons.business_center, size: 40, color: AppConstants.primaryRed.withOpacity(0.2)),
    ),
  );

  Widget _buildDomaines() => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Wrap(
      spacing: 6,
      runSpacing: 4,
      children: _doms.take(3).map((d) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppConstants.primaryRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            d['name']?.toString() ?? '',
            style: const TextStyle(fontSize: 10, color: AppConstants.primaryRed, fontWeight: FontWeight.w600),
          ),
        );
      }).toList(),
    ),
  );

  Widget _buildAddressRow() => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(children: [
      const Icon(Icons.location_on, size: 14, color: AppConstants.primaryRed),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          _addr,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (widget.distance != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: AppConstants.primaryRed, borderRadius: BorderRadius.circular(12)),
          child: Text(
            widget.distance! < 1
                ? '${(widget.distance! * 1000).round()} m'
                : '${widget.distance!.toStringAsFixed(1)} km',
            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ]),
  );

  Widget _buildActionIcons(BuildContext context) {
    final hasPhone = _phone.isNotEmpty;
    final hasWhatsapp = _whatsapp.isNotEmpty;
    final hasServices = _servicesList.isNotEmpty || _services.isNotEmpty;

    return Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      // Appeler
      _ActionIcon(
        icon: Icons.phone,
        label: 'Appeler',
        color: const Color(0xFF4CAF50),
        onTap: hasPhone ? _makePhoneCall : null,
      ),
      // WhatsApp
      _ActionIcon(
        icon: Icons.chat,
        label: 'WhatsApp',
        color: const Color(0xFF25D366),
        onTap: hasWhatsapp ? _openWhatsApp : null,
      ),
      // Message (Chat in-app)
      _ActionIcon(
        icon: Icons.message_rounded,
        label: 'Message',
        color: Colors.deepPurple,
        onTap: _openChat,
      ),
      // Rendez-vous
      _ActionIcon(
        icon: Icons.calendar_month,
        label: 'Rendez-vous',
        color: Colors.blue,
        onTap: _openRendezVous,
      ),
      // Itinéraire
      _ActionIcon(
        icon: Icons.near_me_rounded,
        label: 'Itinéraire',
        color: AppConstants.primaryRed,
        onTap: _position != null ? _openItinerary : null,
      ),
    ]);
  }

  Widget _buildServicesButton(BuildContext context, int servicesCount) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openAllServices,
        icon: const Icon(Icons.storefront_rounded, size: 18),
        label: Text(
          servicesCount > 0
              ? 'Consulter les services ($servicesCount)'
              : 'Voir les services',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryRed,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}



class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap!();
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.25), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}

class _DomChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DomChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppConstants.primaryRed : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 2))],
          border: selected ? null : Border.all(color: Colors.grey[200]!, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }
}


class _GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;

  const _GlassButton({required this.child, this.onTap, this.color, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color ?? Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Center(child: child),
      ),
    );
  }
}