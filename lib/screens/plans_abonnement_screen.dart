import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────
//  PlansAbonnementScreen
//  Affiche les plans disponibles + abonnement actif
// ─────────────────────────────────────────────
class PlansAbonnementScreen extends StatefulWidget {
  const PlansAbonnementScreen({super.key});

  @override
  State<PlansAbonnementScreen> createState() => _PlansAbonnementScreenState();
}

class _PlansAbonnementScreenState extends State<PlansAbonnementScreen>
    with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  late TabController _tabCtrl;

  List<dynamic> _plans = [];
  Map<String, dynamic>? _abonnementActif;
  List<dynamic> _historique = [];

  bool _isLoadingPlans = true;
  bool _isLoadingAbonnement = true;
  bool _isInitiating = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _fetchAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    await Future.wait([_fetchPlans(), _fetchAbonnements()]);
  }

  Future<void> _fetchPlans() async {
    setState(() => _isLoadingPlans = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/plans'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _plans = data['data'] ?? data);
      }
    } catch (_) {}
    finally { if (mounted) setState(() => _isLoadingPlans = false); }
  }

  Future<void> _fetchAbonnements() async {
    setState(() => _isLoadingAbonnement = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      // Abonnement actif
      final actifRes = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/abonnements/actif'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (actifRes.statusCode == 200) {
        final data = jsonDecode(actifRes.body);
        setState(() => _abonnementActif = data['success'] == true ? data['data'] : null);
      }
      // Historique
      final histRes = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/abonnements'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (histRes.statusCode == 200) {
        final data = jsonDecode(histRes.body);
        setState(() => _historique = data['data'] ?? []);
      }
    } catch (_) {}
    finally { if (mounted) setState(() => _isLoadingAbonnement = false); }
  }

  Future<void> _initierPaiement(Map<String, dynamic> plan) async {
    setState(() => _isInitiating = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/paiements/initier/${plan['id']}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final paymentUrl = data['data']?['payment_url'];
        if (paymentUrl != null) {
          final uri = Uri.parse(paymentUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      } else {
        _showError(data['message'] ?? 'Erreur lors de l\'initiation du paiement');
      }
    } catch (_) {
      _showError('Erreur de connexion');
    } finally {
      setState(() => _isInitiating = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Plans & Abonnements',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Plans disponibles'),
            Tab(text: 'Mon abonnement'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildPlansTab(),
          _buildAbonnementTab(),
        ],
      ),
    );
  }

  // ── ONGLET PLANS ──────────────────────────────
  Widget _buildPlansTab() {
    if (_isLoadingPlans) {
      return const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed));
    }
    if (_plans.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.subscriptions_outlined, size: 56, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('Aucun plan disponible', style: TextStyle(color: Colors.grey[500])),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _fetchPlans,
      color: AppConstants.primaryRed,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _plans.length,
        itemBuilder: (_, i) => _buildPlanCard(_plans[i]),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final features = (plan['features_list'] ?? plan['features'] ?? []) as List;
    final price = plan['price'] ?? 0;
    final formattedPrice = plan['formatted_price'] ?? '$price F CFA';
    final duration = plan['duration_text'] ?? '${plan['duration_days']} jours';
    final isPopular = (plan['sort_order'] ?? 0) == 1;
    final isCurrentPlan = _abonnementActif?['plan']?['id']?.toString() == plan['id']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isCurrentPlan
                ? Colors.green.withOpacity(0.5)
                : isPopular
                    ? AppConstants.primaryRed.withOpacity(0.3)
                    : Colors.grey[200]!,
            width: isCurrentPlan || isPopular ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: isPopular
                ? AppConstants.primaryRed.withOpacity(0.08)
                : Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: [
        // Header plan
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isCurrentPlan
                ? Colors.green[50]
                : isPopular
                    ? AppConstants.primaryRed.withOpacity(0.05)
                    : Colors.grey[50],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(plan['name'] ?? '',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (isCurrentPlan) ...[
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(20)),
                      child: const Text('Actif', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                  ] else if (isPopular) ...[
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppConstants.primaryRed, borderRadius: BorderRadius.circular(20)),
                      child: const Text('Populaire', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                  ],
                ]),
                if (plan['description'] != null)
                  Text(plan['description'], style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formattedPrice,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                        color: isCurrentPlan ? Colors.green[700] : AppConstants.primaryRed)),
                Text(duration, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ]),
            ]),
          ]),
        ),

        // Features
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          ...features.take(6).map((f) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 20, height: 20,
                decoration: BoxDecoration(color: Colors.green[50], shape: BoxShape.circle),
                child: Icon(Icons.check, size: 12, color: Colors.green[600])),
              const SizedBox(width: 10),
              Expanded(child: Text(f.toString(),
                  style: const TextStyle(fontSize: 13))),
            ]),
          )),

          const SizedBox(height: 16),

          // Bouton
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: isCurrentPlan ? null : (_isInitiating ? null : () => _showConfirmDialog(plan)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isCurrentPlan ? Colors.grey[300] : AppConstants.primaryRed,
                foregroundColor: isCurrentPlan ? Colors.grey[600] : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isInitiating
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isCurrentPlan ? 'Plan actuel' : 'Souscrire — $formattedPrice',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            )),
        ])),
      ]),
    );
  }

  void _showConfirmDialog(Map<String, dynamic> plan) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Souscrire à ${plan['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Montant', style: TextStyle(color: Colors.grey[600])),
              Text(plan['formatted_price'] ?? '',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                      color: AppConstants.primaryRed)),
            ])),
          const SizedBox(height: 12),
          Text('Vous allez être redirigé vers FedaPay pour finaliser votre paiement.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Annuler', style: TextStyle(color: Colors.grey[600]))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _initierPaiement(plan);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Continuer vers le paiement'),
          ),
        ],
      ),
    );
  }

  // ── ONGLET ABONNEMENT ─────────────────────────
  Widget _buildAbonnementTab() {
    if (_isLoadingAbonnement) {
      return const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed));
    }
    return RefreshIndicator(
      onRefresh: _fetchAbonnements,
      color: AppConstants.primaryRed,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Abonnement actif ou pas
          if (_abonnementActif != null)
            _buildAbonnementActifCard()
          else
            _buildNoAbonnementCard(),

          const SizedBox(height: 24),

          // Historique
          if (_historique.isNotEmpty) ...[
            Row(children: [
              const Text('Historique', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${_historique.length} abonnement(s)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ]),
            const SizedBox(height: 12),
            ..._historique.map((a) => _buildHistoriqueItem(a)),
          ],
        ]),
      ),
    );
  }

  Widget _buildAbonnementActifCard() {
    final a = _abonnementActif!;
    final plan = a['plan'] ?? {};
    final joursRestants = a['jours_restants'] ?? 0;
    final dateFin = a['date_fin'] ?? '';
    final estEssai = a['est_essai'] == true || a['type'] == 'trial';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: estEssai
              ? [Colors.blue[600]!, Colors.blue[400]!]
              : [AppConstants.primaryRed, AppConstants.primaryRed.withOpacity(0.8)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: (estEssai ? Colors.blue : AppConstants.primaryRed).withOpacity(0.3),
          blurRadius: 20, offset: const Offset(0, 8),
        )],
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(estEssai ? Icons.science_outlined : Icons.verified_outlined,
                  color: Colors.white, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(estEssai ? 'Période d\'essai' : plan['name'] ?? 'Abonnement',
                  style: const TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Text(estEssai ? 'Gratuit — 30 jours' : a['montant_formate'] ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ])),
            // Badge actif
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('Actif', style: TextStyle(color: Colors.white,
                  fontSize: 11, fontWeight: FontWeight.bold))),
          ]),

          const SizedBox(height: 20),

          // Barre de progression jours
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$joursRestants jour(s) restant(s)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              Text('Expire le $dateFin',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: joursRestants > 30 ? 1.0 : joursRestants / 30.0,
                backgroundColor: Colors.white.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 8,
              )),
          ]),

          const SizedBox(height: 16),
          const Divider(color: Colors.white30),
          const SizedBox(height: 12),

          // Stats
          Row(children: [
            _statItem(Icons.home_repair_service_outlined,
                '${plan['max_services'] ?? '∞'}', 'Services max'),
            Container(width: 1, height: 32, color: Colors.white30),
            _statItem(Icons.people_outline,
                '${plan['max_employees'] ?? '∞'}', 'Employés max'),
            Container(width: 1, height: 32, color: Colors.white30),
            _statItem(Icons.api_outlined,
                plan['has_api_access'] == true ? 'Oui' : 'Non', 'Accès API'),
          ]),
        ],
      )),
    );
  }

  Widget _statItem(IconData icon, String value, String label) => Expanded(
    child: Column(children: [
      Icon(icon, color: Colors.white70, size: 18),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
    ]),
  );

  Widget _buildNoAbonnementCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!)),
    child: Column(children: [
      Container(width: 70, height: 70,
        decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
        child: Icon(Icons.subscriptions_outlined, size: 36, color: Colors.grey[400])),
      const SizedBox(height: 16),
      const Text('Aucun abonnement actif',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('Souscrivez à un plan pour débloquer toutes les fonctionnalités.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: () => _tabCtrl.animateTo(0),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: const Text('Voir les plans'),
      ),
    ]),
  );

  Widget _buildHistoriqueItem(Map<String, dynamic> a) {
    final plan = a['plan'] ?? {};
    final statut = a['statut'] ?? 'inconnu';
    final estEssai = a['est_essai'] == true || a['type'] == 'trial';

    Color statusColor;
    String statusLabel;
    switch (statut) {
      case 'actif': statusColor = Colors.green; statusLabel = 'Actif'; break;
      case 'expire': statusColor = Colors.grey; statusLabel = 'Expiré'; break;
      case 'annule': statusColor = Colors.red; statusLabel = 'Annulé'; break;
      default: statusColor = Colors.orange; statusLabel = statut;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!)),
      child: Row(children: [
        Container(width: 42, height: 42,
          decoration: BoxDecoration(
              color: (estEssai ? Colors.blue : AppConstants.primaryRed).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(estEssai ? Icons.science_outlined : Icons.subscriptions_outlined,
              color: estEssai ? Colors.blue : AppConstants.primaryRed, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(estEssai ? 'Période d\'essai' : plan['name'] ?? 'Abonnement',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text('${a['date_debut'] ?? ''} → ${a['date_fin'] ?? ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text(statusLabel,
                style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Text(estEssai ? 'Gratuit' : (a['montant_formate'] ?? ''),
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
      ]),
    );
  }
}