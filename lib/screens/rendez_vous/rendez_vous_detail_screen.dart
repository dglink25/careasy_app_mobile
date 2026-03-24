// lib/screens/rendez_vous/rendez_vous_detail_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../../providers/rendez_vous_provider.dart';
import '../../models/rendez_vous_model.dart';
import '../../utils/constants.dart';
import '../../services/notification_service.dart';  // ← AJOUT notifications

class RendezVousDetailScreen extends StatefulWidget {
  final String rdvId;
  const RendezVousDetailScreen({super.key, required this.rdvId});

  @override
  State<RendezVousDetailScreen> createState() => _RendezVousDetailScreenState();
}

class _RendezVousDetailScreenState extends State<RendezVousDetailScreen> {
  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  bool _actionLoading = false;
  String? _currentUserId;
  bool _userLoaded = false;

  @override
  void initState() {
    super.initState();
    // Charger l'utilisateur EN PREMIER, puis le RDV
    _loadCurrentUser().then((_) {
      if (mounted) {
        context.read<RendezVousProvider>().loadRendezVousById(widget.rdvId);
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _currentUserId = map['id']?.toString();
            _userLoaded    = true;
          });
          debugPrint('[RDV DETAIL] currentUserId=$_currentUserId');
        }
      } else {
        if (mounted) setState(() => _userLoaded = true);
      }
    } catch (e) {
      debugPrint('[RDV DETAIL] Erreur: $e');
      if (mounted) setState(() => _userLoaded = true);
    }
  }

  bool _isPrestataire(RendezVousModel rdv) =>
      _currentUserId != null && _currentUserId == rdv.prestataireId;

  bool _isClient(RendezVousModel rdv) =>
      _currentUserId != null && _currentUserId == rdv.clientId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Consumer<RendezVousProvider>(
        builder: (context, prov, _) {
          if (!_userLoaded || (prov.isLoading && prov.selected == null)) {
            return const Center(
                child: CircularProgressIndicator(
                    color: AppConstants.primaryRed));
          }

          final rdv = prov.selected;
          if (rdv == null) return _buildNotFound(prov.error);

          debugPrint('[RDV DETAIL] prestataireId=${rdv.prestataireId} '
              'clientId=${rdv.clientId} '
              'isPresta=${_isPrestataire(rdv)} '
              'isClient=${_isClient(rdv)}');

          return CustomScrollView(
            slivers: [
              _buildAppBar(rdv),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildStatusCard(rdv),
                    const SizedBox(height: 16),
                    _buildInfoCard(rdv),
                    const SizedBox(height: 16),
                    if (rdv.clientNotes != null &&
                        rdv.clientNotes!.isNotEmpty) ...[
                      _buildNotesCard(rdv),
                      const SizedBox(height: 16),
                    ],
                    if (prov.error != null) ...[
                      _buildError(prov.error!),
                      const SizedBox(height: 12),
                    ],
                    _buildActionButtons(rdv),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────
  Widget _buildAppBar(RendezVousModel rdv) => SliverAppBar(
    backgroundColor: AppConstants.primaryRed,
    foregroundColor: Colors.white,
    expandedHeight: 155,
    pinned: true,
    flexibleSpace: FlexibleSpaceBar(
      background: Container(
        color: AppConstants.primaryRed,
        padding: const EdgeInsets.fromLTRB(16, 80, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_userLoaded)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isPrestataire(rdv)
                      ? 'Vous êtes le prestataire'
                      : 'Vous êtes le client',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11),
                ),
              ),
            Text(rdv.serviceName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.business, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(rdv.entrepriseName,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ],
        ),
      ),
    ),
  );

  // ── Statut ────────────────────────────────────────────────────────────────
  Widget _buildStatusCard(RendezVousModel rdv) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).dividerColor!),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Statut',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          _StatusBadge(status: rdv.status, large: true),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Créé le',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(_shortDate(rdv.createdAt),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ],
    ),
  );

  // ── Infos ─────────────────────────────────────────────────────────────────
  Widget _buildInfoCard(RendezVousModel rdv) {
    final isPresta = _isPrestataire(rdv);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.info_outline, 'Détails'),
          const SizedBox(height: 14),
          _infoRow(Icons.calendar_today_outlined, 'Date',
              rdv.formattedDate),
          _divider(),
          _infoRow(Icons.access_time, 'Horaire', rdv.timeRange),
          _divider(),
          _infoRow(
            isPresta
                ? Icons.person_outline
                : Icons.business_center_outlined,
            isPresta ? 'Client' : 'Prestataire',
            isPresta ? rdv.clientName : rdv.prestataireName,
          ),
          if (rdv.confirmedAt != null) ...[
            _divider(),
            _infoRow(Icons.check_circle_outline, 'Confirmé le',
                _shortDateFull(rdv.confirmedAt!)),
          ],
          if (rdv.cancelledAt != null) ...[
            _divider(),
            _infoRow(Icons.cancel_outlined, 'Annulé le',
                _shortDateFull(rdv.cancelledAt!)),
          ],
          if (rdv.completedAt != null) ...[
            _divider(),
            _infoRow(Icons.done_all, 'Terminé le',
                _shortDateFull(rdv.completedAt!)),
          ],
        ],
      ),
    );
  }

  Widget _buildNotesCard(RendezVousModel rdv) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.blue[50],
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.blue[200]!),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.notes, color: Colors.blue[700], size: 18),
        const SizedBox(width: 8),
        Text('Notes du client',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.blue[700])),
      ]),
      const SizedBox(height: 8),
      Text(rdv.clientNotes!,
          style: TextStyle(
              fontSize: 14, color: Colors.blue[900], height: 1.5)),
    ]),
  );

  // ── Boutons d'action ──────────────────────────────────────────────────────
  Widget _buildActionButtons(RendezVousModel rdv) {
    if (!_userLoaded) return const SizedBox.shrink();

    final isPresta = _isPrestataire(rdv);
    final isClient = _isClient(rdv);

    final canConfirm      = isPresta && rdv.isPending;
    final canComplete     = isPresta && rdv.isConfirmed;
    final canRefuse       = isPresta && rdv.canBeCancelled;
    final canCancelClient = isClient && rdv.canBeCancelled;

    if (!canConfirm && !canComplete && !canRefuse && !canCancelClient) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Prestataire : accepter ──────────────────────────────────────
        if (canConfirm) ...[
          _actionButton(
            label: 'Accepter le rendez-vous',
            icon: Icons.check_circle_outline,
            color: Colors.green,
            onTap: () => _confirm(rdv.id),
          ),
          const SizedBox(height: 10),
        ],

        // ── Prestataire : terminer ──────────────────────────────────────
        if (canComplete) ...[
          _actionButton(
            label: 'Marquer comme terminé',
            icon: Icons.done_all,
            color: Colors.blue,
            onTap: () => _complete(rdv.id),
          ),
          const SizedBox(height: 10),
        ],

        // ── Prestataire : refuser ───────────────────────────────────────
        if (canRefuse)
          _actionButton(
            label: isPresta && rdv.isPending
                ? 'Refuser le rendez-vous'
                : 'Annuler le rendez-vous',
            icon: Icons.cancel_outlined,
            color: Colors.red,
            outlined: true,
            onTap: () => _showCancelDialog(
              rdv.id,
              title: isPresta && rdv.isPending
                  ? 'Refuser le rendez-vous'
                  : 'Annuler le rendez-vous',
              confirmLabel: isPresta && rdv.isPending
                  ? 'Confirmer le refus'
                  : 'Confirmer l\'annulation',
              hintText: isPresta && rdv.isPending
                  ? 'Raison du refus (optionnel)'
                  : 'Raison (optionnel)',
            ),
          ),

        // ── Client : annuler ────────────────────────────────────────────
        if (canCancelClient && !isPresta) ...[
          if (canRefuse) const SizedBox(height: 10),
          _actionButton(
            label: 'Annuler ma demande',
            icon: Icons.event_busy_outlined,
            color: Colors.orange,
            outlined: true,
            onTap: () => _showCancelDialog(
              rdv.id,
              title: 'Annuler ma demande',
              confirmLabel: 'Confirmer l\'annulation',
              hintText: 'Raison (optionnel)',
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    if (_actionLoading) {
      return Container(
        height: 52,
        decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12)),
        child: const Center(
            child: CircularProgressIndicator(
                color: AppConstants.primaryRed)),
      );
    }
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Actions serveur ───────────────────────────────────────────────────────
  Future<void> _confirm(String id) async {
    setState(() => _actionLoading = true);
    final ok = await context.read<RendezVousProvider>().confirmRendezVous(id);
    if (mounted) {
      setState(() => _actionLoading = false);
      _showFeedback(
        ok
            ? 'Rendez-vous accepté !'
            : context.read<RendezVousProvider>().error ?? 'Erreur',
        ok,
      );
      // ── AJOUT : planifier rappel 1h avant ──────────────────────────
      if (ok) {
        final rdv = context.read<RendezVousProvider>().selected;
        if (rdv != null) {
          await NotificationService().scheduleRdvReminder(
            rdvId        : rdv.id,
            rdvDate      : rdv.date,
            rdvTime      : rdv.startTime,
            serviceName  : rdv.serviceName ?? 'le service',
            isPrestataire: _isPrestataire(rdv),
          );
        }
      }
    }
  }

  Future<void> _complete(String id) async {
    setState(() => _actionLoading = true);
    final ok = await context.read<RendezVousProvider>().completeRendezVous(id);
    if (mounted) {
      setState(() => _actionLoading = false);
      _showFeedback(
        ok
            ? 'Rendez-vous terminé !'
            : context.read<RendezVousProvider>().error ?? 'Erreur',
        ok,
      );
      // ── AJOUT : notif "noter le service" + annuler rappel ──────────
      if (ok) {
        final rdv = context.read<RendezVousProvider>().selected;
        if (rdv != null) {
          await NotificationService().showReviewRequestNotification(
            rdvId      : rdv.id,
            serviceName: rdv.serviceName ?? 'le service',
          );
          await NotificationService().cancelRdvReminder(rdv.id);
        }
      }
    }
  }

  void _showCancelDialog(
    String id, {
    required String title,
    required String confirmLabel,
    required String hintText,
  }) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Cette action est irréversible.',
              style: TextStyle(
                  color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: hintText,
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Retour'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _actionLoading = true);
              final ok = await context
                  .read<RendezVousProvider>()
                  .cancelRendezVous(id, reason: ctrl.text.trim());
              if (mounted) {
                setState(() => _actionLoading = false);
                _showFeedback(
                  ok
                      ? 'Opération effectuée.'
                      : context.read<RendezVousProvider>().error ??
                          'Erreur',
                  ok,
                );
                // ── AJOUT : annuler le rappel planifié ──────────────
                if (ok) {
                  final rdv = context.read<RendezVousProvider>().selected;
                  if (rdv != null) {
                    await NotificationService().cancelRdvReminder(rdv.id);
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _showFeedback(String msg, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green[700] : Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  Widget _buildError(String msg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red[50],
      border: Border.all(color: Colors.red[200]!),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, color: Colors.red, size: 18),
      const SizedBox(width: 8),
      Expanded(
          child: Text(msg, style: const TextStyle(color: Colors.red))),
    ]),
  );

  Widget _buildNotFound(String? error) => Scaffold(
    appBar: AppBar(
      backgroundColor: AppConstants.primaryRed,
      foregroundColor: Colors.white,
      title: const Text('Rendez-vous'),
    ),
    body: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.calendar_today_outlined,
            size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        Text(error ?? 'Rendez-vous introuvable',
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryRed,
              foregroundColor: Colors.white),
          child: const Text('Retour'),
        ),
      ]),
    ),
  );

  Widget _sectionTitle(IconData icon, String title) => Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: AppConstants.primaryRed.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: AppConstants.primaryRed, size: 16),
    ),
    const SizedBox(width: 10),
    Text(title,
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold)),
  ]);

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Icon(icon, size: 16, color: Colors.grey[500]),
      const SizedBox(width: 10),
      SizedBox(
        width: 110,
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ]),
  );

  Widget _divider() => Divider(height: 1, color: Colors.grey[100]);

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _shortDateFull(DateTime d) =>
      '${_shortDate(d)} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ── Badge statut ──────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  final bool large;
  const _StatusBadge({required this.status, this.large = false});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'pending'   => ('En attente', Colors.orange[50]!, Colors.orange[700]!),
      'confirmed' => ('Confirmé',   Colors.green[50]!,  Colors.green[700]!),
      'cancelled' => ('Annulé',     Colors.red[50]!,    Colors.red[700]!),
      'completed' => ('Terminé',    Colors.grey[100]!,  Colors.grey[700]!),
      _           => (status,       Colors.grey[100]!,  Colors.grey[700]!),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 14 : 10, vertical: large ? 6 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: large ? 13 : 11,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }
}