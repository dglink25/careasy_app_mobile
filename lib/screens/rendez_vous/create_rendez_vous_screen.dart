// lib/screens/rendez_vous/create_rendez_vous_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../../models/rendez_vous_model.dart';
import '../../providers/rendez_vous_provider.dart';
import '../../services/rendez_vous_service.dart';
import '../../utils/constants.dart';

class CreateRendezVousScreen extends StatefulWidget {
  final Map<String, dynamic> service;

  const CreateRendezVousScreen({super.key, required this.service});

  @override
  State<CreateRendezVousScreen> createState() =>
      _CreateRendezVousScreenState();
}

class _CreateRendezVousScreenState extends State<CreateRendezVousScreen>
    with TickerProviderStateMixin {
  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  final _notesCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();           // ← AJOUT : champ phone
  final _rdvService = RendezVousService();

  int _step = 0; // 0=date, 1=créneau, 2=confirmation

  DateTime? _selectedDate;
  TimeSlot? _selectedSlot;

  bool _loadingSlots = false;
  List<TimeSlot> _slots = [];
  String? _slotsError;

  bool _submitting = false;

  // Phone de l'utilisateur connecté (null = pas encore de numéro)
  String? _userPhone;
  bool _phoneRequired = false;      // true si le backend a besoin du phone

  @override
  void initState() {
    super.initState();
    _loadUserPhone();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Chargement du phone depuis le storage ─────────────────────────────────
  Future<void> _loadUserPhone() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final phone = map['phone']?.toString();
        if (mounted) {
          setState(() {
            _userPhone = (phone != null && phone.isNotEmpty) ? phone : null;
            // Si pas de phone : on affiche le champ dès l'étape 2 (confirmation)
            _phoneRequired = _userPhone == null;
          });
        }
      }
    } catch (_) {}
  }

  // ── Chargement des créneaux ───────────────────────────────────────────────
  Future<void> _loadSlots(DateTime date) async {
    setState(() {
      _loadingSlots = true;
      _slotsError = null;
      _slots = [];
      _selectedSlot = null;
    });
    try {
      final dateStr = _formatDate(date);
      final slots = await _rdvService.fetchAvailableSlots(
          widget.service['id'].toString(), dateStr);
      setState(() {
        _slots = slots;
        _loadingSlots = false;
      });
    } catch (e) {
      setState(() {
        _slotsError = e.toString().replaceFirst('Exception: ', '');
        _loadingSlots = false;
      });
    }
  }

  // ── Soumission ────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_selectedDate == null || _selectedSlot == null) return;

    // Vérifier que le phone est renseigné si requis
    if (_phoneRequired && _phoneCtrl.text.trim().isEmpty) {
      _showError('Veuillez entrer votre numéro de téléphone');
      return;
    }

    setState(() => _submitting = true);

    final ok = await context.read<RendezVousProvider>().createRendezVous(
      serviceId  : widget.service['id'].toString(),
      date       : _formatDate(_selectedDate!),
      startTime  : _selectedSlot!.start,
      endTime    : _selectedSlot!.end,
      clientNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      // Passer le phone : celui saisi dans le champ, ou celui du compte
      phone      : _phoneRequired
          ? _phoneCtrl.text.trim()
          : _userPhone,
    );

    setState(() => _submitting = false);

    if (!mounted) return;

    if (ok) {
      // Sauvegarder le phone localement si l'user vient de le saisir
      if (_phoneRequired && _phoneCtrl.text.trim().isNotEmpty) {
        await _savePhoneLocally(_phoneCtrl.text.trim());
      }
      _showSuccessDialog();
    } else {
      final err = context.read<RendezVousProvider>().error ?? 'Erreur';
      _showError(err);
    }
  }

  /// Sauvegarde le phone dans le storage local (user_data) pour éviter
  /// de le redemander à chaque RDV.
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

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle),
              child: const Icon(Icons.check_circle,
                  color: Colors.green, size: 44),
            ),
            const SizedBox(height: 18),
            const Text('Demande envoyée !',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Votre demande de rendez-vous a été transmise. '
              'Vous serez notifié dès sa confirmation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // fermer dialog
                  Navigator.pop(context); // quitter l'écran
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('OK'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildServiceInfo(),
                const SizedBox(height: 20),
                _buildStepIndicator(),
                const SizedBox(height: 20),
                if (_step == 0) _buildDatePicker(),
                if (_step == 1) _buildSlotPicker(),
                if (_step == 2) _buildConfirmation(),
              ],
            ),
          ),
        ),
        _buildNavButtons(),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() => Container(
    decoration: const BoxDecoration(
      color: AppConstants.primaryRed,
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_back,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Prendre rendez-vous',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20)),
            child: Text('${_step + 1}/3',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    ),
  );

  // ── Info service ──────────────────────────────────────────────────────────
  Widget _buildServiceInfo() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey[200]!),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppConstants.primaryRed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.build_circle_outlined,
            color: AppConstants.primaryRed, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(widget.service['name']?.toString() ?? '—',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            (widget.service['entreprise'] as Map?)?['name']
                    ?.toString() ??
                '—',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ]),
      ),
    ]),
  );

  // ── Indicateur d'étapes ───────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    const steps = ['Date', 'Créneau', 'Confirmation'];
    const icons = [
      Icons.calendar_today_outlined,
      Icons.schedule,
      Icons.check_circle_outline,
    ];
    return Row(
      children: List.generate(3, (i) {
        final isDone = i < _step;
        final isCurrent = i == _step;
        return Expanded(
          child: Column(children: [
            Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isCurrent ? 32 : 24,
                height: isCurrent ? 32 : 24,
                decoration: BoxDecoration(
                  color: isDone || isCurrent
                      ? AppConstants.primaryRed
                      : Colors.grey[200],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDone ? Icons.check : icons[i],
                  size: isCurrent ? 15 : 12,
                  color: isDone || isCurrent
                      ? Colors.white
                      : Colors.grey[500],
                ),
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i < _step
                        ? AppConstants.primaryRed
                        : Colors.grey[200],
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(steps[i],
                style: TextStyle(
                    fontSize: 10,
                    color: isCurrent
                        ? AppConstants.primaryRed
                        : Colors.grey[500],
                    fontWeight: isCurrent
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ]),
        );
      }),
    );
  }

  // ── Étape 1 : Date ────────────────────────────────────────────────────────
  Widget _buildDatePicker() {
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(Icons.calendar_today_outlined, 'Choisissez une date',
          'Sélectionnez le jour de votre rendez-vous'),
      const SizedBox(height: 16),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.8,
        ),
        itemCount: 14,
        itemBuilder: (_, i) {
          final day = now.add(Duration(days: i + 1));
          final isSelected = _selectedDate != null &&
              _selectedDate!.day == day.day &&
              _selectedDate!.month == day.month &&
              _selectedDate!.year == day.year;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = day;
                _slots = [];
                _selectedSlot = null;
              });
              _loadSlots(day);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppConstants.primaryRed
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppConstants.primaryRed
                      : Colors.grey[200]!,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: AppConstants.primaryRed.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_dayName(day.weekday),
                      style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? Colors.white70
                              : Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text('${day.day}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : Colors.black87)),
                  Text(_monthShort(day.month),
                      style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? Colors.white70
                              : Colors.grey[500])),
                ],
              ),
            ),
          );
        },
      ),
    ]);
  }

  // ── Étape 2 : Créneaux ────────────────────────────────────────────────────
  Widget _buildSlotPicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(Icons.schedule, 'Choisissez un créneau',
          _selectedDate != null ? _formattedDate(_selectedDate!) : ''),
      const SizedBox(height: 16),
      if (_loadingSlots)
        const Center(
            child: CircularProgressIndicator(
                color: AppConstants.primaryRed)),
      if (_slotsError != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red[200]!),
          ),
          child: Text(_slotsError!,
              style: const TextStyle(color: Colors.red)),
        ),
      if (!_loadingSlots && _slotsError == null && _slots.isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              const Icon(Icons.event_busy, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Text('Aucun créneau disponible ce jour',
                  style:
                      TextStyle(fontSize: 14, color: Colors.grey[600])),
            ]),
          ),
        ),
      if (_slots.isNotEmpty)
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _slots.map((slot) {
            final isSelected = _selectedSlot?.start == slot.start;
            return GestureDetector(
              onTap: () => setState(() => _selectedSlot = slot),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppConstants.primaryRed
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppConstants.primaryRed
                        : Colors.grey[200]!,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: AppConstants.primaryRed
                                  .withOpacity(0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Text(slot.display,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : Colors.black87)),
              ),
            );
          }).toList(),
        ),
    ]);
  }

  // ── Étape 3 : Confirmation ────────────────────────────────────────────────
  Widget _buildConfirmation() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(Icons.check_circle_outline, 'Récapitulatif',
          'Vérifiez votre demande avant envoi'),
      const SizedBox(height: 16),

      // Recap
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(children: [
          _recapRow('Service',
              widget.service['name']?.toString() ?? '—'),
          _dividerThin(),
          _recapRow(
              'Entreprise',
              (widget.service['entreprise'] as Map?)?['name']
                      ?.toString() ??
                  '—'),
          _dividerThin(),
          _recapRow('Date',
              _selectedDate != null
                  ? _formattedDate(_selectedDate!)
                  : '—'),
          _dividerThin(),
          _recapRow('Horaire', _selectedSlot?.display ?? '—'),
        ]),
      ),

      const SizedBox(height: 16),

      // ── Champ téléphone si manquant ──────────────────────────────
      if (_phoneRequired) ...[
        _sectionTitle(Icons.phone_outlined, 'Votre numéro de téléphone',
            'Requis pour la confirmation du RDV'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: Row(children: [
            Icon(Icons.info_outline,
                color: Colors.orange[700], size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Le prestataire vous contactera à ce numéro pour confirmer.',
                style: TextStyle(
                    fontSize: 12, color: Colors.orange[800]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Ex: +229 97 00 00 00',
            hintStyle:
                TextStyle(color: Colors.grey[400], fontSize: 13),
            prefixIcon: Icon(Icons.phone_outlined,
                color: Colors.grey[500], size: 18),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppConstants.primaryRed, width: 1.5)),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 16),
      ] else ...[
        // Afficher le phone existant en lecture seule
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(children: [
            Icon(Icons.check_circle_outline,
                color: Colors.green[700], size: 16),
            const SizedBox(width: 8),
            Text('Contact : $_userPhone',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.green[800],
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 16),
      ],

      // Notes
      _sectionTitle(
          Icons.notes, 'Notes pour le prestataire', 'Optionnel'),
      const SizedBox(height: 10),
      TextFormField(
        controller: _notesCtrl,
        maxLines: 4,
        maxLength: 500,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Précisez les détails de votre demande...',
          hintStyle:
              TextStyle(color: Colors.grey[400], fontSize: 13),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: AppConstants.primaryRed, width: 1.5)),
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    ]);
  }

  // ── Boutons navigation ────────────────────────────────────────────────────
  Widget _buildNavButtons() {
    final isLast = _step == 2;

    bool canNext() {
      if (_step == 0) return _selectedDate != null;
      if (_step == 1) return _selectedSlot != null;
      return true;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, -3))
        ],
      ),
      child: Row(children: [
        if (_step > 0) ...[
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _step--),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Précédent'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[700],
                side: BorderSide(color: Colors.grey[300]!),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 3,
          child: ElevatedButton(
            onPressed: canNext()
                ? (_submitting
                    ? null
                    : isLast
                        ? _submit
                        : () => setState(() => _step++))
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isLast
                  ? Colors.green[600]
                  : AppConstants.primaryRed,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(isLast ? Icons.send : Icons.arrow_forward,
                        size: 18),
                    const SizedBox(width: 8),
                    Text(
                      isLast ? 'Envoyer la demande' : 'Suivant',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ]),
          ),
        ),
      ]),
    );
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────
  Widget _sectionTitle(IconData icon, String title, String sub) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03), blurRadius: 8)
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppConstants.primaryRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon,
                color: AppConstants.primaryRed, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              if (sub.isNotEmpty)
                Text(sub,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500])),
            ]),
          ),
        ]),
      );

  Widget _recapRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      SizedBox(
        width: 90,
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ]),
  );

  Widget _dividerThin() => Divider(height: 1, color: Colors.grey[100]);

  // ── Helpers format ────────────────────────────────────────────────────────
  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dayName(int wd) {
    const n = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return n[wd - 1];
  }

  String _monthShort(int m) {
    const mn = [
      'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
      'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'
    ];
    return mn[m - 1];
  }

  String _formattedDate(DateTime d) {
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];
    const days = [
      'lundi', 'mardi', 'mercredi', 'jeudi',
      'vendredi', 'samedi', 'dimanche'
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }
}