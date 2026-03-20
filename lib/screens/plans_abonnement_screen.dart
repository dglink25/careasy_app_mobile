import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as wv;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';

// ─── Palette & constantes design ─────────────────────────────────────────────
const _kRed    = AppConstants.primaryRed;
const _kGreen  = Color(0xFF22C55E);
const _kBlue   = Color(0xFF3B82F6);
const _kAmber  = Color(0xFFF59E0B);
const _kRadius = 20.0;
const _kRadiusLg = 28.0;

// ═══════════════════════════════════════════════════════════════════════════════
//  ÉCRAN PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════════
class PlansAbonnementScreen extends StatefulWidget {
  const PlansAbonnementScreen({super.key});

  @override
  State<PlansAbonnementScreen> createState() => _PlansAbonnementScreenState();
}

class _PlansAbonnementScreenState extends State<PlansAbonnementScreen>
    with TickerProviderStateMixin {
  // ── Storage ──────────────────────────────────────────────────────────────────
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Controllers ───────────────────────────────────────────────────────────────
  late final TabController _tabCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── Données ───────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _plans       = [];
  Map<String, dynamic>?      _abonnement  = null;
  List<Map<String, dynamic>> _historique  = [];

  // ── États ─────────────────────────────────────────────────────────────────────
  bool _loadingPlans = true;
  bool _loadingAbonnement = true;
  bool _initiating = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _shimmerCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Chargement ────────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    _fadeCtrl.reset();
    await Future.wait([_loadPlans(), _loadAbonnements()]);
    _fadeCtrl.forward();
  }

  Future<void> _loadPlans() async {
    _set(() => _loadingPlans = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/plans'),
        headers: _hdr(token),
      );
      if (res.statusCode == 200) {
        final b = jsonDecode(res.body);
        final l = (b['data'] ?? b) as List;
        _set(() => _plans = l.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
    finally { _set(() => _loadingPlans = false); }
  }

  Future<void> _loadAbonnements() async {
    _set(() => _loadingAbonnement = true);
    try {
      final token = await _storage.read(key: 'auth_token');

      final ar = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/abonnements/actif'),
        headers: _hdr(token),
      );
      if (ar.statusCode == 200) {
        final b = jsonDecode(ar.body);
        _set(() => _abonnement =
            b['success'] == true ? Map<String, dynamic>.from(b['data'] ?? {}) : null);
      }

      final hr = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/abonnements'),
        headers: _hdr(token),
      );
      if (hr.statusCode == 200) {
        final b = jsonDecode(hr.body);
        final l = (b['data'] ?? []) as List;
        _set(() => _historique = l.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
    finally { _set(() => _loadingAbonnement = false); }
  }

  // ── Paiement ──────────────────────────────────────────────────────────────────
  Future<void> _initierPaiement(Map<String, dynamic> plan) async {
    _set(() => _initiating = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/paiements/initier/${plan['id']}'),
        headers: _hdr(token, json: true),
        body: jsonEncode({}),
      );

      final b = jsonDecode(res.body);
      if (res.statusCode == 200 && b['success'] == true) {
        final url = b['data']?['payment_url'] as String?;
        final ref = b['data']?['paiement']?['reference'] as String?;

        if (url == null) { _err('URL de paiement introuvable'); return; }

        _set(() => _initiating = false);
        if (!mounted) return;

        HapticFeedback.lightImpact();

        final result = await Navigator.push<_PayResult>(
          context,
          PageRouteBuilder(
            pageBuilder: (_, a1, a2) => _WebViewScreen(
              url: url, reference: ref ?? '',
              planName: plan['name'] ?? '', montant: plan['formatted_price'] ?? '',
            ),
            transitionsBuilder: (_, a, __, child) => SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 420),
          ),
        );

        if (result == null) return;
        if (result.success) {
          await _loadAbonnements();
          _showResultSheet(success: true, ref: result.reference, planName: plan['name'] ?? '');
        } else {
          _showResultSheet(success: false, ref: result.reference, planName: plan['name'] ?? '');
        }
        return;
      }
      _err(b['message'] ?? 'Erreur d\'initiation du paiement');
    } catch (_) { _err('Erreur de connexion'); }
    finally { if (mounted) _set(() => _initiating = false); }
  }

  // ── Result bottom sheet ────────────────────────────────────────────────────────
  void _showResultSheet({required bool success, required String ref, required String planName}) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => _ResultSheet(
        success: success, reference: ref, planName: planName,
        onContinue: () {
          Navigator.pop(context);
          if (success) _tabCtrl.animateTo(1);
        },
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────
  Map<String, String> _hdr(String? token, {bool json = false}) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
  };
  void _set(VoidCallback fn) { if (mounted) setState(fn); }
  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final hp = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            backgroundColor: _kRed,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: _loadAll,
                tooltip: 'Actualiser',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _AppBarBackground(sw: sw),
              title: const Text('Plans & Abonnements',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              titlePadding: const EdgeInsets.only(left: 52, bottom: 58),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: Container(
                color: _kRed,
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  tabs: const [
                    Tab(icon: Icon(Icons.grid_view_rounded, size: 16), text: 'Plans'),
                    Tab(icon: Icon(Icons.verified_user_outlined, size: 16), text: 'Abonnement'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: FadeTransition(
          opacity: _fadeAnim,
          child: TabBarView(
            controller: _tabCtrl,
            children: [_tabPlans(sw), _tabAbonnement(sw)],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  TAB PLANS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _tabPlans(double sw) {
    if (_loadingPlans) return _shimmerList(sw);
    if (_plans.isEmpty) return _emptyState(
      icon: Icons.rocket_launch_outlined,
      title: 'Aucun plan disponible',
      sub: 'Revenez plus tard ou actualisez la page.',
      action: FilledButton.icon(
        onPressed: _loadPlans,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Réessayer'),
        style: FilledButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white),
      ),
    );

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _kRed,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 40 + MediaQuery.of(context).padding.bottom),
        itemCount: _plans.length,
        itemBuilder: (_, i) => _AnimatedPlanCard(
          plan: _plans[i],
          index: i,
          currentPlanId: _abonnement?['plan']?['id']?.toString(),
          initiating: _initiating,
          onSubscribe: _confirmDialog,
        ),
      ),
    );
  }

  // ── Dialog de confirmation ────────────────────────────────────────────────────
  void _confirmDialog(Map<String, dynamic> plan) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => _ConfirmSheet(
        plan: plan,
        onConfirm: () {
          Navigator.pop(context);
          _initierPaiement(plan);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  TAB ABONNEMENT
  // ═══════════════════════════════════════════════════════════════════════
  Widget _tabAbonnement(double sw) {
    if (_loadingAbonnement) return _shimmerList(sw);
    return RefreshIndicator(
      onRefresh: _loadAbonnements,
      color: _kRed,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 20, 16, 40 + MediaQuery.of(context).padding.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _abonnement != null ? _ActiveCard(a: _abonnement!) : _NoAbonnementCard(onTap: () => _tabCtrl.animateTo(0)),
          if (_historique.isNotEmpty) ...[
            const SizedBox(height: 32),
            _SectionHeader(
              title: 'Historique',
              trailing: _Chip('${_historique.length}', Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            ..._historique.asMap().entries.map((e) => _AnimatedHistorique(item: e.value, index: e.key)),
          ],
        ]),
      ),
    );
  }

  // ── Shimmer ────────────────────────────────────────────────────────────────────
  Widget _shimmerList(double sw) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
    itemCount: 3,
    itemBuilder: (_, i) => _ShimmerCard(ctrl: _shimmerCtrl),
  );

  Widget _emptyState({
    required IconData icon, required String title, required String sub, Widget? action,
  }) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
        child: Icon(icon, size: 40, color: Colors.grey.shade400),
      ),
      const SizedBox(height: 20),
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(sub, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.5)),
      if (action != null) ...[const SizedBox(height: 24), action],
    ]),
  ));
}

