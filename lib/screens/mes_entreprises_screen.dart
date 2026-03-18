import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:careasy_app_mobile/screens/create_entreprise_screen.dart';
import 'package:careasy_app_mobile/screens/entreprise_detail_screen.dart';
import 'package:careasy_app_mobile/screens/mes_services_screen.dart';

class MesEntreprisesScreen extends StatefulWidget {
  const MesEntreprisesScreen({super.key});
  @override
  State<MesEntreprisesScreen> createState() => _MesEntreprisesScreenState();
}

class _MesEntreprisesScreenState extends State<MesEntreprisesScreen>
    with SingleTickerProviderStateMixin {
  // APRÈS
final _storage = const FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);
  List<dynamic> _entreprises = [];
  bool _isLoading = true;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fetchMesEntreprises();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  Future<void> _fetchMesEntreprises() async {
  setState(() => _isLoading = true);
  try {
    final token = await _storage.read(key: 'auth_token');
    
    debugPrint('=== DEBUG MES ENTREPRISES ===');
    debugPrint('TOKEN: $token');
    debugPrint('URL: ${AppConstants.apiBaseUrl}/entreprises/mine');
    
    final res = await http.get(
    Uri.parse('${AppConstants.apiBaseUrl}/mes-entreprises'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    debugPrint('STATUS CODE: ${res.statusCode}');
    debugPrint('BODY: ${res.body}');

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      debugPrint('DATA TYPE: ${data.runtimeType}');
      
      final list = data is List ? data : (data['data'] ?? []);
      debugPrint('NOMBRE ENTREPRISES: ${list.length}');
      
      setState(() { _entreprises = list; });
      _animCtrl.forward(from: 0);
    } else {
      debugPrint('ERREUR HTTP: ${res.statusCode}');
      debugPrint('ERREUR BODY: ${res.body}');
      _showError('Erreur ${res.statusCode}');
    }
  } catch (e, stack) {
    debugPrint('EXCEPTION: $e');
    debugPrint('STACK: $stack');
    _showError('Erreur de connexion. Vérifiez votre réseau.');
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red[700], behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  _StatusConfig _getStatusConfig(String status) {
    switch (status) {
      case 'validated': return _StatusConfig(label: 'Validée', color: Colors.green[600]!, bgColor: Colors.green[50]!, icon: Icons.verified, description: 'Votre entreprise est en ligne et visible par les clients.');
      case 'rejected': return _StatusConfig(label: 'Rejetée', color: Colors.red[600]!, bgColor: Colors.red[50]!, icon: Icons.cancel, description: 'Votre demande a été refusée par l\'administrateur.');
      default: return _StatusConfig(label: 'En attente', color: Colors.orange[600]!, bgColor: Colors.orange[50]!, icon: Icons.hourglass_top, description: 'Votre dossier est en cours d\'examen par notre équipe.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: const Text('Mes entreprises', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchMesEntreprises)],
      ),
      body: _isLoading ? _buildLoading() : _entreprises.isEmpty ? _buildEmpty() :
        RefreshIndicator(onRefresh: _fetchMesEntreprises, color: AppConstants.primaryRed,
          child: ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), itemCount: _entreprises.length, itemBuilder: (_, i) {
            final delay = i * 0.1;
            return AnimatedBuilder(animation: _animCtrl, builder: (_, child) {
              final t = (_animCtrl.value - delay).clamp(0.0, 1.0);
              return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child));
            }, child: _buildEntrepriseCard(_entreprises[i]));
          })),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEntrepriseScreen())).then((_) => _fetchMesEntreprises()),
        backgroundColor: AppConstants.primaryRed,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouvelle entreprise', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEntrepriseCard(Map<String, dynamic> e) {
    final status = e['status']?.toString() ?? 'pending';
    final cfg = _getStatusConfig(status);
    final logo = e['logo']?.toString() ?? '';
    final domaines = e['domaines'] as List? ?? [];
    final services = e['services'] as List? ?? [];
    final adminNote = e['admin_note']?.toString() ?? '';
    final createdAt = e['created_at']?.toString() ?? '';
    final isValidated = status == 'validated';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))]),
      child: Column(children: [
        // Header
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cfg.bgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)]),
              child: ClipRRect(borderRadius: BorderRadius.circular(14), child: logo.isNotEmpty ? Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _logoPlaceholder()) : _logoPlaceholder())),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['name'] ?? 'Entreprise', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              _StatusBadge(config: cfg),
            ])),
            if (isValidated) GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntrepriseDetailScreen(entreprise: e))),
              child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.green[600])),
            ),
          ])),

        // Corps
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StatusMessage(config: cfg),
          const SizedBox(height: 14),

          if (status == 'rejected' && adminNote.isNotEmpty) ...[_RejectionBox(note: adminNote), const SizedBox(height: 14)],

          _buildDetails(e, domaines, services, createdAt),

          const SizedBox(height: 16),

          // ── Bouton Créer un service (VALIDÉE UNIQUEMENT) ──
          if (isValidated) ...[
            _buildCreateServiceButton(e),
            const SizedBox(height: 10),
          ],

          _buildActions(e, status),
        ])),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  //  Bouton Créer un service — VALIDÉE UNIQUEMENT
  //  (fonctionnalité à implémenter ultérieurement)
  // ─────────────────────────────────────────────
  Widget _buildCreateServiceButton(Map<String, dynamic> entreprise) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppConstants.primaryRed, AppConstants.primaryRed.withOpacity(0.8)], begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MesServicesScreen(entreprise: entreprise),
            ),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add_circle_outline, color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Créer un service', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text('Ajoutez un service à votre entreprise', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
              const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
            ]),
          ),
        ),
      ),
    );
  }

  void _showComingSoon() {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (_) => Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 24),
      Container(width: 70, height: 70, decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.rocket_launch_outlined, color: AppConstants.primaryRed, size: 36)),
      const SizedBox(height: 16),
      const Text('Bientôt disponible', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('La création de service sera disponible dans la prochaine mise à jour.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5)),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('OK, compris'))),
    ])));
  }

  Widget _buildDetails(Map<String, dynamic> e, List domaines, List services, String createdAt) {
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey[200]!)),
      child: Column(children: [
        _detailRow(icon: Icons.badge_outlined, label: 'IFU', value: e['ifu_number']?.toString() ?? 'Non renseigné'),
        const Divider(height: 16),
        _detailRow(icon: Icons.article_outlined, label: 'RCCM', value: e['rccm_number']?.toString() ?? 'Non renseigné'),
        const Divider(height: 16),
        _detailRow(icon: Icons.person_outline, label: 'PDG', value: e['pdg_full_name']?.toString() ?? 'Non renseigné'),
        const Divider(height: 16),
        _detailRow(icon: Icons.phone_outlined, label: 'Téléphone', value: e['call_phone']?.toString() ?? 'Non renseigné'),
        if ((e['google_formatted_address'] ?? e['siege'] ?? '').toString().isNotEmpty) ...[
          const Divider(height: 16),
          _detailRow(icon: Icons.location_on_outlined, label: 'Adresse', value: e['google_formatted_address']?.toString() ?? e['siege']?.toString() ?? '', maxLines: 2),
        ],
        if (domaines.isNotEmpty) ...[
          const Divider(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.category_outlined, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 8),
            SizedBox(width: 72, child: Text('Domaines', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500))),
            Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: domaines.map((d) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Text(d['name']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: AppConstants.primaryRed, fontWeight: FontWeight.w500)))).toList())),
          ]),
        ],
        if (services.isNotEmpty) ...[
          const Divider(height: 16),
          _detailRow(icon: Icons.home_repair_service_outlined, label: 'Services', value: '${services.length} service${services.length > 1 ? 's' : ''} publié${services.length > 1 ? 's' : ''}'),
        ],
        if (createdAt.isNotEmpty) ...[
          const Divider(height: 16),
          _detailRow(icon: Icons.calendar_today_outlined, label: 'Soumis le', value: _formatDate(createdAt)),
        ],
      ]));
  }

  Widget _detailRow({required IconData icon, required String label, required String value, int maxLines = 1}) => Row(crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [Icon(icon, size: 16, color: Colors.grey[600]), const SizedBox(width: 8), SizedBox(width: 72, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500))), Expanded(child: Text(value, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)))]);

  Widget _buildActions(Map<String, dynamic> e, String status) {
  if (status == 'validated') {
    // Afficher le décompte essai si applicable
    final bool isInTrial = e['is_in_trial_period'] == true ||
        (e['trial_status'] is Map && e['trial_status']['status'] == 'active');
    final int joursRestants = e['trial_days_remaining'] != null
        ? (int.tryParse(e['trial_days_remaining'].toString()) ?? 0)
        : (e['trial_status'] is Map
            ? (int.tryParse(
                    e['trial_status']['days_remaining']?.toString() ?? '0') ??
                0)
            : 0);

    return Column(children: [
      // Badge essai gratuit si en cours
      if (isInTrial) ...[
        _buildTrialBadge(joursRestants),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => EntrepriseDetailScreen(entreprise: e))),
        icon: const Icon(Icons.visibility_outlined, size: 16),
        label: const Text('Voir la page publique'),
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.green[700],
            side: BorderSide(color: Colors.green[300]!),
            minimumSize: const Size(double.infinity, 44),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
    ]);
  }

  if (status == 'rejected') {
    final adminNote = e['admin_note']?.toString() ?? '';
    return ElevatedButton.icon(
      onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      CreateEntrepriseScreen(rejectionNote: adminNote)))
          .then((_) => _fetchMesEntreprises()),
      icon: const Icon(Icons.refresh, size: 16),
      label: const Text('Resoumettre une demande'),
      style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryRed,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 44),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }

  return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange[200]!)),
      child: Row(children: [
        Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
        const SizedBox(width: 8),
        Expanded(
            child: Text('Vous serez notifié dès que votre dossier sera traité.',
                style: TextStyle(fontSize: 12, color: Colors.orange[800])))
      ]));
}

