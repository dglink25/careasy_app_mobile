import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../../providers/rendez_vous_provider.dart';
import '../../models/rendez_vous_model.dart';
import '../../utils/constants.dart';
import '../../widgets/app_bottom_nav.dart';
import 'rendez_vous_detail_screen.dart';
import '../carai_screen.dart';

// ─── Palette ────────────────────────────────────────────────────────────────
const Color _kRed = AppConstants.primaryRed;
const Color _kGreen = Color(0xFF22C55E);
const Color _kAmber = Color(0xFFF59E0B);
const Color _kBlue = Color(0xFF3B82F6);
const Color _kPurple = Color(0xFF8B5CF6);

// ─── Vues disponibles ───────────────────────────────────────────────────────
enum _CalView { day, week, month }

class RendezVousListScreen extends StatefulWidget {
  const RendezVousListScreen({super.key});
  @override
  State<RendezVousListScreen> createState() => _RendezVousListScreenState();
}

class _RendezVousListScreenState extends State<RendezVousListScreen>
    with TickerProviderStateMixin {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String? _currentUserId;
  String? _userRole;

  // ── Vue calendrier ──────────────────────────────────────────────────────
  _CalView _view = _CalView.week;
  DateTime _anchor = DateTime.now();
  DateTime _today = DateTime.now();

  // ── Filtre statut ────────────────────────────────────────────────────────
  String _statusFilter = 'all';

  // ── Animation ────────────────────────────────────────────────────────────
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── Tab controller ────────────────────────────────────────────────────────
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: 1);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() => _view = _CalView.values[_tabCtrl.index]);
        _fadeCtrl.forward(from: 0);
      }
    });

    _loadCurrentUser().then((_) {
      if (mounted) context.read<RendezVousProvider>().loadRendezVous();
      _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty && mounted) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          _currentUserId = map['id']?.toString();
          _userRole = map['role']?.toString();
        });
      }
    } catch (_) {}
  }

  bool _isPrestataire(RendezVousModel rdv) =>
      _currentUserId != null && _currentUserId == rdv.prestataireId;

  void _prev() {
    setState(() {
      switch (_view) {
        case _CalView.day:
          _anchor = _anchor.subtract(const Duration(days: 1));
          break;
        case _CalView.week:
          _anchor = _anchor.subtract(const Duration(days: 7));
          break;
        case _CalView.month:
          _anchor = DateTime(_anchor.year, _anchor.month - 1, 1);
          break;
      }
    });
    _fadeCtrl.forward(from: 0);
  }

  void _next() {
    setState(() {
      switch (_view) {
        case _CalView.day:
          _anchor = _anchor.add(const Duration(days: 1));
          break;
        case _CalView.week:
          _anchor = _anchor.add(const Duration(days: 7));
          break;
        case _CalView.month:
          _anchor = DateTime(_anchor.year, _anchor.month + 1, 1);
          break;
      }
    });
    _fadeCtrl.forward(from: 0);
  }

  void _goToday() {
    setState(() => _anchor = _today);
    _fadeCtrl.forward(from: 0);
  }

  List<RendezVousModel> _filterByPeriod(List<RendezVousModel> all) {
    DateTime start, end;
    switch (_view) {
      case _CalView.day:
        start = DateTime(_anchor.year, _anchor.month, _anchor.day);
        end = start.add(const Duration(days: 1));
        break;
      case _CalView.week:
        final wd = _anchor.weekday;
        start = _anchor.subtract(Duration(days: wd - 1));
        start = DateTime(start.year, start.month, start.day);
        end = start.add(const Duration(days: 7));
        break;
      case _CalView.month:
        start = DateTime(_anchor.year, _anchor.month, 1);
        end = DateTime(_anchor.year, _anchor.month + 1, 1);
        break;
    }

    return all.where((r) {
      try {
        final d = DateTime.parse(r.date);
        final inPeriod = !d.isBefore(start) && d.isBefore(end);
        if (!inPeriod) return false;
        if (_statusFilter == 'all') return true;
        return r.status == _statusFilter;
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) {
        final dc = a.date.compareTo(b.date);
        if (dc != 0) return dc;
        return a.startTime.compareTo(b.startTime);
      });
  }

  String get _periodLabel {
    const months = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', 'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];
    switch (_view) {
      case _CalView.day:
        const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
        return '${days[_anchor.weekday - 1]} ${_anchor.day} ${months[_anchor.month - 1]} ${_anchor.year}';
      case _CalView.week:
        final wd = _anchor.weekday;
        final mon = _anchor.subtract(Duration(days: wd - 1));
        final sun = mon.add(const Duration(days: 6));
        if (mon.month == sun.month) {
          return '${mon.day} – ${sun.day} ${months[mon.month - 1]} ${mon.year}';
        }
        return '${mon.day} ${months[mon.month - 1]} – ${sun.day} ${months[sun.month - 1]} ${mon.year}';
      case _CalView.month:
        return '${months[_anchor.month - 1]} ${_anchor.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
      body: Consumer<RendezVousProvider>(
        builder: (ctx, prov, _) {
          final filtered = _filterByPeriod(prov.rendezVous);
          return Column(
            children: [
              _buildHeader(prov),
              _buildViewTabs(),
              _buildPeriodNav(),
              _buildStatusFilters(),
              if (prov.error != null) _buildErrorBanner(prov.error!),
              Expanded(
                child: prov.isLoading && prov.rendezVous.isEmpty
                    ? _buildShimmer()
                    : FadeTransition(
                        opacity: _fadeAnim,
                        child: filtered.isEmpty
                            ? _buildEmpty()
                            : _view == _CalView.month
                                ? _buildMonthGrid(prov.rendezVous)
                                : _buildList(filtered),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: const CarAIFab(),
    );
  }

  Widget _buildHeader(RendezVousProvider prov) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kRed, Color(0xFFc1121f)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Version responsive pour petits écrans
              if (constraints.maxWidth < 450) {
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _headerChip(Icons.schedule_outlined, '${prov.countPending}', 'Attente', _kAmber),
                        _headerChip(Icons.check_circle_outline, '${prov.countConfirmed}', 'Confirmés', _kGreen),
                        _headerChip(Icons.done_all_outlined, '${prov.countCompleted}', 'Terminés', Colors.white70),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _iconBtn(Icons.refresh_rounded, () => prov.loadRendezVous()),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _goToday,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: const Text(
                              "Aujourd'hui",
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              // Version normale
              return Row(
                children: [
                  _headerChip(Icons.schedule_outlined, '${prov.countPending}', 'Attente', _kAmber),
                  const SizedBox(width: 8),
                  _headerChip(Icons.check_circle_outline, '${prov.countConfirmed}', 'Confirmés', _kGreen),
                  const SizedBox(width: 8),
                  _headerChip(Icons.done_all_outlined, '${prov.countCompleted}', 'Terminés', Colors.white70),
                  const Spacer(),
                  _iconBtn(Icons.refresh_rounded, () => prov.loadRendezVous()),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _goToday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: const Text(
                        "Aujourd'hui",
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _headerChip(IconData icon, String count, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 8),
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildViewTabs() {
    return Container(
      color: _kRed,
      child: TabBar(
        controller: _tabCtrl,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: const [
          Tab(text: 'Jour'),
          Tab(text: 'Semaine'),
          Tab(text: 'Mois'),
        ],
      ),
    );
  }

  Widget _buildPeriodNav() {
    final bool isToday = _view == _CalView.day &&
        _anchor.year == _today.year &&
        _anchor.month == _today.month &&
        _anchor.day == _today.day;

    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _navArrow(Icons.chevron_left, _prev),
          Expanded(
            child: GestureDetector(
              onTap: _goToday,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isToday)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _kRed,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Auj',
                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          _periodLabel,
                          style: TextStyle(
                            fontSize: constraints.maxWidth < 380 ? 11 : 13,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          _navArrow(Icons.chevron_right, _next),
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: _kRed),
      ),
    );
  }

  Widget _buildStatusFilters() {
    final filters = [
      ('all', 'Tous', Icons.list_alt_rounded, Colors.grey),
      ('pending', 'Attente', Icons.hourglass_top_rounded, _kAmber),
      ('confirmed', 'Confirmés', Icons.check_circle_rounded, _kGreen),
      ('cancelled', 'Annulés', Icons.cancel_rounded, Colors.red),
      ('completed', 'Terminés', Icons.done_all_rounded, _kBlue),
    ];
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final sel = _statusFilter == f.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() {
                  _statusFilter = f.$1;
                  _fadeCtrl.forward(from: 0);
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? f.$4.withOpacity(0.15) : Colors.grey.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? f.$4 : Colors.grey.withOpacity(0.2),
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(f.$3, size: 11, color: sel ? f.$4 : Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        f.$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? f.$4 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildList(List<RendezVousModel> items) {
    final Map<String, List<RendezVousModel>> grouped = {};
    for (final r in items) {
      grouped.putIfAbsent(r.date, () => []).add(r);
    }
    final sortedDates = grouped.keys.toList()..sort();

    return RefreshIndicator(
      color: _kRed,
      onRefresh: context.read<RendezVousProvider>().loadRendezVous,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        itemCount: sortedDates.length,
        itemBuilder: (_, i) {
          final date = sortedDates[i];
          final rdvs = grouped[date]!;
          final parsed = DateTime.tryParse(date);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateDivider(date: parsed, today: _today),
              ...rdvs.map((r) => _RdvCard(
                    rdv: r,
                    isPrestataire: _isPrestataire(r),
                    userRole: _userRole,
                  )),
              const SizedBox(height: 6),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMonthGrid(List<RendezVousModel> all) {
    final year = _anchor.year;
    final month = _anchor.month;
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    final startOffset = first.weekday - 1;
    final totalCells = startOffset + last.day;
    final rows = (totalCells / 7).ceil();

    final Map<int, int> countByDay = {};
    for (final r in all) {
      try {
        final d = DateTime.parse(r.date);
        if (d.year == year && d.month == month) {
          if (_statusFilter == 'all' || r.status == _statusFilter) {
            countByDay[d.day] = (countByDay[d.day] ?? 0) + 1;
          }
        }
      } catch (_) {}
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: ['L', 'M', 'M', 'J', 'V', 'S', 'D'].map((d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ),
                )).toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: rows * 7,
            itemBuilder: (_, idx) {
              final dayNum = idx - startOffset + 1;
              if (dayNum < 1 || dayNum > last.day) return const SizedBox.shrink();

              final isToday = year == _today.year && month == _today.month && dayNum == _today.day;
              final count = countByDay[dayNum] ?? 0;
              final isAnchor = year == _anchor.year && month == _anchor.month && dayNum == _anchor.day;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _anchor = DateTime(year, month, dayNum);
                    _view = _CalView.day;
                    _tabCtrl.animateTo(0);
                  });
                  _fadeCtrl.forward(from: 0);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isToday ? _kRed : (isAnchor ? _kRed.withOpacity(0.1) : null),
                    borderRadius: BorderRadius.circular(8),
                    border: isAnchor && !isToday
                        ? Border.all(color: _kRed.withOpacity(0.4))
                        : null,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isToday ? Colors.white : null,
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isToday ? Colors.white.withOpacity(0.9) : _kRed,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w800,
                                  color: isToday ? _kRed : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          if (countByDay.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _kRed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Tous les rendez-vous du mois',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._filterByPeriod(all).map((r) => _RdvCard(
                  rdv: r,
                  isPrestataire: _isPrestataire(r),
                  userRole: _userRole,
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_note_outlined,
                size: 36,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _statusFilter == 'all'
                  ? 'Aucun rendez-vous sur cette période'
                  : 'Aucun rendez-vous "${_statusFilter}"',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Changez la période ou les filtres',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _statusFilter = 'all';
                _view = _CalView.week;
                _anchor = _today;
                _tabCtrl.animateTo(1);
                _fadeCtrl.forward(from: 0);
              }),
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Réinitialiser', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kRed,
                side: const BorderSide(color: _kRed),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 3,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 100,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String msg) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.red, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Séparateur de date style Google Calendar
// ═════════════════════════════════════════════════════════════════════════════
class _DateDivider extends StatelessWidget {
  final DateTime? date;
  final DateTime today;
  const _DateDivider({required this.date, required this.today});

  @override
  Widget build(BuildContext context) {
    if (date == null) return const SizedBox.shrink();
    const weekDays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun', 'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    final isToday = date!.year == today.year && date!.month == today.month && date!.day == today.day;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isToday ? _kRed : Colors.transparent,
              shape: BoxShape.circle,
              border: isToday
                  ? null
                  : Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white24
                          : Colors.grey.shade300,
                      width: 1,
                    ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  weekDays[date!.weekday - 1],
                  style: TextStyle(
                    fontSize: 8,
                    color: isToday ? Colors.white70 : Theme.of(context).textTheme.bodySmall?.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${date!.day}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isToday ? Colors.white : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${months[date!.month - 1]} ${date!.year}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: Theme.of(context).dividerColor,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Carte RDV
// ═════════════════════════════════════════════════════════════════════════════
class _RdvCard extends StatelessWidget {
  final RendezVousModel rdv;
  final bool isPrestataire;
  final String? userRole;
  const _RdvCard({required this.rdv, required this.isPrestataire, this.userRole});

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusBg, statusLabel) = _statusStyle(rdv.status, context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: statusColor, width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RendezVousDetailScreen(rdvId: rdv.id)),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rdv.serviceName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: statusColor.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                rdv.entrepriseName,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time_rounded, size: 11, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          rdv.timeRange,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPrestataire ? _kPurple.withOpacity(0.08) : _kBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPrestataire ? Icons.business_center_outlined : Icons.person_outline,
                          size: 11,
                          color: isPrestataire ? _kPurple : _kBlue,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isPrestataire ? 'Prestataire' : 'Client',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isPrestataire ? _kPurple : _kBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isPrestataire && rdv.isPending) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kAmber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kAmber.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app_rounded, size: 12, color: _kAmber),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Action requise',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFD97706),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (rdv.clientNotes != null && rdv.clientNotes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.notes_rounded,
                      size: 11,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        rdv.clientNotes!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (Color, Color, String) _statusStyle(String status, BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case 'pending':
        return (_kAmber, dark ? _kAmber.withOpacity(0.18) : const Color(0xFFFEF9C3), 'Attente');
      case 'confirmed':
        return (_kGreen, dark ? _kGreen.withOpacity(0.18) : const Color(0xFFDCFCE7), 'Confirmé');
      case 'cancelled':
        return (Colors.red, dark ? Colors.red.withOpacity(0.18) : const Color(0xFFFEE2E2), 'Annulé');
      case 'completed':
        return (Colors.blueGrey, dark ? Colors.blueGrey.withOpacity(0.18) : const Color(0xFFECEFF1), 'Terminé');
      default:
        return (Colors.grey, dark ? Colors.grey.withOpacity(0.18) : const Color(0xFFF5F5F5), status);
    }
  }
}

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    String label;
    Color bg;
    Color fg;
    switch (status) {
      case 'pending':
        label = 'En attente';
        bg = dark ? _kAmber.withOpacity(0.18) : const Color(0xFFFEF9C3);
        fg = _kAmber;
        break;
      case 'confirmed':
        label = 'Confirmé';
        bg = dark ? _kGreen.withOpacity(0.18) : const Color(0xFFDCFCE7);
        fg = _kGreen;
        break;
      case 'cancelled':
        label = 'Annulé';
        bg = dark ? Colors.red.withOpacity(0.18) : const Color(0xFFFEE2E2);
        fg = Colors.red;
        break;
      case 'completed':
        label = 'Terminé';
        bg = dark ? Colors.blueGrey.withOpacity(0.18) : const Color(0xFFECEFF1);
        fg = Colors.blueGrey;
        break;
      default:
        label = status;
        bg = dark ? Colors.grey.withOpacity(0.18) : const Color(0xFFF5F5F5);
        fg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}