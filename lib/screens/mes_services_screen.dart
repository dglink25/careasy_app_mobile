import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:careasy_app_mobile/screens/create_service_screen.dart';
import 'package:careasy_app_mobile/screens/edit_service_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────
//  MesServicesScreen
//  Liste des services d'une entreprise validée
//  Accès : depuis MesEntreprisesScreen (bouton Créer un service)
//          ou depuis la nav bar profil
// ─────────────────────────────────────────────
class MesServicesScreen extends StatefulWidget {
  final Map<String, dynamic> entreprise;
  const MesServicesScreen({super.key, required this.entreprise});

  @override
  State<MesServicesScreen> createState() => _MesServicesScreenState();
}

class _MesServicesScreenState extends State<MesServicesScreen>
    with SingleTickerProviderStateMixin {
  // APRÈS
final _storage = const FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);
  List<dynamic> _services = [];
  bool _isLoading = true;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fetchServices();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── API ──────────────────────────────────────
  Future<void> _fetchServices() async {
    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/services/mine'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        // Filtrer par entreprise
        setState(() {
          _services = data
              .where((s) =>
                  s['entreprise']?['id']?.toString() ==
                  widget.entreprise['id']?.toString())
              .toList();
        });
        _animCtrl.forward(from: 0);
      }
    } catch (_) {
      _showSnack('Erreur de connexion', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteService(Map<String, dynamic> service) async {
    final confirmed = await _showDeleteDialog(service['name']);
    if (!confirmed) return;

    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.delete(
        Uri.parse('${AppConstants.apiBaseUrl}/services/${service['id']}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        _showSnack('Service supprimé avec succès');
        _fetchServices();
      } else {
        final data = jsonDecode(res.body);
        _showSnack(data['message'] ?? 'Erreur lors de la suppression',
            isError: true);
      }
    } catch (_) {
      _showSnack('Erreur de connexion', isError: true);
    }
  }

  Future<bool> _showDeleteDialog(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Supprimer le service'),
            content: Text(
                'Voulez-vous vraiment supprimer "$name" ? Cette action est irréversible.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler',
                    style: TextStyle(color: Colors.grey[600])),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[700] : Colors.green[700],
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── BUILD ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mes services',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              widget.entreprise['name'] ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchServices,
          ),
        ],
      ),
      body: _isLoading
          ? _buildShimmer()
          : _services.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _fetchServices,
                  color: AppConstants.primaryRed,
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _services.length,
                    itemBuilder: (_, i) {
                      final delay = i * 0.08;
                      return AnimatedBuilder(
                        animation: _animCtrl,
                        builder: (_, child) {
                          final t = (_animCtrl.value - delay)
                              .clamp(0.0, 1.0);
                          return Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - t)),
                              child: child,
                            ),
                          );
                        },
                        child: _buildServiceCard(_services[i]),
                      );
                    },
                  ),
                ),
        // APRÈS
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateServiceScreen(entreprise: widget.entreprise),
        ),
      ).then((_) => _fetchServices()),
        backgroundColor: AppConstants.primaryRed,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouveau service',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final medias = service['medias'] is List ? service['medias'] as List : [];
    final hasPromo =
        service['has_promo'] == true && service['is_promo_active'] == true;
    final isPriceOnRequest = service['is_price_on_request'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Image + infos
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Image miniature
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: medias.isNotEmpty
                        ? Image.network(medias.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _imgPlaceholder())
                        : _imgPlaceholder(),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Prix
                      if (isPriceOnRequest)
                        _priceBadge('Sur devis', Colors.blue)
                      else if (hasPromo)
                        Row(children: [
                          Text('${service['price_promo']} FCFA',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.primaryRed)),
                          const SizedBox(width: 6),
                          Text('${service['price']} FCFA',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                  decoration:
                                      TextDecoration.lineThrough)),
                        ])
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
                      const SizedBox(height: 4),
                      // Horaires
                      Row(children: [
                        Icon(Icons.access_time,
                            size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          service['is_always_open'] == true
                              ? '24h/24'
                              : (service['start_time'] != null &&
                                      service['end_time'] != null)
                                  ? '${service['start_time']} - ${service['end_time']}'
                                  : 'Horaires variables',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(height: 1, color: Colors.grey[100]),

          // Actions
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Nb médias
                if (medias.isNotEmpty) ...[
                  Icon(Icons.photo_library_outlined,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('${medias.length} photo(s)',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
                  const Spacer(),
                ] else
                  const Spacer(),

                // Bouton Modifier
                OutlinedButton.icon(
                  // APRÈS
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditServiceScreen(
                        service: service,
                        entreprise: widget.entreprise,
                      ),
                    ),
                  ).then((_) => _fetchServices()),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Modifier'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.primaryRed,
                    side: BorderSide(
                        color: AppConstants.primaryRed.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),

                // Bouton Supprimer
                OutlinedButton.icon(
                  onPressed: () => _deleteService(service),
                  icon:
                      const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Supprimer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(
                        color: Colors.red.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceBadge(String label, MaterialColor color) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color[700],
                fontWeight: FontWeight.w600)),
      );

  Widget _imgPlaceholder() => Container(
      color: Colors.grey[100],
      child:
          Icon(Icons.image_not_supported, size: 28, color: Colors.grey[400]));

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                    color: AppConstants.primaryRed.withOpacity(0.08),
                    shape: BoxShape.circle),
                child: const Icon(Icons.home_repair_service_outlined,
                    size: 44, color: AppConstants.primaryRed),
              ),
              const SizedBox(height: 20),
              const Text('Aucun service',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Commencez par créer votre premier service.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );

  Widget _buildShimmer() => ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (_, __) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ));
}