// ═══════════════════════════════════════════════════════════════════════════════
//  AppBar background décoratif
// ═══════════════════════════════════════════════════════════════════════════════
class _AppBarBackground extends StatelessWidget {
  final double sw;
  const _AppBarBackground({required this.sw});
  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE63946), Color(0xFFc1121f)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
      ),
      // Cercles décoratifs
      Positioned(top: -30, right: -20,
        child: Container(width: 130, height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.07),
          ))),
      Positioned(bottom: 20, right: sw * 0.35,
        child: Container(width: 60, height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.05),
          ))),
      Positioned(top: 20, left: sw * 0.45,
        child: Container(width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.06),
          ))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Plan card animée
// ═══════════════════════════════════════════════════════════════════════════════
class _AnimatedPlanCard extends StatefulWidget {
  final Map<String, dynamic> plan;
  final int index;
  final String? currentPlanId;
  final bool initiating;
  final void Function(Map<String, dynamic>) onSubscribe;
  const _AnimatedPlanCard({
    required this.plan, required this.index, required this.currentPlanId,
    required this.initiating, required this.onSubscribe,
  });
  @override
  State<_AnimatedPlanCard> createState() => _AnimatedPlanCardState();
}

class _AnimatedPlanCardState extends State<_AnimatedPlanCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500 + widget.index * 80),
    );
    _scale = Tween(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _slide = Tween(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.index * 80), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: child),
      ),
      child: _PlanCard(
        plan: widget.plan,
        currentPlanId: widget.currentPlanId,
        initiating: widget.initiating,
        onSubscribe: widget.onSubscribe,
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final String? currentPlanId;
  final bool initiating;
  final void Function(Map<String, dynamic>) onSubscribe;
  const _PlanCard({required this.plan, required this.currentPlanId, required this.initiating, required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    final features  = (plan['features_list'] ?? plan['features'] ?? []) as List;
    final price     = plan['formatted_price'] ?? '${plan['price']} F CFA';
    final duration  = plan['duration_text']   ?? '${plan['duration_days']} jours';
    final isPopular = (plan['sort_order'] ?? 99) == 1;
    final isCurrent = currentPlanId == plan['id']?.toString();
    final isDark    = Theme.of(context).brightness == Brightness.dark;

    final borderCol = isCurrent ? _kGreen.withOpacity(0.6)
        : isPopular ? _kRed.withOpacity(0.4)
        : (isDark ? Colors.white12 : Colors.grey.shade200);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(_kRadiusLg),
        border: Border.all(color: borderCol, width: isCurrent || isPopular ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: (isCurrent ? _kGreen : isPopular ? _kRed : Colors.black).withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 18, offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kRadiusLg - 1),
        child: Column(children: [
          // ── Header gradient ──────────────────────────
          _CardHeader(plan: plan, price: price, duration: duration,
              isCurrent: isCurrent, isPopular: isPopular),

          // ── Features ─────────────────────────────────
          if (features.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Column(children: [
                ...features.take(6).map<Widget>((f) => _FeatureRow(text: f.toString())),
              ]),
            ),

          const SizedBox(height: 16),

          // ── Bouton ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: isCurrent
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle, size: 16, color: _kGreen),
                      label: const Text('Plan actuel',
                          style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kGreen, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: initiating ? null : () => onSubscribe(plan),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kRed, foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: initiating
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(Icons.payment_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text('Souscrire · $price',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            ]),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final Map<String, dynamic> plan;
  final String price, duration;
  final bool isCurrent, isPopular;
  const _CardHeader({required this.plan, required this.price, required this.duration, required this.isCurrent, required this.isPopular});

  @override
  Widget build(BuildContext context) {
    final bg = isCurrent
        ? _kGreen.withOpacity(0.08)
        : isPopular
            ? _kRed.withOpacity(0.06)
            : Theme.of(context).scaffoldBackgroundColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(color: bg),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(plan['name'] ?? '',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            if (isCurrent)
              _Chip('Actif', _kGreen)
            else if (isPopular)
              _Chip('⭐ Populaire', _kRed),
          ]),
          if ((plan['description'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(plan['description'] ?? '',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.4)),
            ),
        ])),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(price, style: TextStyle(
              fontSize: 21, fontWeight: FontWeight.w900,
              color: isCurrent ? _kGreen : _kRed,
              letterSpacing: -0.5)),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(duration, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String text;
  const _FeatureRow({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Container(
        width: 20, height: 20,
        decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 12, color: _kGreen),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.3))),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Confirmation bottom sheet
// ═══════════════════════════════════════════════════════════════════════════════
class _ConfirmSheet extends StatelessWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onConfirm;
  const _ConfirmSheet({required this.plan, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final price    = plan['formatted_price'] ?? '${plan['price']} F CFA';
    final duration = plan['duration_text']   ?? '${plan['duration_days']} jours';
    final features = (plan['features_list'] ?? plan['features'] ?? []) as List;
    final isDark   = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Poignée
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Titre
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: _kRed.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.payment_rounded, color: _kRed, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Confirmer l\'abonnement',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                Text(plan['name'] ?? '',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ])),
            ]),

            const SizedBox(height: 20),

            // Résumé prix
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_kRed.withOpacity(0.07), _kRed.withOpacity(0.03)]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kRed.withOpacity(0.2)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Montant total', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 2),
                  Text(price, style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900, color: _kRed, letterSpacing: -0.5)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Durée', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 2),
                  Text(duration, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ]),
            ),

            const SizedBox(height: 16),

            // Features résumé
            if (features.isNotEmpty) ...[
              Text('Inclus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ...features.take(4).map<Widget>((f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle, size: 12, color: _kGreen),
                    const SizedBox(width: 4),
                    Text(f.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                  ]),
                )),
              ]),
              const SizedBox(height: 16),
            ],

            // Sécurité / modes paiement
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.verified_user_outlined, size: 14, color: _kGreen),
                  const SizedBox(width: 5),
                  Text('Paiement 100 % sécurisé · FedaPay',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                ]),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _PayBadge('MTN Money', const Color(0xFFFFCC00)),
                  const SizedBox(width: 8),
                  _PayBadge('Moov Money', const Color(0xFF0066CC)),
                  const SizedBox(width: 8),
                  _PayBadge('Carte bancaire', Colors.grey.shade600),
                ]),
              ]),
            ),

            const SizedBox(height: 22),

            // Boutons
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Annuler', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed, foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.lock_open_rounded, size: 16),
                    SizedBox(width: 8),
                    Text('Payer maintenant', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _PayBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _PayBadge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800)),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Carte abonnement actif
