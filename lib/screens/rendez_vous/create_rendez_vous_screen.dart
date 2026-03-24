// lib/screens/rendez_vous/create_rendez_vous_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../../models/rendez_vous_model.dart';
import '../../providers/rendez_vous_provider.dart';
import '../../services/rendez_vous_service.dart';
import '../../utils/constants.dart';
import '../../services/notification_service.dart';  // ← AJOUT rappel RDV

const Color _kRed = AppConstants.primaryRed;
const Color _kGreen = Color(0xFF22C55E);

const List<String> _kDayKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
const List<String> _kDayFr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const List<String> _kDaysLong = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const List<String> _kMonthsLong = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];
const List<String> _kMonthsAbbr = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', 'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];

class CreateRendezVousScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  const CreateRendezVousScreen({super.key, required this.service});

  @override
  State<CreateRendezVousScreen> createState() => _CreateRendezVousScreenState();
}

class _CreateRendezVousScreenState extends State<CreateRendezVousScreen>
    with TickerProviderStateMixin {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final RendezVousService _rdvSvc = RendezVousService();

  int _step = 0;
  DateTime? _selectedDate;
  TimeSlot? _selectedSlot;

  bool _loadingSlots = false;
  List<TimeSlot> _slots = [];
  String? _slotsError;
  bool _submitting = false;

  String? _userPhone;
  bool _phoneRequired = false;

  bool _isAlwaysOpen = false;
  bool _is24h = false;
  Map<String, dynamic> _schedule = {};

  @override
  void initState() {
    super.initState();
    _parseService();
    _loadUserPhone();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _parseService() {
    final svc = widget.service;
    _isAlwaysOpen = svc['is_always_open'] == true;
    _is24h = svc['is_open_24h'] == true;
    
    // Gérer le schedule quel que soit son format
    final rawSched = svc['schedule'];
    if (rawSched != null) {
      if (rawSched is Map) {
        _schedule = Map<String, dynamic>.from(rawSched);
      } else if (rawSched is String && rawSched.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawSched);
          if (decoded is Map) {
            _schedule = Map<String, dynamic>.from(decoded);
          }
        } catch (e) {
          debugPrint('Erreur décodage schedule: $e');
        }
      }
    }
    
    debugPrint('Schedule parsé: $_schedule');
    debugPrint('isAlwaysOpen: $_isAlwaysOpen, is24h: $_is24h');
  }

  bool _isOpenOn(DateTime date) {
    if (_isAlwaysOpen || _is24h) return true;
    if (_schedule.isEmpty) {
      // Si pas de schedule et pas ouvert 24h, considérer comme fermé
      debugPrint('Schedule vide pour ${_kDayKeys[date.weekday - 1]}');
      return false;
    }
    
    final key = _kDayKeys[date.weekday - 1];
    final day = _schedule[key];
    
    if (day == null) {
      debugPrint('Jour $key non trouvé dans schedule');
      return false;
    }
    
    // Gérer le cas où is_open peut être booléen ou string
    final isOpen = day['is_open'] == true || day['is_open'] == '1' || day['is_open'] == 1;
    debugPrint('Jour $key: isOpen=$isOpen, data=$day');
    
    return isOpen;
  }

  (String, String)? _getDayRange(DateTime date) {
    if (_isAlwaysOpen || _is24h) return ('00:00', '23:59');
    if (_schedule.isEmpty) return null;
    
    final key = _kDayKeys[date.weekday - 1];
    final day = _schedule[key];
    
    if (day == null) return null;
    
    final isOpen = day['is_open'] == true || day['is_open'] == '1' || day['is_open'] == 1;
    if (!isOpen) return null;
    
    String start = '00:00';
    String end = '23:59';
    
    if (day['start'] != null) {
      start = day['start'].toString();
      if (start.length > 5) start = start.substring(0, 5);
    }
    
    if (day['end'] != null) {
      end = day['end'].toString();
      if (end.length > 5) end = end.substring(0, 5);
    }
    
    return (start, end);
  }

  String _getMonthAbbreviation(int month) => _kMonthsAbbr[month - 1];

  Future<void> _loadUserPhone() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final phone = map['phone']?.toString();
        if (mounted) {
          setState(() {
            _userPhone = (phone != null && phone.isNotEmpty) ? phone : null;
            _phoneRequired = _userPhone == null;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSlots(DateTime date) async {
    if (!_isOpenOn(date)) {
      setState(() {
        _slots = [];
        _slotsError = 'Ce service est fermé ce jour.';
        _loadingSlots = false;
      });
      return;
    }
    
    setState(() {
      _loadingSlots = true;
      _slotsError = null;
      _slots = [];
      _selectedSlot = null;
    });
    
    try {
      final dateStr = _formatDate(date);
      final serviceId = widget.service['id'].toString();
      final slots = await _rdvSvc.fetchAvailableSlots(serviceId, dateStr);
      
      setState(() {
        _slots = slots;
        _loadingSlots = false;
        if (slots.isEmpty) {
          _slotsError = 'Aucun créneau disponible pour cette journée.';
        }
      });
    } catch (e) {
      debugPrint('Erreur chargement créneaux: $e');
      setState(() {
        _slotsError = 'Erreur lors du chargement des créneaux';
        _loadingSlots = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedDate == null || _selectedSlot == null) return;
    if (_phoneRequired && _phoneCtrl.text.trim().isEmpty) {
      _showError('Veuillez entrer votre numéro de téléphone');
      return;
    }
    
    setState(() => _submitting = true);

    final ok = await context.read<RendezVousProvider>().createRendezVous(
      serviceId: widget.service['id'].toString(),
      date: _formatDate(_selectedDate!),
      startTime: _selectedSlot!.start,
      endTime: _selectedSlot!.end,
      clientNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      phone: _phoneRequired ? _phoneCtrl.text.trim() : _userPhone,
    );
    
    setState(() => _submitting = false);
    if (!mounted) return;

    if (ok) {
      if (_phoneRequired && _phoneCtrl.text.trim().isNotEmpty) {
        await _savePhoneLocally(_phoneCtrl.text.trim());
      }
      // ── AJOUT : rappel local planifié côté client ──────────────────
      // On utilise directement les valeurs du formulaire (déjà disponibles)
      // car le provider n'expose pas le RDV créé.
      if (_selectedDate != null && _selectedSlot != null) {
        try {
          await NotificationService().scheduleRdvReminder(
            rdvId        : 'rdv_${DateTime.now().millisecondsSinceEpoch}',
            rdvDate      : _formatDate(_selectedDate!),
            rdvTime      : _selectedSlot!.start,
            serviceName  : widget.service['name']?.toString() ?? 'le service',
            isPrestataire: false,
          );
        } catch (e) {
          debugPrint('[Notif] scheduleRdvReminder error: $e');
        }
      }
      _showSuccessDialog();
    } else {
      _showError(context.read<RendezVousProvider>().error ?? 'Erreur lors de la création');
    }
  }

  Future<void> _savePhoneLocally(String phone) async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map['phone'] = phone;
        await _storage.write(key: 'user_data', value: jsonEncode(map));
        setState(() {
          _userPhone = phone;
          _phoneRequired = false;
        });
      }
    } catch (_) {}
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: _kGreen, size: 48),
              ),
              const SizedBox(height: 18),
              const Text(
                'Demande envoyée !',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'Votre demande de rendez-vous a été transmise. '
                'Vous serez notifié dès sa confirmation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.5, fontSize: 13),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Parfait !', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildServiceBadge(),
                  const SizedBox(height: 16),
                  _buildStepper(),
                  const SizedBox(height: 20),
                  if (_step == 0) _buildDateStep(),
                  if (_step == 1) _buildSlotStep(),
                  if (_step == 2) _buildConfirmStep(),
                ],
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_kRed, Color(0xFFc1121f)]),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Prendre rendez-vous',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_step + 1} / 3',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceBadge() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kRed.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.build_circle_outlined, color: _kRed, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.service['name']?.toString() ?? '—',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  (widget.service['entreprise'] as Map?)?['name']?.toString() ?? '—',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                if (_isAlwaysOpen || _is24h) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.all_inclusive_rounded, size: 10, color: _kGreen),
                        SizedBox(width: 4),
                        Text(
                          '24h/24 • 7j/7',
                          style: TextStyle(fontSize: 9, color: _kGreen, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    const labels = ['Date', 'Créneau', 'Confirmation'];
    const icons = [Icons.calendar_today_outlined, Icons.schedule_rounded, Icons.check_circle_outline];
    
    return Row(
      children: List.generate(3, (i) {
        final done = i < _step;
        final current = i == _step;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: current ? 32 : 28,
                    height: current ? 32 : 28,
                    decoration: BoxDecoration(
                      color: done || current ? _kRed : Colors.grey.shade200,
                      shape: BoxShape.circle,
                      boxShadow: current
                          ? [BoxShadow(color: _kRed.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))]
                          : [],
                    ),
                    child: Icon(
                      done ? Icons.check_rounded : icons[i],
                      size: current ? 16 : 14,
                      color: done || current ? Colors.white : Colors.grey.shade400,
                    ),
                  ),
                  if (i < 2)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 2,
                        color: i < _step ? _kRed : Colors.grey.shade200,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: current ? FontWeight.w700 : FontWeight.normal,
                  color: current ? _kRed : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildDateStep() {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.calendar_today_outlined,
          'Choisissez une date',
          'Sélectionnez le jour de votre rendez-vous',
        ),
        const SizedBox(height: 12),
        
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth < 400 ? 4 : 5;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: 21,
              itemBuilder: (_, i) {
                final day = now.add(Duration(days: i + 1));
                final isOpen = _isOpenOn(day);
                final isSelected = _selectedDate != null &&
                    _selectedDate!.year == day.year &&
                    _selectedDate!.month == day.month &&
                    _selectedDate!.day == day.day;

                return GestureDetector(
                  onTap: isOpen
                      ? () {
                          setState(() {
                            _selectedDate = day;
                            _slots = [];
                            _selectedSlot = null;
                          });
                          _loadSlots(day);
                        }
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _kRed
                          : isOpen
                              ? Theme.of(context).cardColor
                              : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? _kRed : (isOpen ? Colors.grey.shade200 : Colors.grey.shade200),
                        width: isSelected ? 1.5 : 1,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: _kRed.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 1))]
                          : [],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _kDayFr[day.weekday - 1],
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? Colors.white70
                                : (isOpen ? Colors.grey.shade600 : Colors.grey.shade400),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.white : (isOpen ? null : Colors.grey.shade400),
                          ),
                        ),
                        Text(
                          _getMonthAbbreviation(day.month),
                          style: TextStyle(
                            fontSize: 9,
                            color: isSelected
                                ? Colors.white70
                                : (isOpen ? Colors.grey.shade500 : Colors.grey.shade400),
                          ),
                        ),
                        if (!isOpen)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Fermé',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        
        const SizedBox(height: 16),
        _buildScheduleLegend(),
      ],
    );
  }

  Widget _buildScheduleLegend() {
    if (_isAlwaysOpen || _is24h) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _kGreen.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kGreen.withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.all_inclusive_rounded, color: _kGreen, size: 14),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Service disponible 24h/24 et 7j/7',
                style: TextStyle(fontSize: 11, color: _kGreen, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    
    if (_schedule.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey, size: 14),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Horaires non définis',
                style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_outlined, size: 12, color: _kRed),
              const SizedBox(width: 6),
              const Text('Horaires', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(7, (i) {
              final key = _kDayKeys[i];
              final dayData = _schedule[key];
              final isOpen = dayData != null && 
                  (dayData['is_open'] == true || dayData['is_open'] == '1' || dayData['is_open'] == 1);
              
              String hours = 'Fermé';
              if (isOpen) {
                String start = dayData['start']?.toString() ?? '00:00';
                String end = dayData['end']?.toString() ?? '23:59';
                if (start.length > 5) start = start.substring(0, 5);
                if (end.length > 5) end = end.substring(0, 5);
                hours = '$start-$end';
              }
              
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isOpen ? _kRed.withOpacity(0.07) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isOpen ? _kRed.withOpacity(0.2) : Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Text(_kDayFr[i], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isOpen ? _kRed : Colors.grey.shade400)),
                    Text(hours, style: TextStyle(fontSize: 8, color: isOpen ? _kRed.withOpacity(0.7) : Colors.grey.shade400)),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotStep() {
    final range = _selectedDate != null ? _getDayRange(_selectedDate!) : null;
    final subLabel = _selectedDate != null
        ? '${_kDaysLong[_selectedDate!.weekday - 1]} ${_selectedDate!.day} ${_kMonthsLong[_selectedDate!.month - 1]}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.schedule_rounded, 'Choisissez un créneau', subLabel),
        const SizedBox(height: 12),

        if (range != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kRed.withOpacity(0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time_rounded, size: 12, color: _kRed),
                const SizedBox(width: 4),
                Text(
                  'Ouvert de ${range.$1} à ${range.$2}',
                  style: const TextStyle(fontSize: 11, color: _kRed, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (_selectedDate != null && !_isOpenOn(_selectedDate!))
          _buildInfoBox(
            Icons.event_busy_outlined,
            Colors.orange,
            'Ce service est fermé ce jour. Choisissez une autre date.',
          ),

        if (_loadingSlots)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: _kRed),
                  SizedBox(height: 12),
                  Text('Vérification des créneaux...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),

        if (_slotsError != null) _buildInfoBox(Icons.error_outline, Colors.red, _slotsError!),

        if (!_loadingSlots && _slotsError == null && _slots.isEmpty &&
            _selectedDate != null && _isOpenOn(_selectedDate!))
          _buildInfoBox(
            Icons.event_busy_outlined,
            Colors.orange,
            'Aucun créneau disponible ce jour. Tous les créneaux sont réservés.',
          ),

        if (_slots.isNotEmpty) ...[
          Text(
            '${_slots.length} créneau${_slots.length > 1 ? 'x' : ''} disponible${_slots.length > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _slots.map((slot) {
              final isSelected = _selectedSlot?.start == slot.start;
              return GestureDetector(
                onTap: () => setState(() => _selectedSlot = slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? _kRed : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? _kRed : Colors.grey.shade200,
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: _kRed.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 1))]
                        : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 2)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 12,
                        color: isSelected ? Colors.white70 : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        slot.display,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.check_circle_outline,
          'Récapitulatif',
          'Vérifiez votre demande avant envoi',
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
          ),
          child: Column(
            children: [
              _buildRecapRow(Icons.build_circle_outlined, 'Service', widget.service['name']?.toString() ?? '—', _kRed),
              const Divider(height: 1),
              _buildRecapRow(Icons.business_outlined, 'Entreprise', (widget.service['entreprise'] as Map?)?['name']?.toString() ?? '—', Colors.grey),
              const Divider(height: 1),
              _buildRecapRow(
                Icons.calendar_today_outlined,
                'Date',
                _selectedDate != null
                    ? '${_kDaysLong[_selectedDate!.weekday - 1]} ${_selectedDate!.day} ${_kMonthsLong[_selectedDate!.month - 1]} ${_selectedDate!.year}'
                    : '—',
                _kRed,
              ),
              const Divider(height: 1),
              _buildRecapRow(Icons.schedule_rounded, 'Horaire', _selectedSlot?.display ?? '—', _kRed),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (_phoneRequired) ...[
          _buildSectionHeader(Icons.phone_outlined, 'Votre numéro', 'Le prestataire vous contactera à ce numéro'),
          const SizedBox(height: 8),
          _buildInfoBox(Icons.info_outline, Colors.orange, 'Ce numéro sera partagé avec le prestataire.'),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'Ex: +229 97 00 00 00',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              prefixIcon: const Icon(Icons.phone_outlined, size: 16),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kRed, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kGreen.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kGreen.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: _kGreen, size: 14),
                const SizedBox(width: 8),
                Text('Contact : $_userPhone', style: const TextStyle(fontSize: 12, color: _kGreen, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        _buildSectionHeader(Icons.notes_rounded, 'Notes', 'Optionnel'),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: 'Précisez les détails de votre demande...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kRed, width: 1.5)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    bool canNext() {
      if (_step == 0) return _selectedDate != null && _isOpenOn(_selectedDate!);
      if (_step == 1) return _selectedSlot != null;
      return true;
    }
    
    final isLast = _step == 2;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          if (_step > 0) ...[
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: () => setState(() => _step--),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Précédent', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 3,
            child: ElevatedButton(
              onPressed: canNext()
                  ? (_submitting ? null : isLast ? _submit : () => setState(() => _step++))
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isLast ? _kGreen : _kRed,
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isLast ? Icons.send_rounded : Icons.arrow_forward_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(isLast ? 'Envoyer' : 'Suivant', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _kRed, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(IconData icon, Color color, String message) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(child: Text(message, style: TextStyle(fontSize: 11, color: color))),
        ],
      ),
    );
  }

  Widget _buildRecapRow(IconData icon, String label, String value, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 10),
          SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}