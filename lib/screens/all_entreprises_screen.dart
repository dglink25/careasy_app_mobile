import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:careasy_app_mobile/screens/service_detail_screen.dart';
import 'package:careasy_app_mobile/screens/entreprise_detail_screen.dart';


class AllEntreprisesScreen extends StatefulWidget {
  final List<dynamic> initialEntreprises;
  final List<dynamic> initialDomaines;

  const AllEntreprisesScreen({
    super.key,
    required this.initialEntreprises,
    required this.initialDomaines,
  });

  @override
  State<AllEntreprisesScreen> createState() => _AllEntreprisesScreenState();
}

class _AllEntreprisesScreenState extends State<AllEntreprisesScreen> {
  final _storage = const FlutterSecureStorage();

  // ── Données ──────────────────────────────────
  List<dynamic> _entreprises = [];
  List<dynamic> _domaines = [];
  bool _isLoading = false;

  // ── Filtre domaine ───────────────────────────
  String? _selectedDomaine;

  // ── Recherche ────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _entreprises = List.from(widget.initialEntreprises);
    _domaines = List.from(widget.initialDomaines);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/entreprises'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        setState(() => _entreprises = data);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _processed {
    List<dynamic> list = List.from(_entreprises);

    // 1. Filtre domaine
    if (_selectedDomaine != null && _selectedDomaine != 'Tous') {
      list = list.where((e) {
        final domaines = e['domaines'] as List? ?? [];
        return domaines.any((d) => d['name'] == _selectedDomaine);
      }).toList();
    }

    // 2. Recherche texte
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) {
        final name = (e['name'] ?? '').toString().toLowerCase();
        final desc = (e['description'] ?? '').toString().toLowerCase();
        final siege = (e['siege'] ?? '').toString().toLowerCase();
        return name.contains(q) || desc.contains(q) || siege.contains(q);
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final results = _processed;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildDomainFilters(),
          _buildResultCount(results.length),

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
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: results.length,
                            itemBuilder: (_, i) =>
                                _buildCompactCard(results[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }


  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppConstants.primaryRed,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Toutes les entreprises',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }


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
            hintText: 'Rechercher une entreprise…',
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            prefixIcon:
                Icon(Icons.search, color: Colors.grey[500], size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon:
                        Icon(Icons.close, color: Colors.grey[500], size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }


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
          final name = _domaines[i]['name'] ?? '';
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
                  ),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: selected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildResultCount(int count) {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Text(
            '$count entreprise${count > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // Indicateur filtre actif
          if (_selectedDomaine != null && _selectedDomaine != 'Tous')
            GestureDetector(
              onTap: () => setState(() => _selectedDomaine = null),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppConstants.primaryRed.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_list,
                        size: 12, color: AppConstants.primaryRed),
                    const SizedBox(width: 4),
                    Text(
                      _selectedDomaine!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppConstants.primaryRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.close,
                        size: 12, color: AppConstants.primaryRed),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildCompactCard(Map<String, dynamic> entreprise) {
    final isValidated = entreprise['status'] == 'validated';
    final domaines = entreprise['domaines'] as List? ?? [];
    final services = entreprise['services'] as List? ?? [];
    final logo = entreprise['logo']?.toString() ?? '';
    final address = entreprise['google_formatted_address'] ??
        entreprise['siege'] ??
        '';

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
        onTap: () => _showEntrepriseDetail(entreprise),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Logo ────────────────────────────
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 70,
                      height: 70,
                      child: logo.isNotEmpty
                          ? Image.network(
                              logo,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _logoPlaceholder(),
                            )
                          : _logoPlaceholder(),
                    ),
                  ),
                  // Badge statut
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        isValidated
                            ? Icons.verified
                            : Icons.hourglass_empty,
                        size: 14,
                        color: isValidated
                            ? Colors.green[600]
                            : Colors.orange[600],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nom + badge statut texte
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entreprise['name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isValidated
                                ? Colors.green[50]
                                : Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isValidated ? 'Validé' : 'En attente',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isValidated
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Adresse
                    if (address.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              size: 11, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 4),

                    // Domaines chips
                    if (domaines.isNotEmpty)
                      SizedBox(
                        height: 20,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: domaines.length > 3
                              ? 3
                              : domaines.length,
                          itemBuilder: (_, i) {
                            final isLast = i == 2 &&
                                domaines.length > 3;
                            return Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppConstants.primaryRed
                                    .withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isLast
                                    ? '+${domaines.length - 2}'
                                    : (domaines[i]['name'] ?? ''),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppConstants.primaryRed,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        Icon(Icons.build_circle_outlined,
                            size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          '${services.length} service${services.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios,
                            size: 12, color: Colors.grey[400]),
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

  Widget _logoPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: Icon(Icons.business, size: 30, color: Colors.grey[400]),
    );
  }

  void _showEntrepriseDetail(Map<String, dynamic> entreprise) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => EntrepriseDetailScreen(entreprise: entreprise),
    ),
  );
}

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: Colors.grey[600]),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


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
              hasFilters ? Icons.search_off : Icons.business_outlined,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'Aucun résultat'
                  : 'Aucune entreprise disponible',
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
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
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
                  side: const BorderSide(color: AppConstants.primaryRed),
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