// ═══════════════════════════════════════════════════════════════════════════════
class _ActiveCard extends StatefulWidget {
  final Map<String, dynamic> a;
  const _ActiveCard({required this.a});
  @override
  State<_ActiveCard> createState() => _ActiveCardState();
}
class _ActiveCardState extends State<_ActiveCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }
  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final a         = widget.a;
    final plan      = Map<String, dynamic>.from(a['plan'] ?? {});
    final jours     = (a['jours_restants'] ?? 0) as num;
    final dateFin   = a['date_fin'] ?? '';
    final estEssai  = a['est_essai'] == true || a['type'] == 'trial';
    final total     = (plan['duration_days'] ?? 30) as num;
    final progress  = (jours / total).clamp(0.0, 1.0).toDouble();

    final gradColors = estEssai
        ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
        : [const Color(0xFFE63946), const Color(0xFFc1121f)];

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(_kRadiusLg),
          boxShadow: [
            BoxShadow(
              color: gradColors.first.withOpacity(0.28 + _pulse.value * 0.12),
              blurRadius: 24 + _pulse.value * 8,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Titre
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
              child: Icon(estEssai ? Icons.science_outlined : Icons.verified_outlined,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(estEssai ? 'Période d\'essai' : plan['name'] ?? 'Abonnement',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              Text(estEssai ? 'Gratuit · 30 jours' : a['montant_formate'] ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('Actif', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),

          const SizedBox(height: 22),

          // Progression
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$jours jour(s) restant(s)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Expire $dateFin',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 10),
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 10,
              ),
            ),
          ]),

          const SizedBox(height: 20),
          const Divider(color: Colors.white24, thickness: 1),
          const SizedBox(height: 16),

          // Stats
          Row(children: [
            _StatCell(icon: Icons.home_repair_service_outlined, value: '${plan['max_services'] ?? '∞'}', label: 'Services'),
            _DivV(),
            _StatCell(icon: Icons.people_outline, value: '${plan['max_employees'] ?? '∞'}', label: 'Employés'),
            _DivV(),
            _StatCell(
              icon: plan['has_analytics'] == true ? Icons.bar_chart : Icons.bar_chart_outlined,
              value: plan['has_analytics'] == true ? 'Oui' : 'Non',
              label: 'Analytics',
            ),
            _DivV(),
            _StatCell(
              icon: plan['has_priority_support'] == true ? Icons.headset_mic : Icons.headset_mic_outlined,
              value: plan['has_priority_support'] == true ? 'Oui' : 'Non',
              label: 'Support',
            ),
          ]),
        ]),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon; final String value, label;
  const _StatCell({required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Icon(icon, color: Colors.white70, size: 15),
    const SizedBox(height: 3),
    Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w500)),
  ]));
}
class _DivV extends StatelessWidget {
  const _DivV();
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 32, color: Colors.white.withOpacity(0.2));
}

