// lib/screens/rendez_vous/rendez_vous_list_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../../providers/rendez_vous_provider.dart';
import '../../models/rendez_vous_model.dart';
import '../../utils/constants.dart';
import 'rendez_vous_detail_screen.dart';

class RendezVousListScreen extends StatefulWidget {
  const RendezVousListScreen({super.key});

  @override
  State<RendezVousListScreen> createState() => _RendezVousListScreenState();
}

class _RendezVousListScreenState extends State<RendezVousListScreen> {
  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser().then((_) {
      if (mounted) {
        context.read<RendezVousProvider>().loadRendezVous();
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() => _currentUserId = map['id']?.toString());
          debugPrint('[RDV LIST] currentUserId=$_currentUserId '
              'role=${map['role']}');
        }
      }
    } catch (e) {
      debugPrint('[RDV LIST] Erreur: $e');
    }
  }

  bool _isPrestataire(RendezVousModel rdv) =>
      _currentUserId != null && _currentUserId == rdv.prestataireId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mes rendez-vous',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<RendezVousProvider>().loadRendezVous(),
          ),
        ],
      ),
      body: Consumer<RendezVousProvider>(
        builder: (context, prov, _) {
          if (prov.isLoading && prov.rendezVous.isEmpty) {
            return const Center(
                child: CircularProgressIndicator(
                    color: AppConstants.primaryRed));
          }
          return Column(
            children: [
              _buildStats(prov),
              _buildFilterBar(prov),
              if (prov.error != null) _buildError(prov.error!),
              Expanded(child: _buildList(prov)),
            ],
          );
        },
      ),
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Widget _buildStats(RendezVousProvider prov) {
    return Container(
      color: AppConstants.primaryRed,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(children: [
        _statChip('En attente', prov.countPending, Colors.orange),
        const SizedBox(width: 8),
        _statChip('Confirmés', prov.countConfirmed, Colors.green),
        const SizedBox(width: 8),
        _statChip('Annulés', prov.countCancelled, Colors.red[300]!),
        const SizedBox(width: 8),
        _statChip('Terminés', prov.countCompleted, Colors.grey),
      ]),
    );
  }

  Widget _statChip(String label, int count, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$count',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 10),
            textAlign: TextAlign.center),
      ]),
    ),
  );

  // ── Filtres ───────────────────────────────────────────────────────────────
  Widget _buildFilterBar(RendezVousProvider prov) {
    final filters = [
      ('all', 'Tous'),
      ('pending', 'En attente'),
      ('confirmed', 'Confirmés'),
      ('cancelled', 'Annulés'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isActive = prov.filter == f.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(f.$2,
                    style: TextStyle(
                        color: isActive ? Colors.white : Colors.black87,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 13)),
                selected: isActive,
                onSelected: (_) => prov.setFilter(f.$1),
                backgroundColor: Colors.grey[100],
                selectedColor: AppConstants.primaryRed,
                checkmarkColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                side: BorderSide(
                    color: isActive
                        ? AppConstants.primaryRed
                        : Colors.grey[300]!),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildError(String msg) => Container(
    margin: const EdgeInsets.all(16),
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

  // ── Liste ─────────────────────────────────────────────────────────────────
  Widget _buildList(RendezVousProvider prov) {
    final items = prov.filtered;
    if (items.isEmpty && !prov.isLoading) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.calendar_today_outlined,
              size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Aucun rendez-vous',
              style: TextStyle(fontSize: 16, color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text('Vos demandes apparaîtront ici',
              style: TextStyle(fontSize: 13, color: Colors.grey[400])),
        ]),
      );
    }
    return RefreshIndicator(
      color: AppConstants.primaryRed,
      onRefresh: prov.loadRendezVous,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (ctx, i) => _RendezVousCard(
          rdv: items[i],
          isPrestataire: _isPrestataire(items[i]),
        ),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────
class _RendezVousCard extends StatelessWidget {
  final RendezVousModel rdv;
  final bool isPrestataire;
  const _RendezVousCard(
      {required this.rdv, required this.isPrestataire});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RendezVousDetailScreen(rdvId: rdv.id),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: Text(rdv.serviceName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: rdv.status),
              ]),
              const SizedBox(height: 4),
              Text(rdv.entrepriseName,
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey[600])),

              const SizedBox(height: 10),

              // ── Rôle dans ce RDV ─────────────────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPrestataire
                        ? Colors.purple[50]
                        : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isPrestataire
                            ? Colors.purple[200]!
                            : Colors.blue[200]!),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      isPrestataire
                          ? Icons.business_center_outlined
                          : Icons.person_outline,
                      size: 11,
                      color: isPrestataire
                          ? Colors.purple[700]
                          : Colors.blue[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPrestataire ? 'Prestataire' : 'Client',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isPrestataire
                              ? Colors.purple[700]
                              : Colors.blue[700]),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                // Nom de l'autre partie
                Text(
                  isPrestataire
                      ? 'Client : ${rdv.clientName}'
                      : 'Prestataire : ${rdv.prestataireName}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[600]),
                ),
              ]),

              const SizedBox(height: 10),

              // ── Date + heure ──────────────────────────────────────────
              Row(children: [
                _infoItem(
                    Icons.calendar_today_outlined, rdv.formattedDate),
                const SizedBox(width: 16),
                _infoItem(Icons.access_time, rdv.timeRange),
              ]),

              // ── Action rapide pour prestataire en attente ─────────────
              if (isPrestataire && rdv.isPending) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(children: [
                    Icon(Icons.notifications_active_outlined,
                        size: 14, color: Colors.orange[700]),
                    const SizedBox(width: 6),
                    Text(
                      'En attente de votre acceptation',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ],

              if (rdv.clientNotes != null &&
                  rdv.clientNotes!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(rdv.clientNotes!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                ),
              ],

              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('Voir détails',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppConstants.primaryRed,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios,
                    size: 12, color: AppConstants.primaryRed),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoItem(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: Colors.grey[500]),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(fontSize: 12, color: Colors.grey[700])),
    ],
  );
}

// ── Badge statut ──────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

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
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }
}