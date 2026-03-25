import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/rendez_vous_provider.dart';
import '../../models/rendez_vous_model.dart';
import '../../utils/constants.dart';
import '../../services/notification_service.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/review_dialog.dart';
import '../../widgets/report_dialog.dart';

class RendezVousDetailScreen extends StatefulWidget {
  final String rdvId;
  const RendezVousDetailScreen({super.key, required this.rdvId});

  @override
  State<RendezVousDetailScreen> createState() => _RendezVousDetailScreenState();
}

class _RendezVousDetailScreenState extends State<RendezVousDetailScreen>
    with SingleTickerProviderStateMixin {
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
  bool _isSubmittingReview = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    
    _loadCurrentUser().then((_) {
      if (mounted) {
        context.read<RendezVousProvider>().loadRendezVousById(widget.rdvId);
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _currentUserId = map['id']?.toString();
            _userLoaded = true;
          });
        }
      } else {
        if (mounted) setState(() => _userLoaded = true);
      }
    } catch (e) {
      if (mounted) setState(() => _userLoaded = true);
    }
  }

  bool _isPrestataire(RendezVousModel rdv) =>
      _currentUserId != null && _currentUserId == rdv.prestataireId;

  bool _isClient(RendezVousModel rdv) =>
      _currentUserId != null && _currentUserId == rdv.clientId;

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'confirmed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      case 'completed':
        return Icons.verified;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Consumer<RendezVousProvider>(
        builder: (context, prov, _) {
          if (!_userLoaded || (prov.isLoading && prov.selected == null)) {
            return _buildLoadingSkeleton();
          }

          final rdv = prov.selected;
          if (rdv == null) return _buildNotFound(prov.error);

          return FadeTransition(
            opacity: _fadeAnimation,
            child: CustomScrollView(
              slivers: [
                _buildDynamicAppBar(rdv),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildAnimatedStatusCard(rdv),
                      const SizedBox(height: 16),
                      _buildAnimatedInfoCard(rdv),
                      const SizedBox(height: 16),
                      if (rdv.clientNotes != null &&
                          rdv.clientNotes!.isNotEmpty)
                        _buildAnimatedNotesCard(rdv),
                      if (rdv.isCompleted && rdv.hasReview)
                        _buildAnimatedReviewCard(rdv),
                      if (prov.error != null)
                        _buildError(prov.error!),
                      _buildAnimatedActionButtons(rdv),
                      const SizedBox(height: 32),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            backgroundColor: Colors.grey[300],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(color: Colors.grey[300]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicAppBar(RendezVousModel rdv) {
    final statusColor = _getStatusColor(rdv.status);
    return SliverAppBar(
      backgroundColor: AppConstants.primaryRed,
      foregroundColor: Colors.white,
      expandedHeight: 200,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppConstants.primaryRed,
                AppConstants.primaryRed.withOpacity(0.8),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_userLoaded)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isPrestataire(rdv)
                                    ? Icons.engineering
                                    : Icons.person,
                                size: 14,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isPrestataire(rdv)
                                    ? 'Prestataire'
                                    : 'Client',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      Hero(
                        tag: 'service_${rdv.id}',
                        child: Material(
                          color: Colors.transparent,
                          child: Text(
                            rdv.serviceName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getStatusIcon(rdv.status),
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  rdv.statusLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              rdv.entrepriseName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
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
        ),
      ),
    );
  }

  Widget _buildAnimatedStatusCard(RendezVousModel rdv) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).cardColor,
              Theme.of(context).cardColor.withOpacity(0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Statut actuel',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(rdv.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(rdv.status),
                        size: 16,
                        color: _getStatusColor(rdv.status),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        rdv.statusLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(rdv.status),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Créé le',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _shortDate(rdv.createdAt),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedInfoCard(RendezVousModel rdv) {
    final isPresta = _isPrestataire(rdv);
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(Icons.info_outline, 'Détails du rendez-vous'),
            const SizedBox(height: 20),
            _buildAnimatedInfoRow(
              Icons.calendar_today_outlined,
              'Date',
              rdv.formattedDate,
              delay: 0,
            ),
            _buildDivider(),
            _buildAnimatedInfoRow(
              Icons.access_time,
              'Horaire',
              rdv.timeRange,
              delay: 100,
            ),
            _buildDivider(),
            _buildAnimatedInfoRow(
              isPresta ? Icons.person_outline : Icons.business_center_outlined,
              isPresta ? 'Client' : 'Prestataire',
              isPresta ? rdv.clientName : rdv.prestataireName,
              delay: 200,
            ),
            if (rdv.confirmedAt != null) ...[
              _buildDivider(),
              _buildAnimatedInfoRow(
                Icons.check_circle_outline,
                'Confirmé le',
                _shortDateFull(rdv.confirmedAt!),
                delay: 300,
              ),
            ],
            if (rdv.completedAt != null) ...[
              _buildDivider(),
              _buildAnimatedInfoRow(
                Icons.done_all,
                'Terminé le',
                _shortDateFull(rdv.completedAt!),
                delay: 400,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedInfoRow(IconData icon, String label, String value,
      {int delay = 0}) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + delay),
      builder: (context, val, child) {
        return Opacity(opacity: val, child: child);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppConstants.primaryRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: AppConstants.primaryRed),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedNotesCard(RendezVousModel rdv) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue[50]!,
              Colors.blue[100]!,
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notes, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Notes du client',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              rdv.clientNotes!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue[900],
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedReviewCard(RendezVousModel rdv) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.amber[50]!,
              Colors.amber[100]!,
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.amber[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_rate, color: Colors.amber[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Votre note',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.amber[800],
                  ),
                ),
                const Spacer(),
                if (_isClient(rdv) && !(rdv.reviewReported ?? false))
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextButton.icon(
                      onPressed: () => _showReportDialog(rdv),
                      icon: Icon(Icons.flag_outlined,
                          size: 14, color: Colors.red[400]),
                      label: Text(
                        'Signaler',
                        style: TextStyle(fontSize: 11, color: Colors.red[400]),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                StarRating(
                  rating: rdv.reviewRating ?? 0,
                  maxRating: 5,
                  size: 28,
                  enabled: false,
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${rdv.reviewRating}/5',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.amber[900],
                    ),
                  ),
                ),
              ],
            ),
            if (rdv.reviewComment != null && rdv.reviewComment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  rdv.reviewComment!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (rdv.reviewReported ?? false) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag, size: 14, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Signalé - Un modérateur examinera votre signalement',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedActionButtons(RendezVousModel rdv) {
    if (!_userLoaded) return const SizedBox.shrink();

    final isPresta = _isPrestataire(rdv);
    final isClient = _isClient(rdv);

    final canConfirm = isPresta && rdv.isPending;
    final canComplete = isPresta && rdv.isConfirmed;
    final canRefuse = isPresta && rdv.canBeCancelled;
    final canCancelClient = isClient && rdv.canBeCancelled;
    final canReview = isClient && rdv.isCompleted && !rdv.hasReview;

    if (!canConfirm &&
        !canComplete &&
        !canRefuse &&
        !canCancelClient &&
        !canReview) {
      return const SizedBox.shrink();
    }

    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canConfirm) ...[
            _buildAnimatedActionButton(
              label: 'Accepter le rendez-vous',
              icon: Icons.check_circle_outline,
              color: Colors.green,
              onTap: () => _confirm(rdv),
              isConfirm: true,
            ),
            const SizedBox(height: 12),
          ],
          if (canComplete) ...[
            _buildAnimatedActionButton(
              label: 'Marquer comme terminé',
              icon: Icons.done_all,
              color: Colors.blue,
              onTap: () => _complete(rdv),
            ),
            const SizedBox(height: 12),
          ],
          if (canReview) ...[
            _buildAnimatedActionButton(
              label: 'Noter ce service',
              icon: Icons.star_rate,
              color: Colors.amber,
              onTap: () => _showReviewDialog(rdv),
              isReview: true,
            ),
            const SizedBox(height: 12),
          ],
          if (canRefuse)
            _buildAnimatedActionButton(
              label: isPresta && rdv.isPending
                  ? 'Refuser le rendez-vous'
                  : 'Annuler le rendez-vous',
              icon: Icons.cancel_outlined,
              color: Colors.red,
              outlined: true,
              onTap: () => _showCancelDialog(rdv),
            ),
          if (canCancelClient && !isPresta) ...[
            if (canRefuse) const SizedBox(height: 12),
            _buildAnimatedActionButton(
              label: 'Annuler ma demande',
              icon: Icons.event_busy_outlined,
              color: Colors.orange,
              outlined: true,
              onTap: () => _showCancelDialog(rdv),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool outlined = false,
    bool isConfirm = false,
    bool isReview = false,
  }) {
    if (_actionLoading || _isSubmittingReview) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppConstants.primaryRed,
            ),
          ),
        ),
      );
    }

    Widget button;
    if (outlined) {
      button = OutlinedButton.icon(
        onPressed: onTap,
        icon: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: Icon(icon, size: 20),
        ),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    } else {
      button = ElevatedButton.icon(
        onPressed: onTap,
        icon: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: Icon(icon, size: 20),
        ),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }

    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0.95, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: button,
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppConstants.primaryRed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppConstants.primaryRed, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() => Divider(
        height: 1,
        color: Colors.grey[200],
      );

  Widget _buildError(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(color: Colors.red[200]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound(String? error) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        title: const Text('Rendez-vous'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/animations/empty.json',
              width: 200,
              height: 200,
              repeat: false,
            ),
            const SizedBox(height: 24),
            Text(
              error ?? 'Rendez-vous introuvable',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Retour'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReviewDialog(RendezVousModel rdv) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReviewDialog(
        serviceName: rdv.serviceName,
        isLoading: _isSubmittingReview,
        onSubmit: (rating, comment) async {
          setState(() => _isSubmittingReview = true);
          Navigator.pop(ctx);

          final ok = await context.read<RendezVousProvider>().submitReview(
                rdvId: rdv.id,
                rating: rating,
                comment: comment,
              );

          if (mounted) {
            setState(() => _isSubmittingReview = false);
            _showFeedback(
              ok
                  ? 'Merci pour votre avis !'
                  : context.read<RendezVousProvider>().error ?? 'Erreur',
              ok,
            );

            if (ok) {
              await context
                  .read<RendezVousProvider>()
                  .loadRendezVousById(rdv.id);
              _fadeController.reset();
              _fadeController.forward();
            }
          }
        },
      ),
    );
  }

  void _showReportDialog(RendezVousModel rdv) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReportDialog(
        serviceName: rdv.serviceName,
        isLoading: _actionLoading,
        onSubmit: (reason, details) async {
          setState(() => _actionLoading = true);

          final ok = await context.read<RendezVousProvider>().reportReview(
                rdvId: rdv.id,
                reason: reason,
                details: details,
              );

          if (mounted) {
            setState(() => _actionLoading = false);
            _showFeedback(
              ok
                  ? 'Service signalé avec succès'
                  : context.read<RendezVousProvider>().error ?? 'Erreur',
              ok,
            );

            if (ok) {
              await context
                  .read<RendezVousProvider>()
                  .loadRendezVousById(rdv.id);
              _fadeController.reset();
              _fadeController.forward();
            }
          }
        },
      ),
    );
  }

  Future<void> _confirm(RendezVousModel rdv) async {
    setState(() => _actionLoading = true);
    final ok = await context
        .read<RendezVousProvider>()
        .confirmRendezVous(rdv.id);
    if (mounted) {
      setState(() => _actionLoading = false);
      _showFeedback(
        ok
            ? 'Rendez-vous accepté !'
            : context.read<RendezVousProvider>().error ?? 'Erreur',
        ok,
      );

      if (ok) {
        final updated = context.read<RendezVousProvider>().selected;
        final target = updated ?? rdv;

        await NotificationService().scheduleRdvReminder(
          rdvId: target.id,
          rdvDate: target.date,
          rdvTime: target.startTime,
          serviceName: target.serviceName,
          isPrestataire: true,
        );

        await NotificationService().scheduleCompleteReminder(
          rdvId: target.id,
          rdvDate: target.date,
          rdvEndTime: target.endTime,
          serviceName: target.serviceName,
        );

        _fadeController.reset();
        _fadeController.forward();

        debugPrint('[RDV] Rappels planifiés pour RDV ${target.id}');
      }
    }
  }

  Future<void> _complete(RendezVousModel rdv) async {
    setState(() => _actionLoading = true);
    final ok = await context
        .read<RendezVousProvider>()
        .completeRendezVous(rdv.id);
    if (mounted) {
      setState(() => _actionLoading = false);
      _showFeedback(
        ok
            ? 'Rendez-vous marqué comme terminé !'
            : context.read<RendezVousProvider>().error ?? 'Erreur',
        ok,
      );

      if (ok) {
        final updated = context.read<RendezVousProvider>().selected;
        final target = updated ?? rdv;

        await NotificationService().cancelRdvReminder(target.id);

        await NotificationService().showReviewRequestNotification(
          rdvId: target.id,
          serviceName: target.serviceName,
        );

        _fadeController.reset();
        _fadeController.forward();

        debugPrint('[RDV] Notification "noter" envoyée pour RDV ${target.id}');
      }
    }
  }

  void _showCancelDialog(RendezVousModel rdv) {
    final isPresta = _isPrestataire(rdv);
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          isPresta && rdv.isPending
              ? 'Refuser le rendez-vous'
              : 'Annuler le rendez-vous',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 48),
            const SizedBox(height: 12),
            Text(
              'Cette action est irréversible.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Raison (optionnel)',
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
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
                  .cancelRendezVous(rdv.id, reason: ctrl.text.trim());
              if (mounted) {
                setState(() => _actionLoading = false);
                _showFeedback(
                  ok
                      ? 'Opération effectuée.'
                      : context.read<RendezVousProvider>().error ?? 'Erreur',
                  ok,
                );
                if (ok) {
                  await NotificationService().cancelRdvReminder(rdv.id);
                  _fadeController.reset();
                  _fadeController.forward();
                  debugPrint('[RDV] Rappels annulés pour RDV ${rdv.id}');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _showFeedback(String msg, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: success ? Colors.green[700] : Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _shortDateFull(DateTime d) =>
      '${_shortDate(d)} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool large;
  const _StatusBadge({required this.status, this.large = false});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'pending' => ('En attente', Colors.orange[50]!, Colors.orange[700]!),
      'confirmed' => ('Confirmé', Colors.green[50]!, Colors.green[700]!),
      'cancelled' => ('Annulé', Colors.red[50]!, Colors.red[700]!),
      'completed' => ('Terminé', Colors.grey[100]!, Colors.grey[700]!),
      _ => (status, Colors.grey[100]!, Colors.grey[700]!),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 14 : 10, vertical: large ? 6 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: large ? 13 : 11,
            fontWeight: FontWeight.w600,
            color: fg),
      ),
    );
  }
}