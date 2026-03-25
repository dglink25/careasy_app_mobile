import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:careasy_app_mobile/screens/service_detail_screen.dart';
import 'package:careasy_app_mobile/screens/home_screen.dart';


enum SortOption {
  newest,
  priceAsc,
  priceDesc,
  nameAsc,
  topRated, 
}

extension SortOptionLabel on SortOption {
  String get label {
    switch (this) {
      case SortOption.newest:
        return 'Plus récents';
      case SortOption.priceAsc:
        return 'Prix croissant';
      case SortOption.priceDesc:
        return 'Prix décroissant';
      case SortOption.nameAsc:
        return 'Nom (A → Z)';
      case SortOption.topRated:  return 'Mieux recommandé';
    }
  }

  IconData get icon {
    switch (this) {
      case SortOption.newest:
        return Icons.schedule;
      case SortOption.priceAsc:
        return Icons.arrow_upward;
      case SortOption.priceDesc:
        return Icons.arrow_downward;
      case SortOption.nameAsc:
        return Icons.sort_by_alpha;
      case SortOption.topRated:  return Icons.star;  
    }
  }
}

// ─────────────────────────────────────────────
//  AllServicesScreen
// ─────────────────────────────────────────────
class AllServicesScreen extends StatefulWidget {
  /// Données pré-chargées depuis le HomeScreen (évite un double appel réseau)
  final List<dynamic> initialServices;
  final List<dynamic> initialDomaines;

  const AllServicesScreen({
    super.key,
    required this.initialServices,
    required this.initialDomaines,
  });

  @override
  State<AllServicesScreen> createState() => _AllServicesScreenState();
}

class _AllServicesScreenState extends State<AllServicesScreen> {
  final _storage = const FlutterSecureStorage();

  // ── Données ──────────────────────────────────
  List<dynamic> _services = [];
  List<dynamic> _domaines = [];
  bool _isLoading = false;

  // ── Filtres & tri ────────────────────────────
  String? _selectedDomaine;
  SortOption _sortOption = SortOption.newest;

  // ── Recherche ────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  String _searchQuery = '';

  // ── Carrousel images ─────────────────────────
  final Map<int, Timer> _imageTimers = {};
  final Map<int, int> _currentImageIndex = {};

