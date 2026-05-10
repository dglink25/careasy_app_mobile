// lib/screens/entreprise_services_screen.dart
// ═══════════════════════════════════════════════════════════════════════════
//  CarEasy — Services d'une entreprise avec détails complets
//  Belle UI, informations riches, notes, horaires, promos
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_model.dart';
import '../providers/message_provider.dart';
import '../providers/rendez_vous_provider.dart';
import '../utils/constants.dart';
import 'chat_screen.dart';
import 'rendez_vous/create_rendez_vous_screen.dart';
import 'service_detail_screen.dart';

const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

// ═════════════════════════════════════════════════════════════════════════════
class EntrepriseServicesScreen extends StatefulWidget {
  final Map<String, dynamic> entreprise;
  const EntrepriseServicesScreen({super.key, required this.entreprise});

  @override
  State<EntrepriseServicesScreen> createState() => _EntrepriseServicesScreenState();
}

class _EntrepriseServicesScreenState extends State<EntrepriseServicesScreen>
    with SingleTickerProviderStateMixin {

  final _storage = const FlutterSecureStorage(aOptions: _androidOptions, iOptions: _iOSOptions);

  List<Map<String, dynamic>> _services   = [];
  List<Map<String, dynamic>> _domaines   = [];
  bool   _isLoading  = true;
  String? _selectedDomaine;
  String  _searchQ   = '';

  late TabController _tabCtrl;
  final _searchCtrl  = TextEditingController();
  bool   _isSearching = false;

  // Image carousel
  final Map<int, int> _imgIndex = {};
  final Map<int, dynamic> _imgTimers = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _fetchServices();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _fetchServices() async {
    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final id    = widget.entreprise['id']?.toString() ?? '';
      final resp  = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/entreprises/$id'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data  = jsonDecode(resp.body) as Map<String, dynamic>;
        final srvs  = (data['services'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final doms  = <Map<String, dynamic>>{};
        for (final s in srvs) {
          if (s['domaine'] != null) doms.add(Map<String, dynamic>.from(s['domaine'] as Map));
        }
        if (mounted) setState(() {
          _services = srvs;
          _domaines = doms.toList();
        });
      }
    } catch (e) { debugPrint('fetchServices: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  // ── Filtres ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    return _services.where((s) {
      final matchD = _selectedDomaine == null || (s['domaine']?['name']) == _selectedDomaine;
      final matchQ = _searchQ.isEmpty ||
          (s['name'] ?? '').toLowerCase().contains(_searchQ.toLowerCase()) ||
          (s['descriptions'] ?? '').toLowerCase().contains(_searchQ.toLowerCase());
      return matchD && matchQ;
    }).toList();
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final e       = widget.entreprise;
    final logo    = e['logo']?.toString() ?? '';
    final name    = e['name']?.toString() ?? 'Entreprise';
    final boutiq  = e['image_boutique']?.toString() ?? '';
    final addr    = e['google_formatted_address']?.toString() ?? e['siege']?.toString() ?? '';
    final doms    = (e['domaines'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: NestedScrollView(
        headerSliverBuilder: (_, inner) => [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: Icon(_isSearching ? Icons.close : Icons.search, size: 18, color: Colors.white),
                ),
                onPressed: () => setState(() { _isSearching = !_isSearching; if (!_isSearching) { _searchCtrl.clear(); _searchQ = ''; } }),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                // Bannière
                boutiq.isNotEmpty || logo.isNotEmpty
                    ? Image.network(boutiq.isNotEmpty ? boutiq : logo, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _coverBg())
                    : _coverBg(),

                // Gradient
                DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                ))),

                // Infos entreprise
                Positioned(bottom: 60, left: 16, right: 16,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    // Logo
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)],
                        image: logo.isNotEmpty
                            ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover, onError: (_, __) {})
                            : null,
                      ),
                      child: logo.isEmpty ? const Icon(Icons.business, color: AppConstants.primaryRed, size: 28) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      if (e['status'] == 'validated')
                        Row(children: const [
                          Icon(Icons.verified, color: Color(0xFF4CAF50), size: 13),
                          SizedBox(width: 4),
                          Text('Entreprise vérifiée', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      if (addr.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.location_on, color: Colors.white70, size: 12),
                          const SizedBox(width: 3),
                          Expanded(child: Text(addr, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]),
                      ],
                    ])),
                  ]),
                ),
              ]),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: _isSearching
                  ? Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        onChanged: (v) => setState(() => _searchQ = v),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un service…',
                          prefixIcon: Icon(Icons.search, color: AppConstants.primaryRed, size: 20),
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.white,
                      child: TabBar(
                        controller: _tabCtrl,
                        labelColor: AppConstants.primaryRed,
                        unselectedLabelColor: Colors.grey[500],
                        indicatorColor: AppConstants.primaryRed,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        tabs: [
                          Tab(text: 'Services (${_services.length})'),
                          const Tab(text: 'Infos'),
                        ],
                      ),
                    ),
            ),
          ),
          // Chips domaines
          if (_domaines.isNotEmpty && !_isSearching)
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverChipsDelegate(
                domaines: _domaines,
                selected: _selectedDomaine,
                onSelect: (d) => setState(() => _selectedDomaine = d == _selectedDomaine ? null : d),
              ),
            ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed))
            : _isSearching
                ? _buildServicesList()
                : TabBarView(controller: _tabCtrl, children: [
                    _buildServicesList(),
                    _buildInfoTab(e),
                  ]),
      ),
    );
  }

  Widget _coverBg() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [AppConstants.primaryRed.withOpacity(0.8), Colors.black87],
      ),
    ),
  );

  // ── Liste services ─────────────────────────────────────────────────────────
  Widget _buildServicesList() {
    final list = _filtered;
    if (list.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off, size: 56, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('Aucun service trouvé', style: TextStyle(fontSize: 15, color: Colors.grey[500])),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _fetchServices,
      color: AppConstants.primaryRed,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _ServiceCard(
          service: list[i],
          entreprise: widget.entreprise,
          imgIndex: _imgIndex[i] ?? 0,
          onContact: () => _showContactSheet(context, list[i]),
          onDetail: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ServiceDetailScreen(service: list[i]))),
        ),
      ),
    );
  }

  // ── Onglet infos entreprise ────────────────────────────────────────────────
  Widget _buildInfoTab(Map<String, dynamic> e) {
    final phone    = e['call_phone']?.toString() ?? '';
    final whatsapp = e['whatsapp_phone']?.toString() ?? '';
    final doms     = (e['domaines'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Contact
        _SectionCard(
          title: 'Coordonnées',
          icon: Icons.contact_phone_rounded,
          children: [
            if (phone.isNotEmpty)
              _InfoRow(icon: Icons.phone, label: 'Téléphone', value: phone, color: Colors.green,
                  onTap: () => launchUrl(Uri.parse('tel:$phone'))),
            if (whatsapp.isNotEmpty)
              _InfoRow(icon: Icons.chat, label: 'WhatsApp', value: whatsapp, color: const Color(0xFF25D366),
                  onTap: () => launchUrl(Uri.parse('https://wa.me/${whatsapp.replaceAll('+', '')}'  ))),
            if (e['google_formatted_address'] != null)
              _InfoRow(icon: Icons.location_on, label: 'Adresse', value: e['google_formatted_address']!, color: AppConstants.primaryRed),
          ],
        ),
        const SizedBox(height: 14),

        // Domaines
        if (doms.isNotEmpty) _SectionCard(
          title: 'Domaines d\'activité',
          icon: Icons.category_rounded,
          children: [
            Wrap(spacing: 8, runSpacing: 6, children: doms.map((d) {
              return Chip(
                label: Text(d['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                backgroundColor: AppConstants.primaryRed.withOpacity(0.08),
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                side: BorderSide.none,
              );
            }).toList()),
          ],
        ),
        const SizedBox(height: 14),

        // Statut
        _SectionCard(
          title: 'Statut',
          icon: Icons.verified_outlined,
          children: [
            _StatusBadge(status: e['status']?.toString() ?? ''),
          ],
        ),
      ]),
    );
  }

  // ── Contact bottom sheet ───────────────────────────────────────────────────
  void _showContactSheet(BuildContext ctx, Map<String, dynamic> service) {
    HapticFeedback.lightImpact();
    final entData = service['entreprise'] ?? widget.entreprise;
    final phone    = entData['call_phone']?.toString() ?? '';
    final whatsapp = entData['whatsapp_phone']?.toString() ?? '';

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.contact_support_rounded, color: AppConstants.primaryRed),
              const SizedBox(width: 8),
              Text('Contacter pour "${service['name']}"', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
            const SizedBox(height: 16),
            if (phone.isNotEmpty) _SheetBtn(icon: Icons.phone, label: 'Appeler', sublabel: phone, color: Colors.green,
              onTap: () { Navigator.pop(ctx); launchUrl(Uri.parse('tel:$phone')); }),
            if (phone.isNotEmpty) const SizedBox(height: 8),
            if (whatsapp.isNotEmpty) _SheetBtn(icon: Icons.chat, label: 'WhatsApp', sublabel: whatsapp, color: const Color(0xFF25D366),
              onTap: () { Navigator.pop(ctx); launchUrl(Uri.parse('https://wa.me/${whatsapp.replaceAll('+', '')}')); }),
            if (whatsapp.isNotEmpty) const SizedBox(height: 8),
            _SheetBtn(icon: Icons.message_rounded, label: 'Message', sublabel: 'Envoyer un message direct', color: Colors.deepPurple,
              onTap: () {
                Navigator.pop(ctx);
                final eu = widget.entreprise;
                final ou = UserModel(id: eu['id']?.toString() ?? '', name: eu['name'] ?? '', photoUrl: eu['logo'], role: 'entreprise', isOnline: false);
                Navigator.push(ctx, MaterialPageRoute(builder: (_) => ChangeNotifierProvider.value(
                  value: ctx.read<MessageProvider>(),
                  child: ChatScreen(conversationId: eu['id']?.toString() ?? '', otherUser: ou, serviceName: service['name']?.toString()),
                )));
              }),
            const SizedBox(height: 8),
            _SheetBtn(icon: Icons.calendar_month, label: 'Rendez-vous', sublabel: 'Planifier une intervention', color: Colors.blue,
              onTap: () {
                Navigator.pop(ctx);
                final svc = Map<String, dynamic>.from(service)..['entreprise'] = widget.entreprise;
                Navigator.push(ctx, MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider(
                    create: (_) => RendezVousProvider(),
                    child: CreateRendezVousScreen(service: svc),
                  ),
                ));
              }),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Card service enrichie
// ═════════════════════════════════════════════════════════════════════════════
class _ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final Map<String, dynamic> entreprise;
  final int imgIndex;
  final VoidCallback onContact;
  final VoidCallback onDetail;

  const _ServiceCard({
    required this.service,
    required this.entreprise,
    required this.imgIndex,
    required this.onContact,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final medias   = (service['medias'] as List?) ?? [];
    final hasPromo = service['has_promo'] == true && service['is_promo_active'] == true;
    final isReq    = service['is_price_on_request'] == true;
    final totalRev = (service['total_reviews'] as num?)?.toInt() ?? 0;
    final avgRat   = totalRev > 0 ? (service['average_rating'] as num?)?.toDouble() ?? 0 : 0.0;
    final schedule = service['schedule'];
    final isAlways = service['is_always_open'] == true;
    final visible  = service['is_visibility'] != false;

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Image ──────────────────────────────────────────────────────────
        Stack(children: [
          SizedBox(
            height: 170, width: double.infinity,
            child: medias.isNotEmpty
                ? Image.network(
                    medias[imgIndex % medias.length].toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imgPlaceholder(),
                  )
                : _imgPlaceholder(),
          ),
          // Badge promo
          if (hasPromo)
            Positioned(top: 10, left: 10,
              child: _Badge(label: '-${service['discount_percentage'] ?? 0}%', color: Colors.red)),
          // Badge visibilité
          if (!visible)
            Positioned(top: 10, right: 10,
              child: _Badge(label: 'Masqué', color: Colors.grey)),
          // Note
          if (totalRev > 0)
            Positioned(top: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 13),
                  const SizedBox(width: 3),
                  Text('${avgRat.toStringAsFixed(1)} ($totalRev)', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          // Indicateurs carrousel
          if (medias.length > 1)
            Positioned(bottom: 8, left: 0, right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children:
                List.generate(medias.length, (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == imgIndex % medias.length ? Colors.white : Colors.white.withOpacity(0.5),
                  ),
                )),
              ),
            ),
        ]),

        // ── Contenu ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Nom + domaine
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(service['name']?.toString() ?? 'Service',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (service['domaine'] != null) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(service['domaine']['name']?.toString() ?? '',
                        style: const TextStyle(fontSize: 10, color: AppConstants.primaryRed, fontWeight: FontWeight.w600)),
                  ),
                ],
              ])),
              const SizedBox(width: 10),
              // Prix
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (isReq)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                    child: const Text('Sur devis', style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w700)),
                  )
                else if (hasPromo) ...[
                  Text('${service['price_promo']} FCFA', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppConstants.primaryRed)),
                  Text('${service['price']} FCFA', style: TextStyle(fontSize: 11, color: Colors.grey[400], decoration: TextDecoration.lineThrough)),
                ] else
                  Text(service['price'] != null ? '${service['price']} FCFA' : '---',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppConstants.primaryRed)),
              ]),
            ]),

            // Description
            if (service['descriptions'] != null && service['descriptions'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(service['descriptions'].toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],

            // Étoiles
            if (totalRev > 0) ...[
              const SizedBox(height: 8),
              _StarRow(rating: avgRat, total: totalRev),
            ],

            // Horaires
            const SizedBox(height: 8),
            _HorairesRow(isAlways: isAlways, schedule: schedule,
                start: service['start_time']?.toString(), end: service['end_time']?.toString()),

            // Promo dates
            if (hasPromo && service['promo_start_date'] != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.local_offer, size: 13, color: Colors.red),
                const SizedBox(width: 4),
                Text(
                  'Promo jusqu\'au ${_fmtDate(service['promo_end_date']?.toString())}',
                  style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
                ),
              ]),
            ],

            // Boutons
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: onContact,
                icon: const Icon(Icons.contact_phone, size: 15),
                label: const Text('Contacter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: onDetail,
                icon: const Icon(Icons.info_outline, size: 15),
                label: const Text('Détails', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.primaryRed,
                  side: const BorderSide(color: AppConstants.primaryRed),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _imgPlaceholder() => Container(
    color: Colors.grey[100],
    child: Center(child: Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.grey[300])),
  );

  String _fmtDate(String? raw) {
    if (raw == null) return '';
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) { return raw; }
  }
}

