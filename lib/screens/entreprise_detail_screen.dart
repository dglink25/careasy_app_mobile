import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/screens/service_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class EntrepriseDetailScreen extends StatefulWidget {
  final Map<String, dynamic> entreprise;

  const EntrepriseDetailScreen({super.key, required this.entreprise});

  @override
  State<EntrepriseDetailScreen> createState() =>
      _EntrepriseDetailScreenState();
}

class _EntrepriseDetailScreenState extends State<EntrepriseDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _galleryController;
  int _currentGalleryIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _galleryController = PageController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _galleryController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  Helpers contacts
  // ─────────────────────────────────────────────
  String _formatPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.startsWith('+')) return phone;
    if (cleaned.startsWith('00')) return '+${cleaned.substring(2)}';
    if (cleaned.startsWith('229') && cleaned.length >= 11) return '+$cleaned';
    if (cleaned.startsWith('0') && cleaned.length == 10)
      return '+229${cleaned.substring(1)}';
    if (cleaned.length == 8) return '+229$cleaned';
    return '+229$cleaned';
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:${_formatPhone(phone)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp(String phone) async {
    final clean = _formatPhone(phone).replaceAll('+', '');
    final urls = [
      'https://wa.me/$clean',
      'whatsapp://send?phone=$clean',
    ];
    for (final u in urls) {
      final uri = Uri.parse(u);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    _showError('WhatsApp non disponible');
  }

  Future<void> _openMaps() async {
    final lat = widget.entreprise['latitude'];
    final lng = widget.entreprise['longitude'];
    final name = Uri.encodeComponent(widget.entreprise['name'] ?? '');
    if (lat == null || lng == null) {
      _showError('Coordonnées non disponibles');
      return;
    }
    final urls = [
      'google.navigation:q=$lat,$lng',
      'https://maps.google.com/?q=$lat,$lng&label=$name',
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    ];
    for (final u in urls) {
      final uri = Uri.parse(u);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    _showError('Impossible d\'ouvrir Google Maps');
  }

  Future<void> _share() async {
    final name = widget.entreprise['name'] ?? '';
    final address = widget.entreprise['google_formatted_address'] ??
        widget.entreprise['siege'] ??
        '';
    final phone = widget.entreprise['call_phone'] ?? '';
    final text =
        '📍 $name\n🏠 $address\n📞 $phone\n\nTrouvé sur CarEasy 🚗';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Infos copiées dans le presse-papiers !'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final e = widget.entreprise;
    final isValidated = e['status'] == 'validated';
    final logo = e['logo']?.toString() ?? '';
    final imageBoutique = e['image_boutique']?.toString() ?? '';
    final services = e['services'] as List? ?? [];
    final domaines = e['domaines'] as List? ?? [];
    final hasPhone = (e['call_phone'] ?? '').toString().isNotEmpty;
    final hasWhatsapp = (e['whatsapp_phone'] ?? '').toString().isNotEmpty;
    final hasLocation =
        e['latitude'] != null && e['longitude'] != null;

    // Galerie : image boutique + logo comme fallback
    final galleryImages = <String>[
      if (imageBoutique.isNotEmpty) imageBoutique,
      if (logo.isNotEmpty) logo,
    ];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // ────────────────────────────────────────
          //  SliverAppBar avec galerie
          // ────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true,
            backgroundColor: AppConstants.primaryRed,
            foregroundColor: Colors.white,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: _share,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Galerie photos
                  galleryImages.isNotEmpty
                      ? PageView.builder(
                          controller: _galleryController,
                          itemCount: galleryImages.length,
                          onPageChanged: (i) =>
                              setState(() => _currentGalleryIndex = i),
                          itemBuilder: (_, i) => Image.network(
                            galleryImages[i],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _headerPlaceholder(),
                          ),
                        )
                      : _headerPlaceholder(),

                  // Gradient sombre en bas
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.75),
                        ],
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),

                  // Indicateurs galerie
                  if (galleryImages.length > 1)
                    Positioned(
                      bottom: 78,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          galleryImages.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin:
                                const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _currentGalleryIndex ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _currentGalleryIndex
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Infos entreprise en bas de la photo
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        // Logo miniature
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: logo.isNotEmpty
                                ? Image.network(logo,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                          Icons.business,
                                          color: AppConstants.primaryRed,
                                        ))
                                : Icon(Icons.business,
                                    color: AppConstants.primaryRed),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e['name'] ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black26,
                                        blurRadius: 4)
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    isValidated
                                        ? Icons.verified
                                        : Icons.hourglass_empty,
                                    size: 14,
                                    color: isValidated
                                        ? Colors.greenAccent
                                        : Colors.orangeAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isValidated
                                        ? 'Entreprise vérifiée'
                                        : 'En attente de validation',
                                    style: TextStyle(
                                      color: isValidated
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ────────────────────────────────────────
          //  Boutons d'action rapides
          // ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  if (hasPhone)
                    Expanded(
                      child: _actionButton(
                        icon: Icons.phone,
                        label: 'Appeler',
                        color: Colors.green,
                        onTap: () =>
                            _call(e['call_phone']),
                      ),
                    ),
                  if (hasPhone && hasWhatsapp)
                    const SizedBox(width: 10),
                  if (hasWhatsapp)
                    Expanded(
                      child: _actionButton(
                        icon: Icons.chat,
                        label: 'WhatsApp',
                        color: const Color(0xFF25D366),
                        onTap: () =>
                            _whatsapp(e['whatsapp_phone']),
                      ),
                    ),
                  if ((hasPhone || hasWhatsapp) && hasLocation)
                    const SizedBox(width: 10),
                  if (hasLocation)
                    Expanded(
                      child: _actionButton(
                        icon: Icons.directions,
                        label: 'Itinéraire',
                        color: Colors.blue,
                        onTap: _openMaps,
                      ),
                    ),
                  if (!hasPhone && !hasWhatsapp && !hasLocation)
                    Expanded(
                      child: _actionButton(
                        icon: Icons.share,
                        label: 'Partager',
                        color: Colors.purple,
                        onTap: _share,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ────────────────────────────────────────
          //  Onglets
          // ────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: AppConstants.primaryRed,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppConstants.primaryRed,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: [
                  const Tab(text: 'Infos'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Services'),
                        if (services.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${services.length}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Tab(text: 'Contact'),
                ],
              ),
            ),
          ),

          // ────────────────────────────────────────
          //  Contenu des onglets
          // ────────────────────────────────────────
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInfosTab(e, domaines),
                _buildServicesTab(services),
                _buildContactTab(e),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Onglet Infos
  // ─────────────────────────────────────────────
  Widget _buildInfosTab(
      Map<String, dynamic> e, List<dynamic> domaines) {
    final address = e['google_formatted_address'] ??
        e['siege'] ??
        'Adresse non renseignée';
    final description =
        e['description']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          if (description.isNotEmpty) ...[
            _sectionTitle('À propos'),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Localisation
          _sectionTitle('Localisation'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _openMaps,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_on,
                        color: AppConstants.primaryRed, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(Icons.open_in_new,
                      size: 16, color: Colors.grey[400]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Domaines d'activité
          if (domaines.isNotEmpty) ...[
            _sectionTitle('Domaines d\'activité'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: domaines.map((d) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        AppConstants.primaryRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppConstants.primaryRed
                          .withOpacity(0.25),
                    ),
                  ),
                  child: Text(
                    d['name'] ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppConstants.primaryRed,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Infos légales
          _sectionTitle('Informations légales'),
          const SizedBox(height: 8),
          _legalRow('N° IFU',
              e['ifu_number']?.toString() ?? 'Non renseigné'),
          _legalRow('N° RCCM',
              e['rccm_number']?.toString() ?? 'Non renseigné'),
          _legalRow('PDG',
              e['pdg_full_name']?.toString() ?? 'Non renseigné'),
          _legalRow('Rôle',
              e['role_user']?.toString() ?? 'Non renseigné'),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Onglet Services
  // ─────────────────────────────────────────────
  Widget _buildServicesTab(List<dynamic> services) {
    if (services.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_repair_service,
                size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Aucun service disponible',
              style: TextStyle(
                  fontSize: 15, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: services.length,
      itemBuilder: (_, i) => _buildServiceRow(services[i]),
    );
  }

  Widget _buildServiceRow(Map<String, dynamic> service) {
    final medias = service['medias'] is List
        ? service['medias'] as List
        : [];
    final hasPromo = service['has_promo'] == true &&
        service['is_promo_active'] == true;
    final isPriceOnRequest =
        service['is_price_on_request'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ServiceDetailScreen(service: service),
          ),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 70,
                  height: 70,
                  child: medias.isNotEmpty
                      ? Image.network(
                          medias.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _imgPlaceholder(),
                        )
                      : _imgPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 11,
                            color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          service['is_always_open'] == true
                              ? '24h/24'
                              : (service['start_time'] != null &&
                                      service['end_time'] !=
                                          null)
                                  ? '${service['start_time']} - ${service['end_time']}'
                                  : 'Horaires variables',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (isPriceOnRequest)
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Sur devis',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else if (hasPromo)
                          Row(
                            children: [
                              Text(
                                '${service['price_promo']} F',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.primaryRed,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${service['price']} F',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[400],
                                  decoration:
                                      TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            service['price'] != null
                                ? '${service['price']} FCFA'
                                : '---',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.primaryRed,
                            ),
                          ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios,
                            size: 13,
                            color: Colors.grey[400]),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Onglet Contact
  // ─────────────────────────────────────────────
  Widget _buildContactTab(Map<String, dynamic> e) {
    final hasPhone =
        (e['call_phone'] ?? '').toString().isNotEmpty;
    final hasWhatsapp =
        (e['whatsapp_phone'] ?? '').toString().isNotEmpty;
    final hasEmail =
        (e['email'] ?? '').toString().isNotEmpty;
    final hasLocation =
        e['latitude'] != null && e['longitude'] != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (hasPhone)
            _contactTile(
              icon: Icons.phone,
              color: Colors.green,
              title: 'Téléphone',
              subtitle: e['call_phone'],
              onTap: () => _call(e['call_phone']),
              actionIcon: Icons.call,
            ),
          if (hasWhatsapp)
            _contactTile(
              icon: Icons.chat,
              color: const Color(0xFF25D366),
              title: 'WhatsApp',
              subtitle: e['whatsapp_phone'],
              onTap: () => _whatsapp(e['whatsapp_phone']),
              actionIcon: Icons.open_in_new,
            ),
          if (hasEmail)
            _contactTile(
              icon: Icons.email,
              color: Colors.blue,
              title: 'Email',
              subtitle: e['email'],
              onTap: () async {
                final uri =
                    Uri.parse('mailto:${e['email']}');
                if (await canLaunchUrl(uri))
                  await launchUrl(uri);
              },
              actionIcon: Icons.send,
            ),
          if (hasLocation)
            _contactTile(
              icon: Icons.location_on,
              color: AppConstants.primaryRed,
              title: 'Adresse',
              subtitle: e['google_formatted_address'] ??
                  e['siege'] ??
                  '${e['latitude']}, ${e['longitude']}',
              onTap: _openMaps,
              actionIcon: Icons.directions,
            ),
          const SizedBox(height: 20),
          // Bouton Partager
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: const Text('Partager cette entreprise'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppConstants.primaryRed,
                side: const BorderSide(
                    color: AppConstants.primaryRed),
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Widgets helpers
  // ─────────────────────────────────────────────
  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required IconData actionIcon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style:
                TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: IconButton(
          icon: Icon(actionIcon, color: color, size: 20),
          onPressed: onTap,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _legalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Center(
        child: Icon(Icons.business,
            size: 60, color: Colors.grey[500]),
      ),
    );
  }

  Widget _imgPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: Icon(Icons.image_not_supported,
          size: 28, color: Colors.grey[400]),
    );
  }
}

// ─────────────────────────────────────────────
//  Delegate pour TabBar sticky
// ─────────────────────────────────────────────
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  const _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}