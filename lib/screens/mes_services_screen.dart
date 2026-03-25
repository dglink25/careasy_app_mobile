import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:careasy_app_mobile/screens/create_service_screen.dart';
import 'package:careasy_app_mobile/screens/edit_service_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MesServicesScreen extends StatefulWidget {
  final Map<String, dynamic> entreprise;
  const MesServicesScreen({super.key, required this.entreprise});

  @override
  State<MesServicesScreen> createState() => _MesServicesScreenState();
}

class _MesServicesScreenState extends State<MesServicesScreen>
    with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  
  List<dynamic> _services = [];
  bool _isLoading = true;
  late AnimationController _animCtrl;
  Map<int, bool> _updatingVisibility = {};

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

  Future<void> _toggleVisibility(Map<String, dynamic> service, bool newValue) async {
    final serviceId = service['id'];
    setState(() {
      _updatingVisibility[serviceId] = true;
    });

    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.patch(
        Uri.parse('${AppConstants.apiBaseUrl}/services/${serviceId}/toggle-visibility'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'is_visibility': newValue}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          final index = _services.indexWhere((s) => s['id'] == serviceId);
          if (index != -1) {
            _services[index]['is_visibility'] = data['is_visibility'];
          }
        });
        _showSnack(
          newValue 
            ? 'Service visible pour les clients' 
            : 'Service masqué. Les clients ne pourront plus le voir',
          isError: false,
        );
      } else {
        _showSnack('Erreur lors de la mise à jour', isError: true);
      }
    } catch (e) {
      _showSnack('Erreur de connexion', isError: true);
    } finally {
      setState(() {
        _updatingVisibility[serviceId] = false;
      });
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── BUILD ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 380;

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
            const Text(
              'Mes services',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              widget.entreprise['name'] ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
          ? _buildShimmer(isSmallScreen)
          : _services.isEmpty
              ? _buildEmpty(isSmallScreen)
              : RefreshIndicator(
                  onRefresh: _fetchServices,
                  color: AppConstants.primaryRed,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                        isSmallScreen ? 12 : 16, 
                        isSmallScreen ? 12 : 16, 
                        isSmallScreen ? 12 : 16, 
                        100),
                    itemCount: _services.length,
                    itemBuilder: (_, i) {
                      final delay = i * 0.08;
                      return AnimatedBuilder(
                        animation: _animCtrl,
                        builder: (_, child) {
                          final t = (_animCtrl.value - delay).clamp(0.0, 1.0);
                          return Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - t)),
                              child: child,
                            ),
                          );
                        },
                        child: _buildServiceCard(_services[i], isSmallScreen),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateServiceScreen(entreprise: widget.entreprise),
          ),
        ).then((_) => _fetchServices()),
        backgroundColor: AppConstants.primaryRed,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nouveau service',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, bool isSmallScreen) {
    final medias = service['medias'] is List ? service['medias'] as List : [];
    final hasPromo = service['has_promo'] == true && service['is_promo_active'] == true;
    final isPriceOnRequest = service['is_price_on_request'] == true;
    final isVisible = service['is_visibility'] ?? true;
    final isUpdating = _updatingVisibility[service['id']] ?? false;
    final serviceId = service['id'];

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
          // Image + infos + switch
          Padding(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image miniature
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: isSmallScreen ? 60 : 72,
                    height: isSmallScreen ? 60 : 72,
                    child: medias.isNotEmpty
                        ? Image.network(
                            medias.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imgPlaceholder(),
                          )
                        : _imgPlaceholder(),
                  ),
                ),
                const SizedBox(width: 14),
                // Infos service
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service['name'] ?? '',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Prix
                      if (isPriceOnRequest)
                        _priceBadge('Sur devis', Colors.blue, isSmallScreen)
                      else if (hasPromo)
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${service['price_promo']} FCFA',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 13,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.primaryRed,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${service['price']} FCFA',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 11,
                                color: Colors.grey[400],
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
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 13,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryRed,
                          ),
                        ),
                      const SizedBox(height: 6),
                      // Horaires
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: isSmallScreen ? 10 : 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              service['is_always_open'] == true
                                  ? '24h/24'
                                  : (service['start_time'] != null &&
                                          service['end_time'] != null)
                                      ? '${service['start_time']} - ${service['end_time']}'
                                      : 'Horaires variables',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 11,
                                color: Colors.grey[500],
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
                // Switch on/off pour visibilité
                Column(
                  children: [
                    if (isUpdating)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppConstants.primaryRed,
                        ),
                      )
                    else
                      Switch(
                        value: isVisible,
                        onChanged: (newValue) {
                          _showVisibilityDialog(service, newValue);
                        },
                        activeColor: Colors.white,
                        activeTrackColor: Colors.green,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.grey[300],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      isVisible ? 'Visible' : 'Masqué',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 9 : 10,
                        color: isVisible ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Divider
          Divider(height: 1, color: Colors.grey[100]),

          // Actions (médias + boutons)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 12 : 14,
              vertical: isSmallScreen ? 8 : 10,
            ),
            child: Row(
              children: [
                // Nb médias
                if (medias.isNotEmpty) ...[
                  Icon(
                    Icons.photo_library_outlined,
                    size: isSmallScreen ? 12 : 14,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${medias.length} photo(s)',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 11,
                      color: Colors.grey[500],
                    ),
                  ),
                  const Spacer(),
                ] else
                  const Spacer(),

                // Bouton Modifier
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditServiceScreen(
                        service: service,
                        entreprise: widget.entreprise,
                      ),
                    ),
                  ).then((_) => _fetchServices()),
                  icon: Icon(Icons.edit_outlined, size: isSmallScreen ? 12 : 14),
                  label: Text(
                    'Modifier',
                    style: TextStyle(fontSize: isSmallScreen ? 11 : 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.primaryRed,
                    side: BorderSide(
                      color: AppConstants.primaryRed.withOpacity(0.5),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 10 : 14,
                      vertical: isSmallScreen ? 6 : 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    minimumSize: const Size(0, 0),
                  ),
                ),
                const SizedBox(width: 8),

                // Bouton Supprimer
                OutlinedButton.icon(
                  onPressed: () => _deleteService(service),
                  icon: Icon(Icons.delete_outline, size: isSmallScreen ? 12 : 14),
                  label: Text(
                    'Supprimer',
                    style: TextStyle(fontSize: isSmallScreen ? 11 : 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red.withOpacity(0.4)),
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 10 : 14,
                      vertical: isSmallScreen ? 6 : 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    minimumSize: const Size(0, 0),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showVisibilityDialog(Map<String, dynamic> service, bool newValue) {
    final isVisible = service['is_visibility'] ?? true;
    
    // Si on veut masquer un service actuellement visible
    if (!newValue && isVisible) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Masquer le service'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cette action va rendre votre service invisible aux clients.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Les clients ne pourront plus voir ni réserver ce service.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annuler', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _toggleVisibility(service, newValue);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Masquer'),
            ),
          ],
        ),
      );
    } 
    // Si on veut rendre visible un service masqué
    else if (newValue && !isVisible) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Rendre visible'),
          content: const Text(
            'Cette action va rendre votre service visible aux clients.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annuler', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _toggleVisibility(service, newValue);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Rendre visible'),
            ),
          ],
        ),
      );
    }
  }

  Widget _priceBadge(String label, MaterialColor color, bool isSmallScreen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isSmallScreen ? 10 : 11,
          color: color[700],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
    color: Colors.grey[100],
    child: Icon(Icons.image_not_supported, size: 28, color: Colors.grey[400]),
  );

  Widget _buildEmpty(bool isSmallScreen) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: isSmallScreen ? 70 : 90,
            height: isSmallScreen ? 70 : 90,
            decoration: BoxDecoration(
              color: AppConstants.primaryRed.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.home_repair_service_outlined,
              size: isSmallScreen ? 36 : 44,
              color: AppConstants.primaryRed,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Aucun service',
            style: TextStyle(
              fontSize: isSmallScreen ? 18 : 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Commencez par créer votre premier service.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildShimmer(bool isSmallScreen) => ListView.builder(
    padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
    itemCount: 3,
    itemBuilder: (_, __) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: isSmallScreen ? 110 : 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey[100]!,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isSmallScreen ? 60 : 72,
            height: isSmallScreen ? 60 : 72,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 14,
                  color: Colors.grey[200],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 12,
                  color: Colors.grey[200],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 10,
                  color: Colors.grey[200],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}