// Nouveau widget : badge décompte essai
Widget _buildTrialBadge(int joursRestants) {
  final isUrgent = joursRestants <= 5;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: isUrgent ? Colors.red[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isUrgent
                ? Colors.red.withOpacity(0.3)
                : Colors.blue.withOpacity(0.3))),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(Icons.science_outlined,
              size: 14,
              color: isUrgent ? Colors.red[700] : Colors.blue[700]),
          const SizedBox(width: 6),
          Text('Essai gratuit — 30 jours',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isUrgent ? Colors.red[700] : Colors.blue[700])),
        ]),
        Text(
            joursRestants > 0
                ? '$joursRestants j restant${joursRestants > 1 ? 's' : ''}'
                : 'Expiré',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isUrgent ? Colors.red[600] : Colors.blue[600])),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: (joursRestants / 30.0).clamp(0.0, 1.0),
          backgroundColor: (isUrgent ? Colors.red : Colors.blue).withOpacity(0.15),
          valueColor: AlwaysStoppedAnimation<Color>(
              isUrgent ? Colors.red : Colors.blue),
          minHeight: 6,
        ),
      ),
      if (isUrgent) ...[
        const SizedBox(height: 8),
        Text(
            'Souscrivez avant expiration pour ne pas perdre vos services !',
            style: TextStyle(fontSize: 11, color: Colors.red[700])),
      ]
    ]),
  );
}

  Widget _buildEmpty() => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 100, height: 100, decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.08), shape: BoxShape.circle), child: const Icon(Icons.business_outlined, size: 50, color: AppConstants.primaryRed)),
    const SizedBox(height: 24),
    const Text('Aucune entreprise', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Text('Vous n\'avez pas encore soumis de demande de création d\'entreprise.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.5)),
    const SizedBox(height: 28),
    ElevatedButton.icon(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEntrepriseScreen())).then((_) => _fetchMesEntreprises()),
      icon: const Icon(Icons.add), label: const Text('Créer mon entreprise'),
      style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
  ])));

  Widget _buildLoading() => ListView.builder(padding: const EdgeInsets.all(16), itemCount: 2, itemBuilder: (_, i) => Container(margin: const EdgeInsets.only(bottom: 16), height: 280, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: Column(children: [Container(height: 90, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: const BorderRadius.vertical(top: Radius.circular(20)))), Padding(padding: const EdgeInsets.all(16), child: Column(children: [Container(height: 12, color: Colors.grey[200]), const SizedBox(height: 8), Container(height: 12, width: 200, color: Colors.grey[200])]))])));

  Widget _logoPlaceholder() => Container(color: Colors.grey[100], child: Icon(Icons.business, size: 28, color: Colors.grey[400]));

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      const months = ['jan.','fév.','mar.','avr.','mai','juin','juil.','août','sep.','oct.','nov.','déc.'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) { return raw; }
  }
}

