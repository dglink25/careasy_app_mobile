// lib/screens/service_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/rendez_vous_provider.dart';
import 'rendez_vous/create_rendez_vous_screen.dart';
import 'dart:convert';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

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

  // Formatage téléphone
  String _formatPhoneNumber(String phone) {
    if (phone.isEmpty) return '';
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('00')) return '+${cleaned.substring(2)}';
    if (cleaned.startsWith('0') && cleaned.length == 10) {
      return '+229${cleaned.substring(1)}';
    }
    if (cleaned.length == 8) return '+229$cleaned';
    if (cleaned.startsWith('229') && cleaned.length >= 11) return '+$cleaned';
    return cleaned;
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      final uri = Uri.parse('tel:${_formatPhoneNumber(phoneNumber)}');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'appel')),
        );
      }
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    try {
      final clean = _formatPhoneNumber(phoneNumber).replaceAll('+', '');
      final uri = Uri.parse('https://wa.me/$clean');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'ouverture de WhatsApp')),
        );
      }
    }
  }

  // Formatage des horaires pour le partage

  String _formatScheduleForShare() {
    Map<String, dynamic> schedule = {};
    final scheduleRaw = widget.service['schedule'];

    if (scheduleRaw != null) {
      if (scheduleRaw is String && scheduleRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(scheduleRaw);
          if (decoded is Map) {
            schedule = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      } else if (scheduleRaw is Map) {
        schedule = Map<String, dynamic>.from(scheduleRaw);
      }
    }

    const days = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    const dayNames = ['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'];

    if (widget.service['is_always_open'] == true || widget.service['is_open_24h'] == true) {
      return 'Ouvert 24h/24 et 7j/7';
    }

    if (schedule.isEmpty) {
      return 'Horaires non définis';
    }

    StringBuffer buffer = StringBuffer();

    for (int i = 0; i < days.length; i++) {
      final day = days[i];
      final daySchedule = schedule[day] is Map
          ? Map<String, dynamic>.from(schedule[day])
          : {};

      bool isOpen = daySchedule['is_open'] == true ||
          daySchedule['is_open'] == '1' ||
          daySchedule['is_open'] == 1;

      if (isOpen) {
        String start = daySchedule['start']?.toString().substring(0, 5) ?? '--:--';
        String end = daySchedule['end']?.toString().substring(0, 5) ?? '--:--';

        buffer.writeln('${dayNames[i]} : $start - $end');
      } else {
        buffer.writeln(' ${dayNames[i]} : Fermé');
      }
    }

    return buffer.toString().trim();
  }

  Future<void> _shareService() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    
    try {
      final serviceName = widget.service['name'] ?? 'Service';
      final entreprise = widget.service['entreprise'] is Map 
          ? Map<String, dynamic>.from(widget.service['entreprise']) 
          : {};
      final entrepriseName = entreprise['name'] ?? 'Entreprise';
      final entrepriseAddress = entreprise['address'] ?? 'Adresse non renseignée';
      final hasPromo = widget.service['has_promo'] ?? false;
      final isPromoActive = widget.service['is_promo_active'] ?? false;
      
      String priceText = '';
      if (widget.service['is_price_on_request'] == true) {
        priceText = 'Prix : Sur devis';
      } else if (hasPromo && isPromoActive) {
        final pricePromo = widget.service['price_promo'] ?? 0;
        final priceOriginal = widget.service['price'] ?? 0;
        final discount = widget.service['discount_percentage'] ?? 0;
        priceText = 'Prix : $priceOriginal FCFA → $pricePromo FCFA (-$discount%)';
      } else {
        final price = widget.service['price'] ?? 'Non défini';
        priceText = 'Prix : ${price != 'Non défini' ? '$price FCFA' : price}';
      }
      
      final description = widget.service['descriptions'] ?? 'Aucune description disponible';
      final scheduleText = _formatScheduleForShare();
      
      final callPhone = entreprise['call_phone'] ?? '';
      final whatsappPhone = entreprise['whatsapp_phone'] ?? '';
      
      String contactText = '';
      if (callPhone.isNotEmpty) contactText += '\nTéléphone : $callPhone';
      if (whatsappPhone.isNotEmpty) contactText += '\nWhatsApp : $whatsappPhone';
      
      final shareText = '''
$serviceName


Entreprise : $entrepriseName
Adresse : $entrepriseAddress
$priceText

Description :
$description

Horaires d'ouverture :
$scheduleText

Contact :$contactText

--- Trouvé sur CarEasy ---
Téléchargez l'application : https://careasy.app/download
      '''.trim();
      
      final medias = widget.service['medias'] is List ? widget.service['medias'] : [];
      XFile? imageFile;
      
      if (medias.isNotEmpty && medias.first != null && medias.first.toString().isNotEmpty) {
        try {
          final imageUrl = medias.first.toString();
          final uri = Uri.parse(imageUrl);
          final response = await http.get(uri);
          
          if (response.statusCode == 200) {
            final tempDir = await getTemporaryDirectory();
            final filePath = '${tempDir.path}/service_share_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final file = File(filePath);
            await file.writeAsBytes(response.bodyBytes);
            imageFile = XFile(filePath);
          }
        } catch (e) {
          debugPrint('Erreur téléchargement image: $e');
        }
      }
      
      if (imageFile != null) {
        await Share.shareXFiles([imageFile], text: shareText, subject: serviceName);
        final file = File(imageFile.path);
        if (await file.exists()) await file.delete();
      } else {
        await Share.share(shareText, subject: serviceName);
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du partage: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _navigateToCreateRdv() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => RendezVousProvider(),
          child: CreateRendezVousScreen(service: widget.service),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entreprise = widget.service['entreprise'] is Map
        ? Map<String, dynamic>.from(widget.service['entreprise'])
        : {};
    final medias = widget.service['medias'] is List ? widget.service['medias'] : [];
    final hasPromo = widget.service['has_promo'] ?? false;
    final isPromoActive = widget.service['is_promo_active'] ?? false;
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 380;

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
                  if (medias.isNotEmpty)
                    PageView.builder(
                      controller: _pageController,
                      itemCount: medias.length,
                      onPageChanged: (i) => setState(() => _currentImageIndex = i),
                      itemBuilder: (_, i) => Image.network(
                        medias[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[300],
                          child: Center(
                            child: Icon(Icons.broken_image, size: 50, color: Colors.grey[600]),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey[300],
                      child: Center(
                        child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey[600]),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                      ),
                    ),
                  ),
                  if (medias.length > 1)
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          medias.length,
                          (i) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _currentImageIndex
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                child: _isSharing
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.share, color: Colors.white),
                        onPressed: _shareService,
                      ),
              ),
            ],
          ),

          // Contenu principal
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Section prix et actions
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Section prix
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Prix',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
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
                          ),
                          // Icônes de contact
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
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
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
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Bouton rendez-vous
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _navigateToCreateRdv,
                          icon: const Icon(Icons.calendar_month, size: 20),
                          label: const Text(
                            'Prendre rendez-vous',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Onglets
                Container(
                  margin: const EdgeInsets.all(16),
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
                      SizedBox(
                        height: 280,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildDescriptionTab(),
                              _buildScheduleTab(),
                              _buildContactTab(Map<String, dynamic>.from(entreprise)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // À propos de l'entreprise
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'À propos de l\'entreprise',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                                    Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        entreprise['address'] ?? 'Adresse non renseignée',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionTab() {
    final description = widget.service['descriptions'] ?? 'Aucune description disponible';
    if (description.isEmpty || description == 'Aucune description disponible') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Aucune description disponible pour ce service',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Text(
        description,
        style: const TextStyle(fontSize: 14, height: 1.6),
      ),
    );
  }

  Widget _buildScheduleTab() {
    Map<String, dynamic> schedule = {};
    dynamic scheduleRaw = widget.service['schedule'];
    
    if (scheduleRaw != null) {
      if (scheduleRaw is String && scheduleRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(scheduleRaw);
          if (decoded is Map) schedule = Map<String, dynamic>.from(decoded);
        } catch (e) {
          debugPrint('Erreur décodage schedule: $e');
        }
      } else if (scheduleRaw is Map) {
        schedule = Map<String, dynamic>.from(scheduleRaw);
      }
    }
    
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    const dayNames = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    
    if (widget.service['is_always_open'] == true || widget.service['is_open_24h'] == true) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.all_inclusive, size: 50, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Disponible 24h/24 et 7j/7',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.green),
            ),
            SizedBox(height: 8),
            Text(
              'Service accessible à tout moment',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    if (schedule.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 50, color: Colors.orange),
            SizedBox(height: 16),
            Text(
              'Horaires non définis',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.orange),
            ),
            SizedBox(height: 8),
            Text(
              'Contacter le prestataire pour plus d\'informations',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return ListView.separated(
      itemCount: days.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final day = days[i];
        final daySchedule = schedule[day] is Map ? Map<String, dynamic>.from(schedule[day]) : {};
        
        bool isOpen = false;
        if (daySchedule.isNotEmpty) {
          final openValue = daySchedule['is_open'];
          isOpen = openValue == true || openValue == '1' || openValue == 1;
        }
        
        String start = '--:--';
        String end = '--:--';
        if (isOpen) {
          if (daySchedule['start'] != null) {
            start = daySchedule['start'].toString();
            if (start.length > 5) start = start.substring(0, 5);
          }
          if (daySchedule['end'] != null) {
            end = daySchedule['end'].toString();
            if (end.length > 5) end = end.substring(0, 5);
          }
        }
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  dayNames[i],
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOpen ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isOpen ? '$start - $end' : 'Fermé',
                    style: TextStyle(
                      color: isOpen ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
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
        if (entreprise['call_phone'] != null && entreprise['call_phone'].toString().isNotEmpty)
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.phone, color: Colors.green, size: 20),
            ),
            title: const Text('Téléphone', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(entreprise['call_phone']),
            trailing: IconButton(
              icon: const Icon(Icons.call, color: Colors.green),
              onPressed: () => _makePhoneCall(entreprise['call_phone']),
            ),
          ),
        if (entreprise['whatsapp_phone'] != null && entreprise['whatsapp_phone'].toString().isNotEmpty)
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.message, color: Color(0xFF25D366), size: 20),
            ),
            title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(entreprise['whatsapp_phone']),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_browser, color: Color(0xFF25D366)),
              onPressed: () => _openWhatsApp(entreprise['whatsapp_phone']),
            ),
          ),
        if (entreprise['email'] != null && entreprise['email'].toString().isNotEmpty)
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.email, color: Colors.blue, size: 20),
            ),
            title: const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(entreprise['email']),
            trailing: IconButton(
              icon: const Icon(Icons.send, color: Colors.blue),
              onPressed: () {},
            ),
          ),
        if ((entreprise['call_phone'] == null || entreprise['call_phone'].toString().isEmpty) &&
            (entreprise['whatsapp_phone'] == null || entreprise['whatsapp_phone'].toString().isEmpty) &&
            (entreprise['email'] == null || entreprise['email'].toString().isEmpty))
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Aucune information de contact disponible',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }
}