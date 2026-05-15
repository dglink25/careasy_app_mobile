// lib/screens/service_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/rendez_vous_provider.dart';
import 'rendez_vous/create_rendez_vous_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/cached_image.dart';   // ← widget image mis en cache

// ─── Widget étoiles inline ────────────────────────────────────────────────────
class _StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const _StarRow({required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.floor();
        final half   = !filled && i < rating;
        return Icon(
          filled ? Icons.star_rounded : half ? Icons.star_half_rounded : Icons.star_outline_rounded,
          size: size,
          color: filled || half ? const Color(0xFFF59E0B) : Colors.grey[300],
        );
      }),
    );
  }
}

class ServiceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  const ServiceDetailScreen({super.key, required this.service});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentImageIndex = 0;
  late PageController _pageController;
  bool _isSharing = false;

  // ── Carousel automatique ──────────────────────────────────────────────────
  Timer? _carouselTimer;

  // ── Avis ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoadingReviews = false;
  bool _reviewsLoaded = false;

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions, iOptions: _iOSOptions,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _pageController = PageController();
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_reviewsLoaded) _fetchReviews();
    });

    // Démarrer le carousel si plusieurs images
    final medias = widget.service['medias'];
    if (medias is List && medias.length > 1) {
      _startCarousel(medias.length);
    }
  }

  // ── Carousel automatique (5 s) ────────────────────────────────────────────
  void _startCarousel(int count) {
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final next = (_currentImageIndex + 1) % count;
      setState(() => _currentImageIndex = next);
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ── Avis ──────────────────────────────────────────────────────────────────
  Future<void> _fetchReviews() async {
    if (_isLoadingReviews) return;
    setState(() => _isLoadingReviews = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final serviceId = widget.service['id']?.toString() ?? '';
      if (serviceId.isEmpty) {
        setState(() { _isLoadingReviews = false; _reviewsLoaded = true; });
        return;
      }
      final resp = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/services/$serviceId/reviews'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final list = data is List ? data : (data['data'] ?? data['reviews'] ?? []);
        setState(() {
          _reviews = List<Map<String, dynamic>>.from(
            (list as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );
          _isLoadingReviews = false;
          _reviewsLoaded = true;
        });
      } else {
        setState(() { _isLoadingReviews = false; _reviewsLoaded = true; });
      }
    } catch (e) {
      debugPrint('Erreur chargement avis: $e');
      setState(() { _isLoadingReviews = false; _reviewsLoaded = true; });
    }
  }

  // ── Téléphone / WhatsApp ──────────────────────────────────────────────────
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

  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      final uri = Uri.parse('tel:${_formatPhoneNumber(phoneNumber)}');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l\'appel')));
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    try {
      final clean = _formatPhoneNumber(phoneNumber).replaceAll('+', '');
      final uri = Uri.parse('https://wa.me/$clean');
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l\'ouverture de WhatsApp')));
    }
  }

  // ── Partage ───────────────────────────────────────────────────────────────
  String _formatScheduleForShare() {
    Map<String, dynamic> schedule = {};
    final scheduleRaw = widget.service['schedule'];
    if (scheduleRaw != null) {
      if (scheduleRaw is String && scheduleRaw.isNotEmpty) {
        try { final decoded = jsonDecode(scheduleRaw); if (decoded is Map) schedule = Map<String, dynamic>.from(decoded); } catch (_) {}
      } else if (scheduleRaw is Map) { schedule = Map<String, dynamic>.from(scheduleRaw); }
    }
    const days = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    const dayNames = ['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'];
    if (widget.service['is_always_open'] == true || widget.service['is_open_24h'] == true) return 'Ouvert 24h/24 et 7j/7';
    if (schedule.isEmpty) return 'Horaires non définis';
    final buffer = StringBuffer();
    for (int i = 0; i < days.length; i++) {
      final daySchedule = schedule[days[i]] is Map ? Map<String, dynamic>.from(schedule[days[i]]) : {};
      final isOpen = daySchedule['is_open'] == true || daySchedule['is_open'] == '1' || daySchedule['is_open'] == 1;
      if (isOpen) {
        buffer.writeln('${dayNames[i]} : ${daySchedule['start']?.toString().substring(0, 5) ?? '--:--'} - ${daySchedule['end']?.toString().substring(0, 5) ?? '--:--'}');
      } else { buffer.writeln(' ${dayNames[i]} : Fermé'); }
    }
    return buffer.toString().trim();
  }

  Future<void> _shareService() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final serviceName       = widget.service['name'] ?? 'Service';
      final entreprise        = widget.service['entreprise'] is Map ? Map<String, dynamic>.from(widget.service['entreprise']) : {};
      final entrepriseName    = entreprise['name'] ?? 'Entreprise';
      final entrepriseAddress = entreprise['address'] ?? 'Adresse non renseignée';
      final hasPromo          = widget.service['has_promo'] ?? false;
      final isPromoActive     = widget.service['is_promo_active'] ?? false;
      String priceText;
      if (widget.service['is_price_on_request'] == true) { priceText = 'Prix : Sur devis'; }
      else if (hasPromo && isPromoActive) { priceText = 'Prix : ${widget.service['price']} FCFA → ${widget.service['price_promo']} FCFA (-${widget.service['discount_percentage'] ?? 0}%)'; }
      else { final price = widget.service['price'] ?? 'Non défini'; priceText = 'Prix : ${price != 'Non défini' ? '$price FCFA' : price}'; }

      final description  = widget.service['descriptions'] ?? 'Aucune description disponible';
      final scheduleText = _formatScheduleForShare();
      final callPhone    = entreprise['call_phone'] ?? '';
      final whatsappPhone = entreprise['whatsapp_phone'] ?? '';
      String contactText = '';
      if (callPhone.isNotEmpty) contactText += '\nTéléphone : $callPhone';
      if (whatsappPhone.isNotEmpty) contactText += '\nWhatsApp : $whatsappPhone';
      final shareText = '''$serviceName\n\nEntreprise : $entrepriseName\nAdresse : $entrepriseAddress\n$priceText\n\nDescription :\n$description\n\nHoraires d'ouverture :\n$scheduleText\n\nContact :$contactText\n\n--- Trouvé sur CarEasy ---\nTéléchargez l'application : https://careasy.app/download'''.trim();

      final medias = widget.service['medias'] is List ? widget.service['medias'] : [];
      XFile? imageFile;
      if (medias.isNotEmpty && medias.first != null && medias.first.toString().isNotEmpty) {
        try {
          final response = await http.get(Uri.parse(medias.first.toString()));
          if (response.statusCode == 200) {
            final tempDir = await getTemporaryDirectory();
            final file = File('${tempDir.path}/service_share_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await file.writeAsBytes(response.bodyBytes);
            imageFile = XFile(file.path);
          }
        } catch (_) {}
      }
      if (imageFile != null) {
        await Share.shareXFiles([imageFile], text: shareText, subject: serviceName);
        final file = File(imageFile.path);
        if (await file.exists()) await file.delete();
      } else { await Share.share(shareText, subject: serviceName); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur lors du partage: $e')));
    } finally { if (mounted) setState(() => _isSharing = false); }
  }

  void _navigateToCreateRdv() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => RendezVousProvider(),
        child: CreateRendezVousScreen(service: widget.service),
      ),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final entreprise    = widget.service['entreprise'] is Map ? Map<String, dynamic>.from(widget.service['entreprise']) : {};
    final medias        = widget.service['medias'] is List ? List<String>.from(widget.service['medias']) : <String>[];
    final hasPromo      = widget.service['has_promo'] ?? false;
    final isPromoActive = widget.service['is_promo_active'] ?? false;
    final size          = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 380;
    final int totalReviews = (widget.service['total_reviews'] as num?)?.toInt() ?? 0;
    final double avgRating = totalReviews > 0 ? (widget.service['average_rating'] as num?)?.toDouble() ?? 0.0 : 0.0;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar avec carousel automatique ────────────────────────
          SliverAppBar(
            expandedHeight: size.height * 0.4,
            pinned: true,
            stretch: true,
            backgroundColor: AppConstants.primaryRed,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Carousel d'images ──────────────────────────────────
                  if (medias.isNotEmpty)
                    PageView.builder(
                      controller: _pageController,
                      itemCount: medias.length,
                      onPageChanged: (i) => setState(() => _currentImageIndex = i),
                      itemBuilder: (_, i) => CachedImage(
                        url: medias[i],
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          color: Colors.grey[300],
                          child: Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey[600])),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey[300],
                      child: Center(child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey[600])),
                    ),

                  // ── Gradient bas ───────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                      ),
                    ),
                  ),

                  // ── Indicateurs de page ────────────────────────────────
                  if (medias.length > 1)
                    Positioned(
                      bottom: 72,
                      left: 0, right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(medias.length, (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _currentImageIndex ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: i == _currentImageIndex ? BoxShape.rectangle : BoxShape.circle,
                            borderRadius: i == _currentImageIndex ? BorderRadius.circular(4) : null,
                            color: i == _currentImageIndex
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                          ),
                        )),
                      ),
                    ),

                  // ── Titre + entreprise ─────────────────────────────────
                  Positioned(
                    bottom: 20, left: 20, right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.service['name'] ?? 'Service',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          // Logo entreprise
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedImage(
                              url: entreprise['logo']?.toString(),
                              width: 30, height: 30, fit: BoxFit.cover,
                              errorWidget: Container(
                                width: 30, height: 30,
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.business, size: 16, color: AppConstants.primaryRed),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entreprise['name'] ?? 'Entreprise',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (totalReviews > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.3)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 16),
                                const SizedBox(width: 4),
                                Text(avgRating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                              ]),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), shape: BoxShape.circle),
              child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), shape: BoxShape.circle),
                child: _isSharing
                    ? const SizedBox(width: 40, height: 40, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
                    : IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: _shareService),
              ),
            ],
          ),

          // ── Contenu ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(children: [

              // ── Prix + contacts rapides + rating ──────────────────────────
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Prix', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 4),
                        if (widget.service['is_price_on_request'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(20)),
                            child: Text('Sur devis', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w600, fontSize: 16)),
                          )
                        else if (hasPromo && isPromoActive)
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text('${widget.service['price_promo']} FCFA', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppConstants.primaryRed)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12)),
                                child: Text('-${widget.service['discount_percentage'] ?? 0}%', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ]),
                            Text('${widget.service['price']} FCFA', style: TextStyle(fontSize: 16, color: Colors.grey[500], decoration: TextDecoration.lineThrough)),
                          ])
                        else
                          Text(
                            widget.service['price'] != null ? '${widget.service['price']} FCFA' : 'Prix non défini',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppConstants.primaryRed),
                          ),
                      ]),
                    ),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(15)),
                        child: IconButton(
                          icon: const Icon(Icons.phone, color: Colors.green),
                          onPressed: entreprise['call_phone'] != null ? () => _makePhoneCall(entreprise['call_phone']) : null,
                          constraints: const BoxConstraints(), padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                        child: IconButton(
                          icon: const Icon(Icons.message, color: Color(0xFF25D366)),
                          onPressed: entreprise['whatsapp_phone'] != null ? () => _openWhatsApp(entreprise['whatsapp_phone']) : null,
                          constraints: const BoxConstraints(), padding: EdgeInsets.zero,
                        ),
                      ),
                    ]),
                  ]),
                  if (totalReviews > 0) ...[
                    const SizedBox(height: 12),
                    _buildRatingSummaryBar(avgRating, totalReviews),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _navigateToCreateRdv,
                      icon: const Icon(Icons.calendar_month, size: 20),
                      label: const Text('Prendre rendez-vous', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              ),

              // ── Onglets ───────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                child: Column(children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: AppConstants.primaryRed,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: AppConstants.primaryRed,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 13),
                    tabs: [
                      const Tab(text: 'Description'),
                      Tab(text: totalReviews > 0 ? 'Avis ($totalReviews)' : 'Avis'),
                      const Tab(text: 'Horaires'),
                      const Tab(text: 'Contact'),
                    ],
                  ),
                  SizedBox(
                    height: 320,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDescriptionTab(),
                          _buildReviewsTab(avgRating, totalReviews),
                          _buildScheduleTab(),
                          _buildContactTab(Map<String, dynamic>.from(entreprise)),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),

              // ── À propos de l'entreprise ──────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('À propos de l\'entreprise', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(children: [
                    CachedImage(
                      url: entreprise['logo']?.toString(),
                      width: 60, height: 60,
                      borderRadius: BorderRadius.circular(15),
                      errorWidget: Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(15)),
                        child: Icon(Icons.business, size: 30, color: Colors.grey[400]),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(entreprise['name'] ?? 'Entreprise', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Expanded(child: Text(entreprise['address'] ?? 'Adresse non renseignée', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ]),
                    ])),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Rating summary ────────────────────────────────────────────────────────
  Widget _buildRatingSummaryBar(double avgRating, int totalReviews) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(avgRating.toStringAsFixed(1), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Color(0xFF92400E), height: 1)),
          _StarRow(rating: avgRating, size: 15),
          const SizedBox(height: 2),
          Text('$totalReviews avis', style: TextStyle(fontSize: 11, color: Colors.amber[800])),
        ]),
        const SizedBox(width: 16),
        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFFDE68A)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_ratingLabel(avgRating), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF78350F))),
          const SizedBox(height: 4),
          Text(_ratingSubtitle(avgRating, totalReviews), style: TextStyle(fontSize: 12, color: Colors.amber[900], height: 1.3)),
        ])),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Color(0xFFFEF3C7), shape: BoxShape.circle),
          child: Icon(_ratingIcon(avgRating), color: const Color(0xFFF59E0B), size: 22),
        ),
      ]),
    );
  }

  String _ratingLabel(double r) {
    if (r >= 4.5) return 'Excellent'; if (r >= 4.0) return 'Très bien'; if (r >= 3.5) return 'Bien';
    if (r >= 3.0) return 'Correct'; if (r >= 2.0) return 'Moyen'; return 'À améliorer';
  }
  String _ratingSubtitle(double r, int count) {
    if (r >= 4.5) return 'Les clients adorent ce service !'; if (r >= 4.0) return 'Très apprécié par les clients.';
    if (r >= 3.5) return 'Bonne expérience globale.'; if (r >= 3.0) return 'Service satisfaisant.'; return 'Expériences mitigées.';
  }
  IconData _ratingIcon(double r) {
    if (r >= 4.5) return Icons.favorite_rounded; if (r >= 4.0) return Icons.thumb_up_rounded;
    if (r >= 3.0) return Icons.sentiment_satisfied_rounded; return Icons.sentiment_neutral_rounded;
  }

  // ── Onglet Description ────────────────────────────────────────────────────
  Widget _buildDescriptionTab() {
    final description = widget.service['descriptions'] ?? 'Aucune description disponible';
    if (description.isEmpty || description == 'Aucune description disponible') {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Aucune description disponible pour ce service', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center)));
    }
    return SingleChildScrollView(child: Text(description, style: const TextStyle(fontSize: 14, height: 1.6)));
  }

  // ── Onglet Avis ───────────────────────────────────────────────────────────
  Widget _buildReviewsTab(double avgRating, int totalReviews) {
    if (totalReviews == 0) return _buildNoReviewsState();
    if (!_reviewsLoaded && !_isLoadingReviews) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchReviews());
    }
    return Column(children: [
      _buildReviewsHeader(avgRating, totalReviews),
      const SizedBox(height: 12),
      const Divider(height: 1),
      const SizedBox(height: 8),
      Expanded(child: _isLoadingReviews
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _reviews.isEmpty
              ? _buildNoReviewsState()
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _reviews.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, i) => _buildReviewItem(_reviews[i]),
                )),
    ]);
  }

  Widget _buildNoReviewsState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle), child: Icon(Icons.rate_review_outlined, size: 40, color: Colors.grey[400])),
    const SizedBox(height: 16),
    Text('Pas encore d\'avis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[600])),
    const SizedBox(height: 6),
    Text('Soyez le premier à noter ce service !', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
  ]));

  Widget _buildReviewsHeader(double avgRating, int totalReviews) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Column(children: [
        Text(avgRating.toStringAsFixed(1), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Color(0xFF1F2937), height: 1)),
        _StarRow(rating: avgRating, size: 16),
        Text('sur 5', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ]),
      const SizedBox(width: 20),
      Expanded(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final starNum = 5 - i;
          final count   = _reviews.where((r) => (r['rating'] as num?)?.toInt() == starNum).length;
          final ratio   = _reviews.isNotEmpty ? count / _reviews.length : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Text('$starNum', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.star_rounded, size: 11, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio, minHeight: 7,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    starNum >= 4 ? const Color(0xFF22C55E) : starNum == 3 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                  ),
                ),
              )),
              const SizedBox(width: 6),
              SizedBox(width: 22, child: Text('$count', style: TextStyle(fontSize: 11, color: Colors.grey[500]))),
            ]),
          );
        }),
      )),
    ]);
  }

  Widget _buildReviewItem(Map<String, dynamic> review) {
    final clientName  = review['client']?['name']?.toString() ?? review['client_name']?.toString() ?? 'Client anonyme';
    final clientPhoto = review['client']?['profile_photo_url']?.toString() ?? review['client']?['photo_url']?.toString();
    final rating      = (review['rating'] as num?)?.toInt() ?? 0;
    final comment     = review['comment']?.toString() ?? '';
    final createdAt   = review['created_at']?.toString() ?? '';
    final initials    = clientName.isNotEmpty ? clientName[0].toUpperCase() : '?';
    final dateStr     = _formatReviewDate(createdAt);
    final avatarColors = [const Color(0xFF6366F1), const Color(0xFF8B5CF6), const Color(0xFFEC4899), const Color(0xFF14B8A6), const Color(0xFF0EA5E9), const Color(0xFFF97316), const Color(0xFF22C55E), const Color(0xFFEF4444)];
    final avatarColor = avatarColors[clientName.codeUnits.fold(0, (a, b) => a + b) % avatarColors.length];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Avatar avec cache
        ClipOval(
          child: CachedImage(
            url: clientPhoto,
            width: 42, height: 42,
            errorWidget: Container(
              width: 42, height: 42,
              color: avatarColor,
              child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(clientName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2937)), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (dateStr.isNotEmpty) Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
          const SizedBox(height: 4),
          _StarRow(rating: rating.toDouble(), size: 14),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comment, style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.4)),
          ],
        ])),
      ]),
    );
  }

  String _formatReviewDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final dt   = DateTime.parse(dateStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inDays == 0) return 'Aujourd\'hui';
      if (diff.inDays == 1) return 'Hier';
      if (diff.inDays < 7)  return 'Il y a ${diff.inDays} j';
      if (diff.inDays < 30) return 'Il y a ${(diff.inDays / 7).floor()} sem';
      if (diff.inDays < 365) return 'Il y a ${(diff.inDays / 30).floor()} mois';
      return 'Il y a ${(diff.inDays / 365).floor()} an${(diff.inDays / 365).floor() > 1 ? 's' : ''}';
    } catch (_) { return ''; }
  }

  // ── Onglet Horaires ───────────────────────────────────────────────────────
  Widget _buildScheduleTab() {
    Map<String, dynamic> schedule = {};
    dynamic scheduleRaw = widget.service['schedule'];
    if (scheduleRaw != null) {
      if (scheduleRaw is String && scheduleRaw.isNotEmpty) {
        try { final decoded = jsonDecode(scheduleRaw); if (decoded is Map) schedule = Map<String, dynamic>.from(decoded); } catch (_) {}
      } else if (scheduleRaw is Map) { schedule = Map<String, dynamic>.from(scheduleRaw); }
    }
    const days = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    const dayNames = ['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'];

    if (widget.service['is_always_open'] == true || widget.service['is_open_24h'] == true) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.all_inclusive, size: 50, color: Colors.green),
        SizedBox(height: 16),
        Text('Disponible 24h/24 et 7j/7', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.green)),
        SizedBox(height: 8),
        Text('Service accessible à tout moment', style: TextStyle(fontSize: 13, color: Colors.grey)),
      ]));
    }
    if (schedule.isEmpty) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.schedule, size: 50, color: Colors.orange),
        SizedBox(height: 16),
        Text('Horaires non définis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.orange)),
        SizedBox(height: 8),
        Text('Contacter le prestataire pour plus d\'informations', style: TextStyle(fontSize: 13, color: Colors.grey), textAlign: TextAlign.center),
      ]));
    }
    return ListView.separated(
      itemCount: days.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final daySchedule = schedule[days[i]] is Map ? Map<String, dynamic>.from(schedule[days[i]]) : {};
        final openValue = daySchedule['is_open'];
        final isOpen = openValue == true || openValue == '1' || openValue == 1;
        String start = '--:--'; String end = '--:--';
        if (isOpen) {
          if (daySchedule['start'] != null) { start = daySchedule['start'].toString(); if (start.length > 5) start = start.substring(0, 5); }
          if (daySchedule['end'] != null) { end = daySchedule['end'].toString(); if (end.length > 5) end = end.substring(0, 5); }
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(width: 80, child: Text(dayNames[i], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
            const SizedBox(width: 12),
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: isOpen ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(isOpen ? '$start - $end' : 'Fermé', style: TextStyle(color: isOpen ? Colors.green : Colors.red, fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.center),
            )),
          ]),
        );
      },
    );
  }

  // ── Onglet Contact ────────────────────────────────────────────────────────
  Widget _buildContactTab(Map<String, dynamic> entreprise) {
    return ListView(children: [
      if (entreprise['call_phone'] != null && entreprise['call_phone'].toString().isNotEmpty)
        ListTile(
          leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.phone, color: Colors.green, size: 20)),
          title: const Text('Téléphone', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(entreprise['call_phone']),
          trailing: IconButton(icon: const Icon(Icons.call, color: Colors.green), onPressed: () => _makePhoneCall(entreprise['call_phone'])),
        ),
      if (entreprise['whatsapp_phone'] != null && entreprise['whatsapp_phone'].toString().isNotEmpty)
        ListTile(
          leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.message, color: Color(0xFF25D366), size: 20)),
          title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(entreprise['whatsapp_phone']),
          trailing: IconButton(icon: const Icon(Icons.open_in_browser, color: Color(0xFF25D366)), onPressed: () => _openWhatsApp(entreprise['whatsapp_phone'])),
        ),
      if (entreprise['email'] != null && entreprise['email'].toString().isNotEmpty)
        ListTile(
          leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.email, color: Colors.blue, size: 20)),
          title: const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(entreprise['email']),
          trailing: IconButton(icon: const Icon(Icons.send, color: Colors.blue), onPressed: () {}),
        ),
      if ((entreprise['call_phone'] == null || entreprise['call_phone'].toString().isEmpty) &&
          (entreprise['whatsapp_phone'] == null || entreprise['whatsapp_phone'].toString().isEmpty) &&
          (entreprise['email'] == null || entreprise['email'].toString().isEmpty))
        const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Text('Aucune information de contact disponible', style: TextStyle(color: Colors.grey)))),
    ]);
  }
}