class _StatusConfig {
  final String label; final Color color, bgColor; final IconData icon; final String description;
  const _StatusConfig({required this.label, required this.color, required this.bgColor, required this.icon, required this.description});
}

class _StatusBadge extends StatefulWidget {
  final _StatusConfig config;
  const _StatusBadge({required this.config});
  @override State<_StatusBadge> createState() => _StatusBadgeState();
}
class _StatusBadgeState extends State<_StatusBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200)); _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); if (widget.config.label == 'En attente') _ctrl.repeat(reverse: true); else _ctrl.forward(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => ScaleTransition(scale: _pulse, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: widget.config.color.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: widget.config.color.withOpacity(0.4))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(widget.config.icon, size: 13, color: widget.config.color), const SizedBox(width: 5), Text(widget.config.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.config.color))])));
}

class _StatusMessage extends StatelessWidget {
  final _StatusConfig config;
  const _StatusMessage({required this.config});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: config.bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: config.color.withOpacity(0.2))),
    child: Row(children: [Icon(config.icon, size: 18, color: config.color), const SizedBox(width: 10), Expanded(child: Text(config.description, style: TextStyle(fontSize: 12, color: config.color, fontWeight: FontWeight.w500, height: 1.3)))]));
}

class _RejectionBox extends StatelessWidget {
  final String note;
  const _RejectionBox({required this.note});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red[200]!)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.report_problem_outlined, size: 16, color: Colors.red[700]), const SizedBox(width: 8), Text('Motif du rejet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[700]))]),
      const SizedBox(height: 8),
      Text(note, style: TextStyle(fontSize: 13, color: Colors.red[800], height: 1.5)),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[200]!)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lightbulb_outline, size: 14, color: Colors.red[600]), const SizedBox(width: 6), Expanded(child: Text('Corrigez les points soulevés et resoumettez votre dossier.', style: TextStyle(fontSize: 11, color: Colors.red[700], fontStyle: FontStyle.italic)))])),
    ]));
}