// ── Widgets utilitaires ────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  final double rating;
  final int total;
  const _StarRow({required this.rating, required this.total});

  @override
  Widget build(BuildContext context) => Row(children: [
    ...List.generate(5, (i) {
      final filled = i < rating.floor();
      final half   = !filled && i < rating;
      return Icon(
        filled ? Icons.star_rounded : half ? Icons.star_half_rounded : Icons.star_outline_rounded,
        size: 14, color: filled || half ? const Color(0xFFF59E0B) : Colors.grey[300],
      );
    }),
    const SizedBox(width: 5),
    Text('${rating.toStringAsFixed(1)} ($total avis)', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
  ]);
}

class _HorairesRow extends StatelessWidget {
  final bool isAlways;
  final dynamic schedule;
  final String? start, end;
  const _HorairesRow({required this.isAlways, this.schedule, this.start, this.end});

  @override
  Widget build(BuildContext context) {
    String label = '';
    if (isAlways) {
      label = '24h/24 — 7j/7';
    } else if (start != null && end != null) {
      label = '$start – $end';
    } else if (schedule != null && schedule is Map) {
      final days = (schedule as Map).values.where((d) => d['is_open'] == true);
      if (days.isNotEmpty) {
        final first = days.first;
        label = '${first['start']} – ${first['end']}';
      }
    }
    if (label.isEmpty) label = 'Horaires variables';

    return Row(children: [
      Icon(isAlways ? Icons.all_inclusive : Icons.access_time, size: 13, color: Colors.grey[500]),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    ]);
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 18, color: AppConstants.primaryRed),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ]),
      const SizedBox(height: 12),
      ...children,
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final VoidCallback? onTap;
  const _InfoRow({required this.icon, required this.label, required this.value, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GestureDetector(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onTap != null ? color : Colors.black87)),
        ])),
        if (onTap != null) Icon(Icons.chevron_right, color: color, size: 18),
      ]),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c; IconData ico; String lbl;
    switch (status) {
      case 'validated': c = Colors.green; ico = Icons.verified; lbl = 'Entreprise validée'; break;
      case 'pending'  : c = Colors.orange; ico = Icons.hourglass_top; lbl = 'En attente de validation'; break;
      case 'rejected' : c = Colors.red; ico = Icons.cancel; lbl = 'Rejetée'; break;
      default         : c = Colors.grey; ico = Icons.help; lbl = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ico, size: 16, color: c),
        const SizedBox(width: 8),
        Text(lbl, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

class _SheetBtn extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final Color color;
  final VoidCallback onTap;
  const _SheetBtn({required this.icon, required this.label, required this.sublabel, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text(sublabel, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ])),
          Icon(Icons.arrow_forward_ios, size: 13, color: Colors.grey[400]),
        ]),
      ),
    ),
  );
}

// ── SliverDelegate pour chips ─────────────────────────────────────────────────
class _SliverChipsDelegate extends SliverPersistentHeaderDelegate {
  final List<Map<String, dynamic>> domaines;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _SliverChipsDelegate({required this.domaines, required this.selected, required this.onSelect});

  @override double get minExtent => 48;
  @override double get maxExtent => 48;
  @override bool shouldRebuild(_SliverChipsDelegate old) =>
      old.selected != selected || old.domaines.length != domaines.length;

  @override
  Widget build(BuildContext ctx, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.grey[50],
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: domaines.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final d   = domaines[i];
          final sel = selected == d['name'];
          return GestureDetector(
            onTap: () => onSelect(d['name']?.toString() ?? ''),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? AppConstants.primaryRed : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? AppConstants.primaryRed : Colors.grey[300]!, width: 1),
                boxShadow: sel ? [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.3), blurRadius: 8)] : [],
              ),
              child: Text(d['name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.grey[700])),
            ),
          );
        },
      ),
    );
  }
}