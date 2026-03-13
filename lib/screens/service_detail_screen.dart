import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

class ServiceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> service;

  const ServiceDetailScreen({super.key, required this.service});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentImageIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pageController = PageController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    
    if (cleaned.startsWith('+')) {
      return cleaned;
    }
    if (cleaned.startsWith('00')) {
      return '+' + cleaned.substring(2);
    }
    if (cleaned.startsWith('0') && cleaned.length == 10) {
      return '+229' + cleaned.substring(1);
    }
    if (cleaned.length == 8) {
      return '+229' + cleaned;
    }
    if (cleaned.startsWith('229') && cleaned.length == 11) {
      return '+' + cleaned;
    }
    return cleaned;
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      final formattedNumber = _formatPhoneNumber(phoneNumber);
      final telUrl = 'tel:$formattedNumber';
      if (await canLaunch(telUrl)) {
        await launch(telUrl);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'appel')),
      );
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    try {
      final formattedNumber = _formatPhoneNumber(phoneNumber).replaceAll('+', '');
      final whatsappUrl = 'https://wa.me/$formattedNumber';
      if (await canLaunch(whatsappUrl)) {
        await launch(whatsappUrl);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'ouverture de WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entreprise = widget.service['entreprise'] ?? {};
    final medias = widget.service['medias'] is List ? widget.service['medias'] : [];
    final hasPromo = widget.service['has_promo'] ?? false;
    final isPromoActive = widget.service['is_promo_active'] ?? false;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // App Bar avec image
          SliverAppBar(
            expandedHeight: size.height * 0.4,
            pinned: true,
            stretch: true,
            backgroundColor: AppConstants.primaryRed,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Image carousel
                  if (medias.isNotEmpty)
                    PageView.builder(
                      controller: _pageController,
                      itemCount: medias.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentImageIndex = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        return Image.network(
                          medias[index],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[300],
                              child: Center(
                                child: Icon(
                                  Icons.broken_image,
                                  size: 50,
                                  color: Colors.grey[600],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    )
                  else
                    Container(
                      color: Colors.grey[300],
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported,
                          size: 50,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                  
                  // Image indicators
                  if (medias.length > 1)
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          medias.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index == _currentImageIndex
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  
                  // Service info overlay
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.service['name'] ?? 'Service',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                image: entreprise['logo'] != null
                                    ? DecorationImage(
                                        image: NetworkImage(entreprise['logo']),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: entreprise['logo'] == null
                                  ? Icon(Icons.business, size: 16, color: AppConstants.primaryRed)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entreprise['name'] ?? 'Entreprise',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
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
                  onPressed: () {
                    // Partager le service
                  },
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.favorite_border, color: Colors.white),
                  onPressed: () {
                    // Ajouter aux favoris
                  },
                ),
              ),
            ],
          ),
          
          // Contenu principal
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Prix et actions rapides
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Prix',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (widget.service['is_price_on_request'] == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Sur devis',
                                    style: TextStyle(
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                              else if (hasPromo && isPromoActive)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '${widget.service['price_promo']} FCFA',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: AppConstants.primaryRed,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.red[50],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '-${widget.service['discount_percentage'] ?? 0}%',
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${widget.service['price']} FCFA',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[500],
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  widget.service['price'] != null 
                                      ? '${widget.service['price']} FCFA' 
                                      : 'Prix non défini',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.primaryRed,
                                  ),
                                ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.phone, color: Colors.green),
                                  onPressed: entreprise['call_phone'] != null
                                      ? () => _makePhoneCall(entreprise['call_phone'])
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.message, color: Color(0xFF25D366)),
                                  onPressed: entreprise['whatsapp_phone'] != null
                                      ? () => _openWhatsApp(entreprise['whatsapp_phone'])
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                // Prendre rendez-vous
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConstants.primaryRed,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: const Text(
                                'Prendre rendez-vous',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Onglets
                Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        labelColor: AppConstants.primaryRed,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: AppConstants.primaryRed,
                        indicatorSize: TabBarIndicatorSize.label,
                        tabs: const [
                          Tab(text: 'Description'),
                          Tab(text: 'Horaires'),
                          Tab(text: 'Contact'),
                        ],
                      ),
                      Container(
                        height: 300,
                        padding: const EdgeInsets.all(16),
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Onglet Description
                            _buildDescriptionTab(),
                            
                            // Onglet Horaires
                            _buildScheduleTab(),
                            
                            // Onglet Contact
                            _buildContactTab(entreprise),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Entreprise info
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'À propos de l\'entreprise',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(15),
                              image: entreprise['logo'] != null
                                  ? DecorationImage(
                                      image: NetworkImage(entreprise['logo']),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: entreprise['logo'] == null
                                ? Icon(Icons.business, size: 30, color: Colors.grey[400])
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entreprise['name'] ?? 'Entreprise',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        entreprise['address'] ?? 'Adresse non renseignée',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
    );
  }

  Widget _buildDescriptionTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.service['descriptions'] ?? 'Aucune description disponible',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTab() {
    final schedule = widget.service['schedule'] is Map ? widget.service['schedule'] : {};
    final days = [
      'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
    ];
    final dayNames = [
      'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
    ];

    if (widget.service['is_always_open'] == true) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 50, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Ouvert 24h/24',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: days.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final day = days[index];
        final daySchedule = schedule[day] ?? {'is_open': false};
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  dayNames[index],
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: daySchedule['is_open'] == true
                    ? Text(
                        '${daySchedule['start']} - ${daySchedule['end']}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : const Text(
                        'Fermé',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContactTab(Map<String, dynamic> entreprise) {
    return ListView(
      children: [
        if (entreprise['call_phone'] != null)
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phone, color: Colors.green),
            ),
            title: const Text('Téléphone'),
            subtitle: Text(entreprise['call_phone']),
            trailing: IconButton(
              icon: const Icon(Icons.call),
              onPressed: () => _makePhoneCall(entreprise['call_phone']),
            ),
          ),
        if (entreprise['whatsapp_phone'] != null)
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.message, color: Color(0xFF25D366)),
            ),
            title: const Text('WhatsApp'),
            subtitle: Text(entreprise['whatsapp_phone']),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => _openWhatsApp(entreprise['whatsapp_phone']),
            ),
          ),
        if (entreprise['email'] != null)
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.email, color: Colors.blue),
            ),
            title: const Text('Email'),
            subtitle: Text(entreprise['email']),
            trailing: IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {
                // Envoyer un email
              },
            ),
          ),
      ],
    );
  }
}