  @override
  void initState() {
    super.initState();
    _services = List.from(widget.initialServices);
    _domaines = List.from(widget.initialDomaines);
    _searchController.addListener(_onSearchChanged);
    // Démarre les carrousels
    for (int i = 0; i < _services.length; i++) {
      _startImageCarousel(i);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _imageTimers.forEach((_, t) => t.cancel());
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  Carrousel
  // ─────────────────────────────────────────────
  void _startImageCarousel(int idx) {
    if (idx >= _services.length) return;
    final medias = _services[idx]['medias'];
    if (medias is! List || medias.length <= 1) return;
    _currentImageIndex[idx] = 0;
    _imageTimers[idx] = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && idx < _services.length) {
        setState(() {
          _currentImageIndex[idx] =
              ((_currentImageIndex[idx] ?? 0) + 1) % medias.length;
        });
      }
    });
  }

  // ─────────────────────────────────────────────
  //  Recherche avec debounce
  // ─────────────────────────────────────────────
  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  // ─────────────────────────────────────────────
  //  Rafraîchissement
  // ─────────────────────────────────────────────
  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/services'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        _imageTimers.forEach((_, t) => t.cancel());
        _imageTimers.clear();
        _currentImageIndex.clear();
        setState(() => _services = data);
        for (int i = 0; i < data.length; i++) {
          _startImageCarousel(i);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────
  //  Pipeline filtre + tri
  // ─────────────────────────────────────────────
  List<dynamic> get _processed {
    List<dynamic> list = List.from(_services);

    // 1. Filtre domaine
    if (_selectedDomaine != null && _selectedDomaine != 'Tous') {
      list = list.where((s) {
        final d = s['domaine'] ?? {};
        return d['name'] == _selectedDomaine;
      }).toList();
    }

    // 2. Filtre recherche
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final desc = (s['descriptions'] ?? '').toString().toLowerCase();
        final ent = (s['entreprise']?['name'] ?? '').toString().toLowerCase();
        return name.contains(q) || desc.contains(q) || ent.contains(q);
      }).toList();
    }

    // 3. Tri

    list.sort((a, b) {
      switch (_sortOption) {
        case SortOption.priceAsc:
          final pa = _parsePrice(a);
          final pb = _parsePrice(b);
          if (pa == null && pb == null) return 0;
          if (pa == null) return 1;
          if (pb == null) return -1;
          return pa.compareTo(pb);
        case SortOption.priceDesc:
          final pa = _parsePrice(a);
          final pb = _parsePrice(b);
          if (pa == null && pb == null) return 0;
          if (pa == null) return 1;
          if (pb == null) return -1;
          return pb.compareTo(pa);
        case SortOption.nameAsc:
          return (a['name'] ?? '').toString().compareTo(
                (b['name'] ?? '').toString());
        case SortOption.topRated: // ⭐ NOUVEAU
          final ra = (a['total_stars'] ?? 0) as int;
          final rb = (b['total_stars'] ?? 0) as int;
          return rb.compareTo(ra);
        case SortOption.newest:
          return 0;
      }
    });

    return list;
  }

  double? _parsePrice(dynamic service) {
    if (service['is_price_on_request'] == true) return null;
    final hasPromo = service['has_promo'] == true &&
        service['is_promo_active'] == true;
    final raw = hasPromo ? service['price_promo'] : service['price'];
    if (raw == null) return null;
    return double.tryParse(raw.toString());
  }

  // ─────────────────────────────────────────────
  //  Bottom sheet : options de tri
  // ─────────────────────────────────────────────
  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Trier par',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...SortOption.values.map((opt) {
              final selected = _sortOption == opt;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppConstants.primaryRed.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    opt.icon,
                    size: 18,
                    color: selected ? AppConstants.primaryRed : Colors.grey[600],
                  ),
                ),
                title: Text(
                  opt.label,
                  style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? AppConstants.primaryRed
                        : Colors.black87,
                  ),
                ),
                trailing: selected
                    ? const Icon(Icons.check_circle,
                        color: AppConstants.primaryRed, size: 20)
                    : null,
                onTap: () {
                  setState(() => _sortOption = opt);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final results = _processed;
    final activeFilters =
        (_selectedDomaine != null && _selectedDomaine != 'Tous' ? 1 : 0) +
            (_sortOption != SortOption.newest ? 1 : 0);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(activeFilters),
      body: Column(
        children: [
          // ── Barre de recherche ──────────────────
          _buildSearchBar(),

          // ── Filtres domaines ────────────────────
          _buildDomainFilters(),

          // ── Compteur résultats ──────────────────
          _buildResultCount(results.length),

          // ── Liste des services ──────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppConstants.primaryRed,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    color: AppConstants.primaryRed,
                    child: results.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              // On retrouve l'index dans _services pour le carrousel
                              final globalIdx = _services.indexOf(results[i]);
                              return _buildCompactServiceCard(
                                results[i],
                                globalIdx >= 0 ? globalIdx : i,
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  AppBar
  // ─────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(int activeFilters) {
    return AppBar(
      backgroundColor: AppConstants.primaryRed,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Tous les services',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      actions: [
        // Bouton tri avec badge si filtre actif
        Stack(
          alignment: Alignment.topRight,
          children: [
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Trier',
              onPressed: _showSortSheet,
            ),
            if (activeFilters > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  Barre de recherche
  // ─────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      color: AppConstants.primaryRed,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Rechercher un service, une entreprise…',
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            prefixIcon:
                Icon(Icons.search, color: Colors.grey[500], size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close,
                        color: Colors.grey[500], size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Filtres domaines
  // ─────────────────────────────────────────────
  Widget _buildDomainFilters() {
    return Container(
      height: 52,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _domaines.length,
        itemBuilder: (_, i) {
          final d = _domaines[i];
          final name = d['name'] ?? '';
          final selected = _selectedDomaine == name ||
              (i == 0 &&
                  (_selectedDomaine == null || _selectedDomaine == 'Tous'));

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedDomaine = (i == 0) ? null : name;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? AppConstants.primaryRed
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? AppConstants.primaryRed
                        : Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color:
                        selected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Compteur résultats + tri actif
  // ─────────────────────────────────────────────
  Widget _buildResultCount(int count) {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Text(
            '$count service${count > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (_sortOption != SortOption.newest)
            GestureDetector(
              onTap: _showSortSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color:
                        AppConstants.primaryRed.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sortOption.icon,
                        size: 12,
                        color: AppConstants.primaryRed),
                    const SizedBox(width: 4),
                    Text(
                      _sortOption.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppConstants.primaryRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.close,
                        size: 12,
                        color: AppConstants.primaryRed),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Carte service compacte
  // ─────────────────────────────────────────────
  Widget _buildCompactServiceCard(
      Map<String, dynamic> service, int idx) {
    final entreprise = service['entreprise'] ?? {};
    final hasPromo =
        service['has_promo'] == true && service['is_promo_active'] == true;
    final medias = service['medias'] is List ? service['medias'] : [];
    final imgIdx = _currentImageIndex[idx] ?? 0;
    final isPriceOnRequest = service['is_price_on_request'] == true;

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
            builder: (_) => ServiceDetailScreen(service: service),
          ),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // ── Miniature image ─────────────────
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: medias.isNotEmpty
                          ? Image.network(
                              medias[imgIdx % medias.length],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _imagePlaceholder(),
                            )
                          : _imagePlaceholder(),
                    ),
                  ),
                  // Badge promo
                  if (hasPromo)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '-${service['discount_percentage'] ?? 0}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 12),

              // ── Infos ───────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nom service
                    Text(
                      service['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 3),

                    // Nom entreprise
                    Row(
                      children: [
                        Icon(Icons.business,
                            size: 11, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            entreprise['name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 3),

                    // Horaires
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 11, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          service['is_always_open'] == true
                              ? '24h/24'
                              : (service['start_time'] != null &&
                                      service['end_time'] != null)
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

                    // Prix + bouton
                    Row(
                      children: [
                        // Prix
                        if (isPriceOnRequest)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
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

                        // Bouton Voir
                        SizedBox(
                          height: 28,
                          child: ElevatedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ServiceDetailScreen(service: service),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.primaryRed,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            child: const Text('Voir'),
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

  Widget _imagePlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Icon(Icons.image_not_supported,
          size: 28, color: Colors.grey[400]),
    );
  }

  // ─────────────────────────────────────────────
  //  État vide
  // ─────────────────────────────────────────────
  Widget _buildEmptyState() {
    final hasFilters = _searchQuery.isNotEmpty ||
        (_selectedDomaine != null && _selectedDomaine != 'Tous');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasFilters ? Icons.search_off : Icons.home_repair_service,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'Aucun résultat'
                  : 'Aucun service disponible',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Essayez d\'autres filtres ou mots-clés'
                  : 'Revenez plus tard',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
            if (hasFilters) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _selectedDomaine = null;
                  });
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Réinitialiser les filtres'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.primaryRed,
                  side:
                      const BorderSide(color: AppConstants.primaryRed),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}