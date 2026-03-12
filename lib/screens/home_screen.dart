import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int _currentIndex = 0;
  
  // Données API
  List<dynamic> _services = [];
  List<dynamic> _entreprises = [];
  List<dynamic> _domaines = [];
  String? _selectedDomaine;
  
  // États de chargement
  bool _isLoadingServices = true;
  bool _isLoadingEntreprises = true;
  bool _isLoadingDomaines = true;
  
  // Scroll controllers
  final ScrollController _serviceScrollController = ScrollController();
  
  // Timers pour le carrousel d'images
  final Map<int, Timer> _imageTimers = {};
  final Map<int, int> _currentImageIndex = {};

  // Recherche
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  FocusNode _searchFocusNode = FocusNode();
  List<dynamic> _searchResults = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
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
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    try {
      final token = await _storage.read(key: 'auth_token');
      
      // Recherche combinée
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/search?q=$query'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _searchResults = data;
        });
      }
    } catch (e) {
      print('Erreur recherche: $e');
    }
  }

  Future<void> _loadUserData() async {
    try {
      final userDataString = await _storage.read(key: 'user_data');
      if (userDataString != null) {
        setState(() {
          _userData = jsonDecode(userDataString);
        });
      }
    } catch (e) {
      print('Erreur chargement user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchData() async {
    await Future.wait([
      _fetchServices(),
      _fetchEntreprises(),
      _fetchDomaines(),
    ]);
  }

  Future<void> _fetchServices() async {
    setState(() => _isLoadingServices = true);
    
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/services'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      print('Services response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _services = data;
          _isLoadingServices = false;
        });
        
        for (int i = 0; i < data.length; i++) {
          _startImageCarousel(i);
        }
      } else {
        setState(() => _isLoadingServices = false);
      }
    } catch (e) {
      print('Erreur chargement services: $e');
      setState(() => _isLoadingServices = false);
    }
  }

  Future<void> _fetchEntreprises() async {
    setState(() => _isLoadingEntreprises = true);
    
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/entreprises'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      print('Entreprises response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _entreprises = data;
          _isLoadingEntreprises = false;
        });
      } else {
        setState(() => _isLoadingEntreprises = false);
      }
    } catch (e) {
      print('Erreur chargement entreprises: $e');
      setState(() => _isLoadingEntreprises = false);
    }
  }

  Future<void> _fetchDomaines() async {
    setState(() => _isLoadingDomaines = true);
    
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/domaines'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      print('Domaines response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _domaines = data;
          _domaines.insert(0, {'id': null, 'name': 'Tous'});
          _isLoadingDomaines = false;
        });
      } else {
        setState(() => _isLoadingDomaines = false);
      }
    } catch (e) {
      print('Erreur chargement domaines: $e');
      setState(() => _isLoadingDomaines = false);
    }
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
          int currentIndex = _currentImageIndex[serviceIndex] ?? 0;
          _currentImageIndex[serviceIndex] = ((currentIndex + 1) % medias.length).toInt();
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _logout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_data');
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  List<dynamic> get _filteredServices {
    if (_selectedDomaine == null || _selectedDomaine == 'Tous') {
      return _services;
    }
    return _services.where((s) {
      final domaine = s['domaine'] ?? {};
      return domaine['name'] == _selectedDomaine;
    }).toList();
  }

  void _showContactModal(Map<String, dynamic> service) async {
    final entreprise = service['entreprise'] ?? {};
    final whatsapp = entreprise['whatsapp_phone'] ?? '';
    final phone = entreprise['call_phone'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: AppConstants.primaryRed.withOpacity(0.1),
                        backgroundImage: entreprise['logo'] != null
                            ? NetworkImage(entreprise['logo'])
                            : null,
                        child: entreprise['logo'] == null
                            ? Icon(Icons.business, color: AppConstants.primaryRed)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service['name'] ?? 'Service',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entreprise['name'] ?? 'Entreprise',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Divider(),
                
                // Contact options
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (phone.isNotEmpty) ...[
                        _buildContactOption(
                          icon: Icons.phone,
                          iconColor: Colors.green,
                          title: 'Appeler',
                          subtitle: phone,
                          onTap: () async {
                            Navigator.pop(context);
                            final telUrl = 'tel:$phone';
                            if (await canLaunch(telUrl)) {
                              await launch(telUrl);
                            } else {
                              _showError('Impossible de passer l\'appel');
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      if (whatsapp.isNotEmpty) ...[
                        _buildContactOption(
                          icon: Icons.message,
                          iconColor: Colors.green,
                          title: 'WhatsApp',
                          subtitle: whatsapp,
                          onTap: () async {
                            Navigator.pop(context);
                            final cleanPhone = whatsapp.replaceAll('+', '').replaceAll(' ', '');
                            final whatsappUrl = 'https://wa.me/$cleanPhone';
                            if (await canLaunch(whatsappUrl)) {
                              await launch(whatsappUrl);
                            } else {
                              _showError('Impossible d\'ouvrir WhatsApp');
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      _buildContactOption(
                        icon: Icons.calendar_today,
                        iconColor: Colors.blue,
                        title: 'Prendre rendez-vous',
                        subtitle: 'Planifier un rendez-vous',
                        onTap: () {
                          Navigator.pop(context);
                          _showServiceDetails(service);
                        },
                      ),
                      const SizedBox(height: 12),
                      
                      _buildContactOption(
                        icon: Icons.info_outline,
                        iconColor: Colors.orange,
                        title: 'Voir détails',
                        subtitle: 'Plus d\'informations sur ce service',
                        onTap: () {
                          Navigator.pop(context);
                          _showServiceDetails(service);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContactOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  void _showServiceDetails(Map<String, dynamic> service) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ServiceDetailScreen(service: service),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = _userData?['name'] ?? 'Utilisateur';
    final userPhoto = _userData?['profile_photo_url'] ?? '';
    final hasEntreprise = _userData?['has_entreprise'] ?? false;
    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 360;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      
      // App Bar personnalisée
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        title: _isSearching
            ? Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _isSearching = false);
                      },
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              )
            : Row(
                children: [
                  // Logo
                  Container(
                    height: 32,
                    width: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.car_repair,
                          color: AppConstants.primaryRed,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CarEasy',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
        actions: [
          // Recherche
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                } else {
                  _isSearching = true;
                  _searchFocusNode.requestFocus();
                }
              });
            },
          ),
          // Notifications
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                onPressed: () => _showComingSoon('Notifications'),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  height: 8,
                  width: 8,
                  decoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          // Paramètres
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => _showComingSoon('Paramètres'),
          ),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              color: AppConstants.primaryRed,
              child: _isSearching && _searchController.text.isNotEmpty
                  ? _buildSearchResults()
                  : CustomScrollView(
                      controller: _serviceScrollController,
                      slivers: [
                        // Categories
                        SliverAppBar(
                          pinned: true,
                          floating: true,
                          elevation: 2,
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
                                      itemBuilder: (context, index) {
                                        final domaine = _domaines[index];
                                        final isSelected = _selectedDomaine == domaine['name'];
                                        
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: FilterChip(
                                            label: Text(
                                              domaine['name'] ?? '',
                                              style: TextStyle(
                                                color: isSelected ? Colors.white : Colors.black87,
                                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                fontSize: 13,
                                              ),
                                            ),
                                            selected: isSelected,
                                            onSelected: (selected) {
                                              setState(() {
                                                _selectedDomaine = selected ? domaine['name'] : null;
                                              });
                                            },
                                            backgroundColor: Colors.grey[100],
                                            selectedColor: AppConstants.primaryRed,
                                            checkmarkColor: Colors.white,
                                            elevation: isSelected ? 2 : 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(20),
                                              side: BorderSide(
                                                color: isSelected ? AppConstants.primaryRed : Colors.grey[300]!,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ),

                        // Contenu principal
                        SliverPadding(
                          padding: EdgeInsets.all(size.width * 0.04),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              // Section Services
                              _buildSectionHeader(
                                'Services populaires',
                                onSeeAll: () => _showComingSoon('Tous les services'),
                              ),
                              const SizedBox(height: 12),
                              
                              _isLoadingServices
                                  ? _buildServicesShimmer()
                                  : _filteredServices.isEmpty
                                      ? _buildEmptyState('Aucun service trouvé', Icons.search_off)
                                      : _buildServicesList(),
                              
                              const SizedBox(height: 24),
                              
                              // Section Entreprises
                              _buildSectionHeader(
                                'Entreprises',
                                onSeeAll: () => _showComingSoon('Toutes les entreprises'),
                              ),
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

      // Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.home, 'Accueil', 0),
                _buildNavItem(Icons.calendar_today, 'Rendez-vous', 1),
                _buildNavItem(
                  hasEntreprise ? Icons.business : Icons.add_business,
                  hasEntreprise ? 'Entreprise' : 'Créer',
                  2,
                ),
                _buildProfileNavItem(userName, userPhoto, 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Aucun résultat trouvé',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        final type = item['type'];
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.grey[200],
              backgroundImage: item['logo'] != null
                  ? NetworkImage(item['logo'])
                  : null,
              child: item['logo'] == null
                  ? Icon(type == 'service' ? Icons.build : Icons.business, size: 20)
                  : null,
            ),
            title: Text(item['name'] ?? ''),
            subtitle: Text(type == 'service' ? 'Service' : 'Entreprise'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              if (type == 'service') {
                _showServiceDetails(item);
              } else {
                _showComingSoon('Détails entreprise');
              }
            },
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
          if (index == 1) _showComingSoon('Rendez-vous');
          if (index == 2) _handleEntrepriseTap();
          if (index == 3) _showProfileDialog();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? AppConstants.primaryRed : Colors.grey,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? AppConstants.primaryRed : Colors.grey,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileNavItem(String userName, String userPhoto, int index) {
    final isSelected = _currentIndex == index;
    
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);
          _showProfileDialog();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundImage: userPhoto.isNotEmpty
                    ? NetworkImage(userPhoto)
                    : null,
                backgroundColor: Colors.grey[200],
                child: userPhoto.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 14,
                        color: Colors.grey[600],
                      )
                    : null,
              ),
              const SizedBox(height: 2),
              Text(
                userName.split(' ').first,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? AppConstants.primaryRed : Colors.grey,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: AppConstants.primaryRed,
              padding: EdgeInsets.zero,
              minimumSize: const Size(50, 30),
            ),
            child: const Text('Voir plus'),
          ),
      ],
    );
  }

  Widget _buildServicesList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredServices.length,
      itemBuilder: (context, index) {
        return _buildServiceCard(_filteredServices[index], index);
      },
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, int index) {
    final entreprise = service['entreprise'] ?? {};
    final hasPromo = service['has_promo'] ?? false;
    final isPromoActive = service['is_promo_active'] ?? false;
    final medias = service['medias'] is List ? service['medias'] : [];
    final currentImageIdx = _currentImageIndex[index] ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image carousel
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    color: Colors.grey[200],
                    child: medias.isNotEmpty
                        ? Image.network(
                            medias[currentImageIdx % medias.length],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Icon(
                                Icons.image_not_supported,
                                size: 40,
                                color: Colors.grey[400],
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.image_not_supported,
                              size: 40,
                              color: Colors.grey[400],
                            ),
                          ),
                  ),
                ),
                
                // Image indicators
                if (medias.length > 1)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        medias.length,
                        (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == currentImageIdx % medias.length
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Promo badge
                if (hasPromo && isPromoActive)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '-${service['discount_percentage'] ?? 0}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            
            // Service info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo entreprise
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: entreprise['logo'] != null
                            ? NetworkImage(entreprise['logo'])
                            : null,
                        child: entreprise['logo'] == null
                            ? Icon(
                                Icons.business,
                                size: 20,
                                color: Colors.grey[600],
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      
                      // Infos
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service['name'] ?? 'Service',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entreprise['name'] ?? 'Entreprise',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  service['is_always_open'] == true
                                      ? '24h/24'
                                      : service['start_time'] != null &&
                                              service['end_time'] != null
                                          ? '${service['start_time']} - ${service['end_time']}'
                                          : 'Horaires variables',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // Prix
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (service['is_price_on_request'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(12),
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
                          else if (hasPromo && isPromoActive)
                            Column(
                              children: [
                                Text(
                                  '${service['price_promo']} FCFA',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.primaryRed,
                                  ),
                                ),
                                Text(
                                  '${service['price']} FCFA',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                    decoration: TextDecoration.lineThrough,
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
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.primaryRed,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Boutons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showContactModal(service),
                          icon: const Icon(Icons.contact_phone, size: 16),
                          label: const Text('Contacter'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryRed,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showServiceDetails(service),
                          icon: const Icon(Icons.info_outline, size: 16),
                          label: const Text('Voir plus'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppConstants.primaryRed,
                            side: BorderSide(color: AppConstants.primaryRed),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
    );
  }

  Widget _buildEntreprisesList() {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _entreprises.length,
        itemBuilder: (context, index) {
          final entreprise = _entreprises[index];
          return _buildEntrepriseCard(entreprise);
        },
      ),
    );
  }

  Widget _buildEntrepriseCard(Map<String, dynamic> entreprise) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => _showComingSoon('Profil entreprise'),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: entreprise['logo'] != null &&
                          entreprise['logo'].toString().isNotEmpty
                      ? Image.network(
                          entreprise['logo'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                              Icons.business,
                              size: 30,
                              color: Colors.grey[400],
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.business,
                            size: 30,
                            color: Colors.grey[400],
                          ),
                        ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entreprise['name'] ?? 'Entreprise',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 12,
                          color: Colors.amber[600],
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '4.5',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: entreprise['status'] == 'validated'
                                ? Colors.green[50]
                                : Colors.orange[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entreprise['status'] == 'validated'
                                ? 'Validé'
                                : 'En attente',
                            style: TextStyle(
                              fontSize: 8,
                              color: entreprise['status'] == 'validated'
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _buildServicesShimmer() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Container(
          height: 200,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey[200]!,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 16,
                      width: 150,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 100,
                      color: Colors.grey[300],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntreprisesShimmer() {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        itemBuilder: (context, index) {
          return Container(
            width: 160,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey[200]!,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: 100,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 60,
                        color: Colors.grey[300],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(
              icon,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleEntrepriseTap() {
    final hasEntreprise = _userData?['has_entreprise'] ?? false;
    if (hasEntreprise) {
      _showComingSoon('Mon entreprise');
    } else {
      _showCreateEntrepriseDialog();
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Bientôt disponible'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCreateEntrepriseDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Créer une entreprise'),
        content: const Text(
          'Vous n\'avez pas encore d\'entreprise. Voulez-vous en créer une maintenant ?',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showComingSoon('Création entreprise');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              CircleAvatar(
                radius: 40,
                backgroundImage: _userData?['profile_photo_url'] != null
                    ? NetworkImage(_userData!['profile_photo_url'])
                    : null,
                backgroundColor: Colors.grey[200],
                child: _userData?['profile_photo_url'] == null
                    ? Icon(
                        Icons.person,
                        size: 40,
                        color: Colors.grey[400],
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                _userData?['name'] ?? 'Utilisateur',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _userData?['email'] ?? 'Email non renseigné',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              
              // Informations
              _buildInfoRow(Icons.email, 'Email', _userData?['email'] ?? 'Non renseigné'),
              _buildInfoRow(Icons.phone, 'Téléphone', _userData?['phone'] ?? 'Non renseigné'),
              _buildInfoRow(Icons.person, 'Rôle', _userData?['role'] ?? 'Client'),
              
              const SizedBox(height: 16),
              
              // Boutons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Fermer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _logout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Déconnexion'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// Nouvelle page de détails du service
class ServiceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> service;

  const ServiceDetailScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final entreprise = service['entreprise'] ?? {};
    final medias = service['medias'] is List ? service['medias'] : [];
    final hasPromo = service['has_promo'] ?? false;
    final isPromoActive = service['is_promo_active'] ?? false;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            stretch: true,
            backgroundColor: AppConstants.primaryRed,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Image
                  medias.isNotEmpty
                      ? Image.network(
                          medias[0],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: Colors.grey[300],
                            child: Center(
                              child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey[600]),
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: Center(
                            child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey[600]),
                          ),
                        ),
                  
                  // Gradient
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
                  
                  // Info overlay
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] ?? 'Service',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.white,
                              backgroundImage: entreprise['logo'] != null
                                  ? NetworkImage(entreprise['logo'])
                                  : null,
                              child: entreprise['logo'] == null
                                  ? Icon(Icons.business, size: 12, color: AppConstants.primaryRed)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entreprise['name'] ?? 'Entreprise',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Prix
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Prix',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (service['is_price_on_request'] == true)
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
                            ),
                          ),
                        )
                      else if (hasPromo && isPromoActive)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${service['price_promo']} FCFA',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.primaryRed,
                              ),
                            ),
                            Text(
                              '${service['price']} FCFA',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          service['price'] != null ? '${service['price']} FCFA' : '---',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryRed,
                          ),
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Description
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        service['descriptions'] ?? 'Aucune description disponible',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Horaires
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Horaires',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 20, color: AppConstants.primaryRed),
                          const SizedBox(width: 8),
                          Text(
                            service['is_always_open'] == true
                                ? 'Ouvert 24h/24'
                                : service['start_time'] != null && service['end_time'] != null
                                    ? '${service['start_time']} - ${service['end_time']}'
                                    : 'Horaires variables',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Contact
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Contact',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (entreprise['call_phone'] != null)
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.phone, color: Colors.green),
                          ),
                          title: const Text('Téléphone'),
                          subtitle: Text(entreprise['call_phone']),
                          onTap: () async {
                            final telUrl = 'tel:${entreprise['call_phone']}';
                            if (await canLaunch(telUrl)) {
                              await launch(telUrl);
                            }
                          },
                        ),
                      if (entreprise['whatsapp_phone'] != null)
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.message, color: Colors.green),
                          ),
                          title: const Text('WhatsApp'),
                          subtitle: Text(entreprise['whatsapp_phone']),
                          onTap: () async {
                            final cleanPhone = entreprise['whatsapp_phone'].replaceAll('+', '').replaceAll(' ', '');
                            final whatsappUrl = 'https://wa.me/$cleanPhone';
                            if (await canLaunch(whatsappUrl)) {
                              await launch(whatsappUrl);
                            }
                          },
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}