class _NoAbonnementCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NoAbonnementCard({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(_kRadiusLg),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.grey.shade100, Colors.grey.shade200]),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.rocket_launch_outlined, size: 38, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 18),
        const Text('Aucun abonnement actif',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Choisissez un plan pour accéder à toutes les fonctionnalités de CarEasy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.5)),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.grid_view_rounded, size: 17),
            label: const Text('Voir les plans', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed, foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Historique item animé
// ═══════════════════════════════════════════════════════════════════════════════
class _AnimatedHistorique extends StatefulWidget {
  final Map<String, dynamic> item;
  final int index;
  const _AnimatedHistorique({required this.item, required this.index});
  @override
  State<_AnimatedHistorique> createState() => _AnimatedHistoriqueState();
}
class _AnimatedHistoriqueState extends State<_AnimatedHistorique>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _ctrl.forward();
    });
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: _HistoriqueItem(item: widget.item),
  );
}

class _HistoriqueItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _HistoriqueItem({required this.item});
  @override
  Widget build(BuildContext context) {
    final plan      = Map<String, dynamic>.from(item['plan'] ?? {});
    final statut    = item['statut'] ?? 'inconnu';
    final estEssai  = item['est_essai'] == true || item['type'] == 'trial';
    final isDark    = Theme.of(context).brightness == Brightness.dark;

    Color sc; IconData si; String sl;
    switch (statut) {
      case 'actif':  sc = _kGreen;         si = Icons.check_circle_outline; sl = 'Actif'; break;
      case 'expire': sc = Colors.grey;     si = Icons.schedule_outlined;    sl = 'Expiré'; break;
      case 'annule': sc = Colors.red;      si = Icons.cancel_outlined;      sl = 'Annulé'; break;
      default:       sc = _kAmber;         si = Icons.pending_outlined;     sl = statut;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: (estEssai ? _kBlue : _kRed).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(estEssai ? Icons.science_outlined : Icons.subscriptions_outlined,
              color: estEssai ? _kBlue : _kRed, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(estEssai ? 'Période d\'essai' : plan['name'] ?? 'Abonnement',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${item['date_debut'] ?? ''} → ${item['date_fin'] ?? ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(si, size: 11, color: sc),
              const SizedBox(width: 3),
              Text(sl, style: TextStyle(fontSize: 11, color: sc, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 4),
          Text(estEssai ? 'Gratuit' : (item['montant_formate'] ?? ''),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Result bottom sheet
// ═══════════════════════════════════════════════════════════════════════════════
class _ResultSheet extends StatefulWidget {
  final bool success;
  final String reference, planName;
  final VoidCallback onContinue;
  const _ResultSheet({required this.success, required this.reference, required this.planName, required this.onContinue});
  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}
class _ResultSheetState extends State<_ResultSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale, _fade;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scale = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.success ? _kGreen : Colors.red.shade600;
    final icon  = widget.success ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 20),
          width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            // Icône animée
            FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [color.withOpacity(0.2), color.withOpacity(0.05)]),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withOpacity(0.3), width: 2),
                  ),
                  child: Icon(icon, color: color, size: 50),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(widget.success ? '🎉 Paiement réussi !' : 'Paiement échoué',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4,
                    color: widget.success ? null : Colors.red.shade700)),
            const SizedBox(height: 10),
            Text(
              widget.success
                  ? 'Votre abonnement "${widget.planName}" est maintenant actif. Profitez de toutes les fonctionnalités !'
                  : 'Le paiement n\'a pas pu aboutir. Vérifiez votre solde ou changez de moyen de paiement.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.55),
            ),
            const SizedBox(height: 8),

            // Référence
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_outlined, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 5),
                Text('Réf : ${widget.reference}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
              ]),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: widget.onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.success ? _kGreen : _kRed,
                  foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  widget.success ? 'Voir mon abonnement' : 'Réessayer',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),

            if (!widget.success) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Fermer', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Section header
