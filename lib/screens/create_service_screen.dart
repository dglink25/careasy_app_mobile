import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:careasy_app_mobile/screens/plans_abonnement_screen.dart';


class CreateServiceScreen extends StatefulWidget {
  final Map<String, dynamic> entreprise;
  const CreateServiceScreen({super.key, required this.entreprise});

  @override
  State<CreateServiceScreen> createState() => _CreateServiceScreenState();
}

class _CreateServiceScreenState extends State<CreateServiceScreen>
    with TickerProviderStateMixin {
  // APRÈS
final _storage = const FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSubmitting = false;

  // ── Step 1 : Infos de base ───────────────────
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  bool _isPriceOnRequest = false;
  bool _hasPromo = false;
  String? _selectedDomaineId;
  List<dynamic> _domaines = [];

  // ── Step 2 : Horaires ────────────────────────
  bool _isAlwaysOpen = false;
  final Map<String, bool> _dayOpen = {
    'monday': false, 'tuesday': false, 'wednesday': false,
    'thursday': false, 'friday': false, 'saturday': false, 'sunday': false,
  };
  final Map<String, TextEditingController> _dayStart = {};
  final Map<String, TextEditingController> _dayEnd = {};
  final Map<String, String> _dayNames = {
    'monday': 'Lundi', 'tuesday': 'Mardi', 'wednesday': 'Mercredi',
    'thursday': 'Jeudi', 'friday': 'Vendredi', 'saturday': 'Samedi',
    'sunday': 'Dimanche',
  };

  final List<File> _mediaFiles = [];
  final List<String> _mediaPreviews = [];

  @override
  void initState() {
    super.initState();
    for (final day in _dayNames.keys) {
      _dayStart[day] = TextEditingController(text: '08:00');
      _dayEnd[day] = TextEditingController(text: '18:00');
    }
    _fetchDomaines();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTrialLimitsOnOpen();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _descCtrl.dispose();
    _priceCtrl.dispose(); _promoCtrl.dispose();
    for (final c in _dayStart.values) c.dispose();
    for (final c in _dayEnd.values) c.dispose();
    _pageController.dispose();
    super.dispose();
  }

    void _checkTrialLimitsOnOpen() {
    final entreprise = widget.entreprise;

    // Récupérer les infos de l'entreprise passées en paramètre
    final bool isInTrial = entreprise['is_in_trial_period'] == true ||
        entreprise['trial_status'] == 'in_trial';

    final int currentServices = (entreprise['services'] as List?)?.length ??
        entreprise['services_count'] ?? 0;

    final int? maxServices = entreprise['max_services_allowed'] != null
        ? int.tryParse(entreprise['max_services_allowed'].toString())
        : null;

    // Si en essai ET limite atteinte → bloquer immédiatement
    if (isInTrial && maxServices != null && currentServices >= maxServices) {
      _showTrialLimitBlockingDialog(
        maxServices: maxServices,
        currentServices: currentServices,
        isTrialExpired: false,
      );
    }
  }

  Future<void> _fetchDomaines() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/domaines'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final List raw = jsonDecode(res.body);
        // Filtrer par domaines de l'entreprise
        final entrepriseDomaines =
            (widget.entreprise['domaines'] as List? ?? [])
                .map((d) => d['id'].toString())
                .toSet();
        setState(() {
          _domaines = raw
              .where((d) => entrepriseDomaines.contains(d['id'].toString()))
              .toList();
          if (_domaines.isNotEmpty) {
            _selectedDomaineId = _domaines.first['id'].toString();
          }
        });
      }
    } catch (_) {}
  }

  // ── Navigation ───────────────────────────────
  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  bool _validateStep() {
    switch (_currentStep) {
      case 0:
        if (_nameCtrl.text.trim().isEmpty) {
          _showError('Le nom du service est requis'); return false;
        }
        if (_selectedDomaineId == null) {
          _showError('Sélectionnez un domaine'); return false;
        }
        if (!_isPriceOnRequest && _priceCtrl.text.trim().isEmpty) {
          _showError('Entrez un prix ou cochez "Sur devis"'); return false;
        }
        if (_hasPromo && _promoCtrl.text.trim().isEmpty) {
          _showError('Entrez un prix promotionnel'); return false;
        }
        return true;
      case 1:
        if (!_isAlwaysOpen) {
          final anyOpen = _dayOpen.values.any((v) => v);
          if (!anyOpen) {
            _showError('Sélectionnez au moins un jour ouvert'); return false;
          }
        }
        return true;
      default: return true;
    }
  }

  void _next() {
    if (!_validateStep()) return;
    if (_currentStep < 2) _goToStep(_currentStep + 1);
  }

  // ── Photos ───────────────────────────────────
  Future<void> _pickMedia() async {
    if (_mediaFiles.length >= 5) {
      _showError('Maximum 5 photos'); return;
    }
    final source = await _showSourceDialog();
    if (source == null) return;
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, imageQuality: 70, maxWidth: 1200);
      if (picked != null) {
        setState(() {
          _mediaFiles.add(File(picked.path));
          _mediaPreviews.add(picked.path);
        });
      }
    } catch (_) {}
  }

  Future<ImageSource?> _showSourceDialog() =>
      showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppConstants.primaryRed),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Choisir depuis la galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );

  // ── Soumission ───────────────────────────────
  Future<void> _submit() async {
    if (!_validateStep()) return;
    setState(() => _isSubmitting = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.apiBaseUrl}/services'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      // Champs de base
      request.fields['name'] = _nameCtrl.text.trim();
      request.fields['descriptions'] = _descCtrl.text.trim();
      request.fields['entreprise_id'] = widget.entreprise['id'].toString();
      request.fields['domaine_id'] = _selectedDomaineId!;
      request.fields['is_price_on_request'] = _isPriceOnRequest ? '1' : '0';

      if (!_isPriceOnRequest && _priceCtrl.text.isNotEmpty) {
        request.fields['price'] = _priceCtrl.text.trim();
      }
      request.fields['has_promo'] = _hasPromo ? '1' : '0';
      if (_hasPromo && _promoCtrl.text.isNotEmpty) {
        request.fields['price_promo'] = _promoCtrl.text.trim();
      }

      // Horaires
      request.fields['is_always_open'] = _isAlwaysOpen ? '1' : '0';
      if (!_isAlwaysOpen) {
        for (final day in _dayNames.keys) {
          request.fields['schedule[$day][is_open]'] =
              _dayOpen[day]! ? '1' : '0';
          if (_dayOpen[day]!) {
            request.fields['schedule[$day][start]'] = _dayStart[day]!.text;
            request.fields['schedule[$day][end]'] = _dayEnd[day]!.text;
          }
        }
      }

      // Photos
      for (int i = 0; i < _mediaFiles.length; i++) {
        final f = _mediaFiles[i];
        final ext = f.path.split('.').last.toLowerCase();
        request.files.add(await http.MultipartFile.fromPath(
          'medias[]', f.path,
          contentType: MediaType('image', ext == 'jpg' ? 'jpeg' : ext),
        ));
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSuccessDialog();
      } else {
        // ✅ Gestion spéciale des erreurs 403 liées aux limites de l'essai
        if (response.statusCode == 403) {
          final data = jsonDecode(body);
          final message = data['message'] ?? '';

          // Vérifier si c'est une erreur de limite de services (essai gratuit)
          if (message.contains('limite de services') ||
              message.contains('période d\'essai')) {
            final int maxServices = data['max_services'] ?? 3;
            final int currentServices = data['current_services'] ?? 0;
            _showTrialLimitBlockingDialog(
              maxServices: maxServices,
              currentServices: currentServices,
              isTrialExpired: false,
            );
            return;
          }
        }

        final data = jsonDecode(body);
        String msg = data['message'] ?? 'Erreur';
        if (data['errors'] != null) {
          msg += '\n' +
              (data['errors'] as Map)
                  .entries
                  .map((e) => '• ${(e.value as List).first}')
                  .join('\n');
        }
        _showError(msg);
      }
    } catch (_) {
      _showError('Erreur de connexion. Vérifiez votre réseau.');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

    void _showTrialLimitBlockingDialog({
    required int maxServices,
    required int currentServices,
    required bool isTrialExpired,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false, // Ne peut pas fermer sans action
      builder: (_) => WillPopScope(
        onWillPop: () async => false, // Bloquer le bouton retour Android
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Icône ──
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.orange,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Titre ──
                const Text(
                  'Limite de services atteinte',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Badge compteur ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_repair_service_outlined,
                          color: Colors.orange[700], size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '$currentServices / $maxServices services utilisés',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Message ──
                Text(
                  'Votre période d\'essai gratuite vous permet de créer jusqu\'à '
                  '$maxServices service${maxServices > 1 ? 's' : ''}. '
                  'Pour en ajouter davantage, souscrivez à un plan payant.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),

                // ── Avantages d'un plan payant ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      _benefitRow(Icons.all_inclusive, 'Services illimités'),
                      const SizedBox(height: 6),
                      _benefitRow(Icons.people_outline, 'Gestion des employés'),
                      const SizedBox(height: 6),
                      _benefitRow(Icons.analytics_outlined, 'Statistiques avancées'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                    SizedBox(
  width: double.infinity,
  child: ElevatedButton.icon(
    onPressed: () {
      Navigator.pop(context);
      Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PlansAbonnementScreen()));
    },
    icon: const Icon(Icons.subscriptions_outlined, size: 16),
    label: const Text('Plans & Abonnements'),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.grey[100],
      foregroundColor: Colors.black87,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
),

                const SizedBox(height: 10),

                // ── Bouton secondaire → Retour ──
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Fermer le dialog
                      Navigator.pop(context); // Quitter CreateServiceScreen
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: const Text(
                      'Retour',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ligne d'avantage dans le dialog
  Widget _benefitRow(IconData icon, String label) => Row(
    children: [
      Icon(icon, size: 15, color: Colors.green[600]),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(
              fontSize: 12,
              color: Colors.green[700],
              fontWeight: FontWeight.w500)),
    ],
  );
  
 void _navigateToAbonnements() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/profile/abonnements',
      (route) => route.isFirst,
    );
  }

  void _showSuccessDialog() => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72,
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 44)),
          const SizedBox(height: 18),
          const Text('Service créé !',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Votre service a été ajouté avec succès.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('OK'),
            )),
        ]),
      ),
    ),
  );

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
  );

  // ── BUILD ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final steps = ['Infos', 'Horaires', 'Photos'];
    final icons = [Icons.info_outline, Icons.schedule, Icons.photo_library];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(children: [
        _buildHeader(steps, icons),
        Expanded(child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildStep1(), _buildStep2(), _buildStep3()],
        )),
        _buildNavButtons(),
      ]),
    );
  }

  Widget _buildHeader(List<String> steps, List<IconData> icons) {
    return Container(
      decoration: const BoxDecoration(
        color: AppConstants.primaryRed,
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24)),
      ),
      child: SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(children: [
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Créer un service',
                style: TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${_currentStep + 1}/3',
                  style: const TextStyle(color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: List.generate(3, (i) {
            final isDone = i < _currentStep, isCurrent = i == _currentStep;
            return Expanded(child: Padding(
              padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
              child: Column(children: [
                Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isCurrent ? 34 : 26, height: isCurrent ? 34 : 26,
                    decoration: BoxDecoration(
                      color: isDone || isCurrent ? Colors.white : Colors.white.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(isDone ? Icons.check : icons[i],
                        size: isCurrent ? 16 : 13,
                        color: isDone || isCurrent ? AppConstants.primaryRed : Colors.white),
                  ),
                  if (i < 2) Expanded(child: Container(height: 2,
                      color: i < _currentStep ? Colors.white : Colors.white.withOpacity(0.3))),
                ]),
                const SizedBox(height: 4),
                Text(steps[i], style: TextStyle(
                    color: isCurrent ? Colors.white : Colors.white.withOpacity(0.7),
                    fontSize: 10,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal),
                  textAlign: TextAlign.center),
              ]),
            ));
          })),
        ]),
      )),
    );
  }

  // ── STEP 1 : Infos de base ────────────────────
  Widget _buildStep1() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(Icons.info_outline, 'Informations de base',
          'Nom, domaine et tarification du service'),
      const SizedBox(height: 20),

      // Nom
      _label('Nom du service', required: true),
      _field(_nameCtrl, 'Ex: Vidange moteur', Icons.build_circle_outlined),
      const SizedBox(height: 16),

      // Description
      _label('Description'),
      TextFormField(
        controller: _descCtrl,
        maxLines: 3,
        style: const TextStyle(fontSize: 14),
        decoration: _inputDeco('Décrivez votre service...', Icons.description_outlined),
      ),
      const SizedBox(height: 16),

      // Domaine
      _label('Domaine d\'activité', required: true),
      Container(
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedDomaineId,
            isExpanded: true,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            borderRadius: BorderRadius.circular(12),
            items: _domaines.map((d) => DropdownMenuItem(
              value: d['id'].toString(),
              child: Text(d['name'] ?? ''),
            )).toList(),
            onChanged: (v) => setState(() => _selectedDomaineId = v),
          ),
        ),
      ),
      const SizedBox(height: 20),

      // Prix
      _sectionTitle(Icons.payments_outlined, 'Tarification', 'Définissez le prix de votre service'),
      const SizedBox(height: 14),

      // Sur devis toggle
      _toggleCard(
        icon: Icons.request_quote_outlined,
        title: 'Prix sur devis',
        subtitle: 'Le client vous contacte pour connaître le prix',
        value: _isPriceOnRequest,
        onChanged: (v) => setState(() {
          _isPriceOnRequest = v;
          if (v) _hasPromo = false;
        }),
      ),
      const SizedBox(height: 12),

      if (!_isPriceOnRequest) ...[
        _label('Prix (FCFA)', required: true),
        _field(_priceCtrl, 'Ex: 15000', Icons.attach_money,
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),

        // Promo toggle
        _toggleCard(
          icon: Icons.local_offer_outlined,
          title: 'Activer une promotion',
          subtitle: 'Afficher un prix réduit avec le prix barré',
          value: _hasPromo,
          onChanged: (v) => setState(() => _hasPromo = v),
        ),
        if (_hasPromo) ...[
          const SizedBox(height: 12),
          _label('Prix promotionnel (FCFA)', required: true),
          _field(_promoCtrl, 'Ex: 12000', Icons.sell_outlined,
              keyboardType: TextInputType.number),
        ],
      ],
      const SizedBox(height: 20),
    ]),
  );

  // ── STEP 2 : Horaires ──────────────────────────
  Widget _buildStep2() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(Icons.schedule, 'Horaires d\'ouverture',
          'Définissez quand votre service est disponible'),
      const SizedBox(height: 20),

      // 24h/24 toggle
      _toggleCard(
        icon: Icons.all_inclusive,
        title: 'Disponible 24h/24',
        subtitle: 'Votre service est accessible à toute heure',
        value: _isAlwaysOpen,
        onChanged: (v) => setState(() => _isAlwaysOpen = v),
        color: Colors.green,
      ),

      if (!_isAlwaysOpen) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.blue[50], borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!)),
          child: Row(children: [
            Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('Activez les jours où vous êtes disponible',
                style: TextStyle(fontSize: 12, color: Colors.blue[700]))),
          ]),
        ),
        const SizedBox(height: 14),
        ..._dayNames.entries.map((entry) {
          final day = entry.key;
          final name = entry.value;
          final isOpen = _dayOpen[day]!;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isOpen ? AppConstants.primaryRed.withOpacity(0.3) : Colors.grey[200]!),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
            ),
            child: Column(children: [
              // Ligne jour + toggle
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Text(name, style: TextStyle(fontSize: 14,
                      fontWeight: isOpen ? FontWeight.w700 : FontWeight.normal,
                      color: isOpen ? Colors.black87 : Colors.grey[500])),
                  const Spacer(),
                  Switch(
                    value: isOpen,
                    onChanged: (v) => setState(() => _dayOpen[day] = v),
                    activeColor: AppConstants.primaryRed,
                  ),
                ]),
              ),
              // Horaires si ouvert
              if (isOpen)
                Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Row(children: [
                    Expanded(child: _timeField(_dayStart[day]!, 'Ouverture')),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('—', style: TextStyle(color: Colors.grey))),
                    Expanded(child: _timeField(_dayEnd[day]!, 'Fermeture')),
                  ]),
                ),
            ]),
          );
        }).toList(),
      ],
      const SizedBox(height: 20),
    ]),
  );

  Widget _timeField(TextEditingController ctrl, String hint) => GestureDetector(
    onTap: () async {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: int.tryParse(ctrl.text.split(':')[0]) ?? 8,
          minute: int.tryParse(ctrl.text.split(':')[1]) ?? 0,
        ),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(primary: AppConstants.primaryRed)),
          child: child!,
        ),
      );
      if (t != null) {
        ctrl.text =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        setState(() {});
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.grey[50], borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[200]!)),
      child: Row(children: [
        Icon(Icons.access_time, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text(ctrl.text.isEmpty ? hint : ctrl.text,
            style: TextStyle(fontSize: 13,
                color: ctrl.text.isEmpty ? Colors.grey[400] : Colors.black87)),
      ]),
    ),
  );

  // ── STEP 3 : Médias + récap ───────────────────
  Widget _buildStep3() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(Icons.photo_library, 'Photos du service',
          'Ajoutez jusqu\'à 5 photos (optionnel)'),
      const SizedBox(height: 16),

      // Grid photos
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: [
          ..._mediaPreviews.asMap().entries.map((e) => Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10),
                child: Image.file(File(e.value), fit: BoxFit.cover,
                    width: double.infinity, height: double.infinity)),
            Positioned(top: 4, right: 4,
              child: GestureDetector(
                onTap: () => setState(() {
                  _mediaFiles.removeAt(e.key);
                  _mediaPreviews.removeAt(e.key);
                }),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
          ])),
          if (_mediaPreviews.length < 5)
            GestureDetector(
              onTap: _pickMedia,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppConstants.primaryRed.withOpacity(0.4), width: 1.5,
                      style: BorderStyle.solid),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      color: AppConstants.primaryRed, size: 28),
                  const SizedBox(height: 4),
                  Text('Ajouter', style: TextStyle(fontSize: 11,
                      color: AppConstants.primaryRed, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
        ],
      ),

      const SizedBox(height: 24),

      // Récapitulatif
      _sectionTitle(Icons.checklist, 'Récapitulatif', ''),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(children: [
          _recapRow('Service', _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '—'),
          _recapRow('Domaine', _domaines.firstWhere(
            (d) => d['id'].toString() == _selectedDomaineId,
            orElse: () => {'name': '—'})['name']),
          _recapRow('Prix', _isPriceOnRequest ? 'Sur devis' :
              _priceCtrl.text.isNotEmpty ? '${_priceCtrl.text} FCFA' : '—'),
          if (_hasPromo && _promoCtrl.text.isNotEmpty)
            _recapRow('Prix promo', '${_promoCtrl.text} FCFA'),
          _recapRow('Disponibilité', _isAlwaysOpen ? '24h/24'
              : '${_dayOpen.values.where((v) => v).length} jour(s)'),
          _recapRow('Photos', '${_mediaFiles.length} photo(s)'),
        ]),
      ),

      const SizedBox(height: 20),
    ]),
  );

  // ── Nav buttons ───────────────────────────────
  Widget _buildNavButtons() {
    final isLast = _currentStep == 2;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: Row(children: [
        if (_currentStep > 0) ...[
          Expanded(flex: 2, child: OutlinedButton.icon(
            onPressed: () => _goToStep(_currentStep - 1),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Précédent'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              side: BorderSide(color: Colors.grey[300]!),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          )),
          const SizedBox(width: 12),
        ],
        Expanded(flex: 3, child: ElevatedButton(
          onPressed: _isSubmitting ? null : (isLast ? _submit : _next),
          style: ElevatedButton.styleFrom(
            backgroundColor: isLast ? Colors.green[600] : AppConstants.primaryRed,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(isLast ? Icons.check : Icons.arrow_forward, size: 18),
                  const SizedBox(width: 8),
                  Text(isLast ? 'Créer le service' : 'Suivant',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
        )),
      ]),
    );
  }

  // ── Widgets helpers ───────────────────────────
  Widget _sectionTitle(IconData icon, String title, String sub) =>
      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppConstants.primaryRed, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ])),
        ]));

  Widget _label(String t, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      if (required) const Text(' *', style: TextStyle(color: Colors.red)),
    ]),
  );

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType? keyboardType}) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: _inputDeco(hint, icon),
      );

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
    prefixIcon: Icon(icon, color: Colors.grey[500], size: 18),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppConstants.primaryRed, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  Widget _toggleCard({required IconData icon, required String title,
      required String subtitle, required bool value,
      required ValueChanged<bool> onChanged, Color? color}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: value
                ? (color ?? AppConstants.primaryRed).withOpacity(0.3)
                : Colors.grey[200]!),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: (color ?? AppConstants.primaryRed).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color ?? AppConstants.primaryRed, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ])),
          Switch(value: value, onChanged: onChanged,
              activeColor: color ?? AppConstants.primaryRed),
        ]),
      );

  Widget _recapRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label,
          style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500))),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );
}