// ═══════════════════════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final String title; final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 16,
        decoration: BoxDecoration(color: _kRed, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
    const Spacer(),
    if (trailing != null) trailing!,
  ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Chip générique
// ═══════════════════════════════════════════════════════════════════════════════
class _Chip extends StatelessWidget {
  final String label; final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Shimmer card skeleton
// ═══════════════════════════════════════════════════════════════════════════════
class _ShimmerCard extends StatelessWidget {
  final AnimationController ctrl;
  const _ShimmerCard({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final shimmer = LinearGradient(
          begin: Alignment.topLeft, end: Alignment.centerRight,
          stops: const [0.0, 0.4, 0.8, 1.0],
          colors: isDark
              ? [Colors.white.withOpacity(0.03), Colors.white.withOpacity(0.08),
                 Colors.white.withOpacity(0.03), Colors.white.withOpacity(0.03)]
              : [Colors.grey.shade100, Colors.grey.shade200, Colors.grey.shade100, Colors.grey.shade100],
          transform: GradientRotation(ctrl.value * 2 * math.pi * 0.5),
        );
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(_kRadiusLg),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(width: 110, height: 18, decoration: BoxDecoration(gradient: shimmer, borderRadius: BorderRadius.circular(6))),
              Container(width: 70, height: 22, decoration: BoxDecoration(gradient: shimmer, borderRadius: BorderRadius.circular(6))),
            ]),
            const SizedBox(height: 10),
            Container(width: 180, height: 12, decoration: BoxDecoration(gradient: shimmer, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 20),
            ...List.generate(3, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(height: 12, width: double.infinity,
                  decoration: BoxDecoration(gradient: shimmer, borderRadius: BorderRadius.circular(4))),
            )),
            const SizedBox(height: 12),
            Container(height: 46, width: double.infinity,
                decoration: BoxDecoration(gradient: shimmer, borderRadius: BorderRadius.circular(12))),
          ]),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Modèle résultat paiement
// ═══════════════════════════════════════════════════════════════════════════════
class _PayResult {
  final bool   success;
  final String reference;
  const _PayResult({required this.success, required this.reference});
}

// ═══════════════════════════════════════════════════════════════════════════════
//  WebView FedaPay in-app
// ═══════════════════════════════════════════════════════════════════════════════
class _WebViewScreen extends StatefulWidget {
  final String url, reference, planName, montant;
  const _WebViewScreen({required this.url, required this.reference, required this.planName, required this.montant});
  @override
  State<_WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<_WebViewScreen> {
  wv.InAppWebViewController? _ctrl;
  double  _progress   = 0;
  bool    _loaded     = false;
  bool    _doneCalled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kRed,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _askClose(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Paiement sécurisé',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          Text(widget.planName,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_rounded, size: 14),
              const SizedBox(width: 4),
              Text(widget.montant,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_loaded ? 0 : 3),
          child: _loaded
              ? const SizedBox.shrink()
              : LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 3,
                ),
        ),
      ),
      body: Stack(children: [
        wv.InAppWebView(
          initialUrlRequest: wv.URLRequest(url: wv.WebUri(widget.url)),
          initialSettings: wv.InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            useShouldOverrideUrlLoading: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
          ),
          onWebViewCreated: (c) => _ctrl = c,
          onProgressChanged: (_, p) => setState(() => _progress = p / 100.0),
          onLoadStop: (_, url) {
            setState(() => _loaded = true);
            _check(url?.toString() ?? '');
          },
          shouldOverrideUrlLoading: (_, nav) async {
            _check(nav.request.url?.toString() ?? '');
            return wv.NavigationActionPolicy.ALLOW;
          },
        ),

        // Overlay chargement initial
        AnimatedOpacity(
          opacity: _loaded ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          child: IgnorePointer(
            ignoring: _loaded,
            child: Container(
              color: Colors.white,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_kRed, Color(0xFFc1121f)]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: _kRed.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.payment_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 22),
                const Text('Chargement du paiement…',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Connexion sécurisée à FedaPay',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 24),
                SizedBox(width: 140,
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(_kRed),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  void _check(String url) {
    if (_doneCalled || url.isEmpty) return;
    if (url.contains('paiement/success') || url.contains('status=approved') ||
        url.contains(AppConstants.appCallbackScheme + '://')) {
      _finish(true);
    } else if (url.contains('paiement/cancel') || url.contains('status=declined') ||
        url.contains('status=canceled') || url.contains('status=failed')) {
      _finish(false);
    }
  }

  void _finish(bool success) {
    if (_doneCalled || !mounted) return;
    _doneCalled = true;
    Navigator.pop(context, _PayResult(success: success, reference: widget.reference));
  }

  Future<void> _askClose(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Quitter le paiement ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text('Le paiement n\'est pas encore finalisé. Voulez-vous quitter ?',
            style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Continuer', style: TextStyle(color: _kRed, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            child: Text('Quitter', style: TextStyle(color: Colors.grey.shade600)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _finish(false);
  }
}