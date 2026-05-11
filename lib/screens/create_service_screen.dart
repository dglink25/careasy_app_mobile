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
  /// L'entreprise concernée (toujours fournie depuis MesServicesScreen).
  final Map<String, dynamic>? entreprise;

  /// Domaines déjà chargés par MesServicesScreen → aucun appel API.
  final List<Map<String, dynamic>> preloadedDomaines;

  const CreateServiceScreen({
    super.key,
    this.entreprise,
    this.preloadedDomaines = const [],
  });

  @override
  State<CreateServiceScreen> createState() => _CreateServiceScreenState();
}

class _CreateServiceScreenState extends State<CreateServiceScreen>
    with TickerProviderStateMixin {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSubmitting = false;

  // ── ENTREPRISES ─────────────────────────────────────────────────────────────
  // Quand on arrive depuis MesServicesScreen, l'entreprise est déjà connue.
  // On ne charge plus la liste des entreprises si elle est passée en paramètre.
  List<Map<String, dynamic>> _mesEntreprises = [];
  bool _isLoadingEntreprises = false;           // false par défaut si pré-sélectionnée
  Map<String, dynamic>? _selectedEntreprise;

  // ── DOMAINES ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _domaines = [];
  bool _isLoadingDomaines = false;
  String? _selectedDomaineId;

  // ── STEP 1 : Infos de base ───────────────────────────────────────────────────
  final _nameCtrl  = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  bool _isPriceOnRequest = false;
  bool _hasPromo         = false;

  // ── STEP 2 : Horaires ─────────────────────────────────────────────────────────
  bool _isAlwaysOpen = false;
  final Map<String, bool> _dayOpen = {
    'monday': false, 'tuesday': false, 'wednesday': false,
    'thursday': false, 'friday': false, 'saturday': false, 'sunday': false,
  };
  final Map<String, TextEditingController> _dayStart = {};
  final Map<String, TextEditingController> _dayEnd   = {};
  final Map<String, String> _dayNames = {
    'monday': 'Lundi', 'tuesday': 'Mardi', 'wednesday': 'Mercredi',
    'thursday': 'Jeudi', 'friday': 'Vendredi',
    'saturday': 'Samedi', 'sunday': 'Dimanche',
  };

  // ── STEP 3 : Médias ───────────────────────────────────────────────────────────
  final List<File>   _mediaFiles    = [];
  final List<String> _mediaPreviews = [];

  // ── Flag : entreprise fournie depuis l'extérieur ──────────────────────────────
  // Quand true, le champ entreprise est en lecture seule et on n'affiche
  // pas le sélecteur multiple.
  bool get _entreprisePreset => widget.entreprise != null;

  @override
  void initState() {
    super.initState();

    // Initialiser les contrôleurs d'horaires
    for (final day in _dayNames.keys) {
      _dayStart[day] = TextEditingController(text: '08:00');
      _dayEnd[day]   = TextEditingController(text: '18:00');
    }

    if (_entreprisePreset) {
      // ── Cas normal : on vient de MesServicesScreen ──────────────────────
      // 1. Pré-sélectionner l'entreprise directement (pas de chargement réseau)
      _selectedEntreprise = Map<String, dynamic>.from(widget.entreprise!);
      _mesEntreprises     = [_selectedEntreprise!];

      // 2. Utiliser les domaines déjà chargés si disponibles
      if (widget.preloadedDomaines.isNotEmpty) {
        _domaines = List<Map<String, dynamic>>.from(widget.preloadedDomaines);
        // Auto-sélectionner si un seul domaine
        if (_domaines.length == 1) {
          _selectedDomaineId = _domaines.first['id'];
        }
      } else {
        // Fallback : charger les domaines de l'entreprise via API
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _loadDomainesForEntreprise(_selectedEntreprise!));
      }

      // 3. Vérifier les limites d'essai
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _checkTrialLimits(_selectedEntreprise!));
    } else {
      // ── Cas générique : ouverture hors contexte MesServicesScreen ────────
      _loadMesEntreprises();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _descCtrl.dispose();
    _priceCtrl.dispose(); _promoCtrl.dispose();
    for (final c in _dayStart.values) c.dispose();
    for (final c in _dayEnd.values)   c.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ── Chargement des entreprises (cas générique uniquement) ─────────────────────
  Future<void> _loadMesEntreprises() async {
    setState(() => _isLoadingEntreprises = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/entreprises/mine'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final List raw = jsonDecode(res.body);
        final validated = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => e['status'] == 'validated')
            .toList();

        if (mounted) {
          setState(() {
            _mesEntreprises     = validated;
            _isLoadingEntreprises = false;
          });

          if (validated.length == 1) {
            await _onEntrepriseSelected(validated.first);
          }
        }
      } else {
        if (mounted) setState(() => _isLoadingEntreprises = false);
      }
    } catch (e) {
      debugPrint('Erreur chargement entreprises: $e');
      if (mounted) setState(() => _isLoadingEntreprises = false);
    }
  }

  // ── Chargement des domaines d'une entreprise ──────────────────────────────────
  Future<void> _loadDomainesForEntreprise(Map<String, dynamic> entreprise) async {
    setState(() { _isLoadingDomaines = true; _domaines = []; _selectedDomaineId = null; });

    // 1. Depuis l'objet entreprise
    final rawDomaines = entreprise['domaines'];
    if (rawDomaines is List && rawDomaines.isNotEmpty) {
      final parsed = _parseDomaines(rawDomaines);
      if (parsed.isNotEmpty) {
        if (mounted) {
          setState(() {
            _domaines          = parsed;
            _isLoadingDomaines = false;
            if (parsed.length == 1) _selectedDomaineId = parsed.first['id'];
          });
        }
        return;
      }
    }

    // 2. Fallback API
    try {
      final token = await _storage.read(key: 'auth_token');
      final id    = entreprise['id']?.toString() ?? '';
      final res   = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/entreprises/$id'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final data     = jsonDecode(res.body) as Map<String, dynamic>;
        final domaines = data['domaines'];
        final parsed   = _parseDomaines(domaines is List ? domaines : []);
        if (mounted) {
          setState(() {
            _domaines          = parsed;
            _isLoadingDomaines = false;
            if (parsed.length == 1) _selectedDomaineId = parsed.first['id'];
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingDomaines = false);
      }
    } catch (e) {
      debugPrint('Erreur chargement domaines: $e');
      if (mounted) setState(() => _isLoadingDomaines = false);
    }
  }

  // ── Sélection d'une entreprise (cas générique) ────────────────────────────────
  Future<void> _onEntrepriseSelected(Map<String, dynamic> entreprise) async {
    setState(() {
      _selectedEntreprise = entreprise;
      _selectedDomaineId  = null;
    });
    await _loadDomainesForEntreprise(entreprise);
    _checkTrialLimits(entreprise);
  }

  List<Map<String, dynamic>> _parseDomaines(List raw) => raw
      .whereType<Map>()
      .map((d) => {
            'id':   d['id']?.toString()   ?? '',
            'name': d['name']?.toString() ?? '',
          })
      .where((d) => d['id']!.isNotEmpty && d['name']!.isNotEmpty)
      .toList();

  void _checkTrialLimits(Map<String, dynamic> entreprise) {
    final bool isInTrial  = entreprise['is_in_trial_period'] == true ||
        (entreprise['trial_status'] is Map &&
            entreprise['trial_status']['status'] == 'active');
    final int current     = (entreprise['services'] as List?)?.length ??
        entreprise['services_count'] ?? 0;
    final int? maxAllowed = int.tryParse(
        entreprise['max_services_allowed']?.toString() ?? '');

    if (isInTrial && maxAllowed != null && current >= maxAllowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTrialLimitDialog(maxServices: maxAllowed, currentServices: current);
      });
    }
  }

  // ── Navigation stepper ────────────────────────────────────────────────────────
  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  bool _validateStep() {
    switch (_currentStep) {
      case 0:
        if (_selectedEntreprise == null) {
          _showError('Sélectionnez une entreprise'); return false;
        }
        if (_selectedDomaineId == null) {
          _showError('Sélectionnez un domaine d\'activité'); return false;
        }
        if (_nameCtrl.text.trim().isEmpty) {
          _showError('Le nom du service est requis'); return false;
        }
        if (!_isPriceOnRequest && _priceCtrl.text.trim().isEmpty) {
          _showError('Entrez un prix ou cochez "Sur devis"'); return false;
        }
        if (_hasPromo && _promoCtrl.text.trim().isEmpty) {
          _showError('Entrez un prix promotionnel'); return false;
        }
        return true;
      case 1:
        if (!_isAlwaysOpen && !_dayOpen.values.any((v) => v)) {
          _showError('Sélectionnez au moins un jour ouvert'); return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateStep()) return;
    if (_currentStep < 2) _goToStep(_currentStep + 1);
  }

  // ── Photos ────────────────────────────────────────────────────────────────────
  Future<void> _pickMedia() async {
    if (_mediaFiles.length >= 5) { _showError('Maximum 5 photos'); return; }
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

  // ── Soumission ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_validateStep()) return;
    setState(() => _isSubmitting = true);
    try {
      final token   = await _storage.read(key: 'auth_token');
      final request = http.MultipartRequest(
        'POST', Uri.parse('${AppConstants.apiBaseUrl}/services'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $token', 'Accept': 'application/json',
      });

      request.fields['name']           = _nameCtrl.text.trim();
      request.fields['descriptions']   = _descCtrl.text.trim();
      request.fields['entreprise_id']  = _selectedEntreprise!['id'].toString();
      request.fields['domaine_id']     = _selectedDomaineId!;
      request.fields['is_price_on_request'] = _isPriceOnRequest ? '1' : '0';

      if (!_isPriceOnRequest && _priceCtrl.text.isNotEmpty) {
        request.fields['price'] = _priceCtrl.text.trim();
      }
      request.fields['has_promo'] = _hasPromo ? '1' : '0';
      if (_hasPromo && _promoCtrl.text.isNotEmpty) {
        request.fields['price_promo'] = _promoCtrl.text.trim();
      }

      request.fields['is_always_open'] = _isAlwaysOpen ? '1' : '0';
      if (!_isAlwaysOpen) {
        for (final day in _dayNames.keys) {
          request.fields['schedule[$day][is_open]'] = _dayOpen[day]! ? '1' : '0';
          if (_dayOpen[day]!) {
            request.fields['schedule[$day][start]'] = _dayStart[day]!.text;
            request.fields['schedule[$day][end]']   = _dayEnd[day]!.text;
          }
        }
      }

      for (int i = 0; i < _mediaFiles.length; i++) {
        final f   = _mediaFiles[i];
        final ext = f.path.split('.').last.toLowerCase();
        request.files.add(await http.MultipartFile.fromPath(
          'medias[]', f.path,
          contentType: MediaType('image', ext == 'jpg' ? 'jpeg' : ext),
        ));
      }

      final response = await request.send();
      final body     = await response.stream.bytesToString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSuccessDialog();
      } else {
        if (response.statusCode == 403) {
          final data    = jsonDecode(body);
          final message = data['message'] ?? '';
          if (message.contains('limite') || message.contains('essai')) {
            _showTrialLimitDialog(
              maxServices:     data['max_services']     ?? 3,
              currentServices: data['current_services'] ?? 0,
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    const steps = ['Infos', 'Horaires', 'Photos'];
    const icons = [Icons.info_outline, Icons.schedule, Icons.photo_library];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(children: [
        _buildHeader(steps, icons),
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [_buildStep1(), _buildStep2(), _buildStep3()],
          ),
        ),
        _buildNavButtons(),
      ]),
    );
  }

  // ── Header stepper ────────────────────────────────────────────────────────────
  Widget _buildHeader(List<String> steps, List<IconData> icons) {
    return Container(
      decoration: const BoxDecoration(
        color: AppConstants.primaryRed,
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
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
              const Expanded(
                child: Text('Créer un service',
                    style: TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
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
            Row(
              children: List.generate(3, (i) {
                final isDone    = i < _currentStep;
                final isCurrent = i == _currentStep;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    child: Column(children: [
                      Row(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: isCurrent ? 34 : 26,
                          height: isCurrent ? 34 : 26,
                          decoration: BoxDecoration(
                            color: isDone || isCurrent
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(isDone ? Icons.check : icons[i],
                              size: isCurrent ? 16 : 13,
                              color: isDone || isCurrent
                                  ? AppConstants.primaryRed
                                  : Colors.white),
                        ),
                        if (i < 2)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: i < _currentStep
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Text(steps[i],
                          style: TextStyle(
                              color: isCurrent
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.7),
                              fontSize: 10,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal),
                          textAlign: TextAlign.center),
                    ]),
                  ),
                );
              }),
            ),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEP 1 — Infos de base
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStep1() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── Section Entreprise ────────────────────────────────────────────────
      _sectionTitle(Icons.business_rounded, 'Entreprise',
          'Entreprise associée à ce service'),
      const SizedBox(height: 14),

      // Cas normal (depuis MesServicesScreen) : lecture seule, pas de sélecteur
      if (_entreprisePreset)
        _buildEntrepriseReadOnly()
      else if (_isLoadingEntreprises)
        _loadingWidget('Chargement de vos entreprises…')
      else if (_mesEntreprises.isEmpty)
        _emptyWidget(Icons.business_outlined, 'Aucune entreprise validée',
            'Votre entreprise doit être validée pour créer des services.')
      else
        _buildEntrepriseSelector(),

      const SizedBox(height: 20),

      // ── Section Domaine ───────────────────────────────────────────────────
      _sectionTitle(Icons.category_outlined, 'Domaine d\'activité',
          'Sélectionnez le domaine de ce service'),
      const SizedBox(height: 14),

      _buildDomaineSelector(),

      const SizedBox(height: 20),

      // ── Infos service ─────────────────────────────────────────────────────
      _sectionTitle(Icons.info_outline, 'Informations du service',
          'Nom et description'),
      const SizedBox(height: 14),

      _label('Nom du service', required: true),
      _field(_nameCtrl, 'Ex: Vidange moteur', Icons.build_circle_outlined),
      const SizedBox(height: 14),

      _label('Description'),
      TextFormField(
        controller: _descCtrl,
        maxLines: 3,
        style: const TextStyle(fontSize: 14),
        decoration: _inputDeco('Décrivez votre service…', Icons.description_outlined),
      ),
      const SizedBox(height: 20),

      // ── Tarification ──────────────────────────────────────────────────────
      _sectionTitle(Icons.payments_outlined, 'Tarification',
          'Définissez le prix de votre service'),
      const SizedBox(height: 14),

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

  // ── Entreprise en LECTURE SEULE (depuis MesServicesScreen) ────────────────────
  Widget _buildEntrepriseReadOnly() {
    final e    = _selectedEntreprise!;
    final logo = e['logo']?.toString() ?? '';

    // Domaines en chips depuis l'objet entreprise
    final doms = e['domaines'];
    final domList = doms is List
        ? doms.whereType<Map>().map((d) => d['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList()
        : <String>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        // Logo
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            image: logo.isNotEmpty
                ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover)
                : null,
          ),
          child: logo.isEmpty
              ? Icon(Icons.business, color: Colors.grey.shade400, size: 22)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  e['name']?.toString() ?? 'Entreprise',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Badge "validée"
              if (e['status'] == 'validated')
                Row(mainAxisSize: MainAxisSize.min, children: const [
                  SizedBox(width: 4),
                  Icon(Icons.verified_rounded, size: 14, color: Color(0xFF4CAF50)),
                  SizedBox(width: 2),
                  Text('Validée',
                      style: TextStyle(fontSize: 10, color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600)),
                ]),
            ]),
            if (domList.isNotEmpty) ...[
              const SizedBox(height: 5),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: domList
                    .take(3)
                    .map((d) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppConstants.primaryRed.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(d,
                              style: const TextStyle(fontSize: 10,
                                  color: AppConstants.primaryRed,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ],
          ]),
        ),
        // Icône cadenas = lecture seule
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade400),
        ),
      ]),
    );
  }

  // ── Widget sélecteur d'entreprise (cas générique) ─────────────────────────────
  Widget _buildEntrepriseSelector() {
    if (_mesEntreprises.length == 1) {
      final e = _mesEntreprises.first;
      return _SelectedEntrepriseCard(entreprise: e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selectedEntreprise != null
                  ? AppConstants.primaryRed.withOpacity(0.4)
                  : Colors.grey.shade200,
              width: _selectedEntreprise != null ? 1.5 : 1,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedEntreprise?['id']?.toString(),
              isExpanded: true,
              hint: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Icon(Icons.business_outlined, size: 18, color: Colors.grey.shade400),
                  const SizedBox(width: 10),
                  Text('Sélectionnez une entreprise',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ]),
              ),
              borderRadius: BorderRadius.circular(14),
              padding: EdgeInsets.zero,
              items: _mesEntreprises.map((e) {
                final logo = e['logo']?.toString() ?? '';
                return DropdownMenuItem<String>(
                  value: e['id'].toString(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          image: logo.isNotEmpty
                              ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover)
                              : null,
                        ),
                        child: logo.isEmpty
                            ? Icon(Icons.business, size: 16, color: Colors.grey.shade400)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e['name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ),
                );
              }).toList(),
              onChanged: (id) {
                final found = _mesEntreprises.firstWhere(
                    (e) => e['id'].toString() == id,
                    orElse: () => <String, dynamic>{});
                if (found.isNotEmpty) _onEntrepriseSelected(found);
              },
            ),
          ),
        ),
        if (_selectedEntreprise != null) ...[
          const SizedBox(height: 10),
          _SelectedEntrepriseCard(entreprise: _selectedEntreprise!),
        ],
      ],
    );
  }

  // ── Widget sélecteur de domaine ───────────────────────────────────────────────
  Widget _buildDomaineSelector() {
    if (_selectedEntreprise == null) {
      return _infoBox(Icons.info_outline, Colors.grey.shade400,
          Colors.grey.shade50, Colors.grey.shade200,
          'Sélectionnez d\'abord une entreprise pour voir ses domaines.');
    }

    if (_isLoadingDomaines) {
      return _loadingWidget('Chargement des domaines…');
    }

    if (_domaines.isEmpty) {
      return _infoBox(Icons.warning_amber_rounded, Colors.orange.shade600,
          Colors.orange.shade50, Colors.orange.shade200,
          'Aucun domaine d\'activité trouvé pour cette entreprise.');
    }

    // Un seul domaine → badge sélectionné automatiquement
    if (_domaines.length == 1) {
      final d = _domaines.first;
      if (_selectedDomaineId != d['id']) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _selectedDomaineId = d['id']));
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppConstants.primaryRed.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppConstants.primaryRed.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: AppConstants.primaryRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.category_rounded,
                color: AppConstants.primaryRed, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(d['name']!,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const Icon(Icons.check_circle_rounded,
              color: AppConstants.primaryRed, size: 18),
        ]),
      );
    }

    // Plusieurs domaines → chips sélectionnables
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _domaines.map((d) {
        final isSelected = _selectedDomaineId == d['id'];
        return GestureDetector(
          onTap: () => setState(() => _selectedDomaineId = d['id']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppConstants.primaryRed : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppConstants.primaryRed : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.2),
                      blurRadius: 8, offset: const Offset(0, 2))]
                  : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.category_outlined,
                size: 15,
                color: isSelected ? Colors.white : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(d['name']!,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey.shade700)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEP 2 — Horaires
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStep2() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(Icons.schedule, 'Horaires d\'ouverture',
          'Définissez quand votre service est disponible'),
      const SizedBox(height: 20),

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
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Activez les jours où vous êtes disponible',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        ..._dayNames.entries.map((entry) {
          final day    = entry.key;
          final name   = entry.value;
          final isOpen = _dayOpen[day]!;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isOpen
                      ? AppConstants.primaryRed.withOpacity(0.3)
                      : Colors.grey.shade200),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: isOpen ? FontWeight.w700 : FontWeight.normal,
                          color: isOpen ? Colors.black87 : Colors.grey.shade500)),
                  const Spacer(),
                  Switch(
                    value: isOpen,
                    onChanged: (v) => setState(() => _dayOpen[day] = v),
                    activeColor: AppConstants.primaryRed,
                  ),
                ]),
              ),
              if (isOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Row(children: [
                    Expanded(child: _timeField(_dayStart[day]!, 'Ouverture')),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('—', style: TextStyle(color: Colors.grey.shade400))),
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

  Widget _timeField(TextEditingController ctrl, String hint) =>
      GestureDetector(
        onTap: () async {
          final t = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(
              hour:   int.tryParse(ctrl.text.split(':')[0]) ?? 8,
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
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200)),
          child: Row(children: [
            Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(ctrl.text.isEmpty ? hint : ctrl.text,
                style: TextStyle(
                    fontSize: 13,
                    color: ctrl.text.isEmpty ? Colors.grey.shade400 : Colors.black87)),
          ]),
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEP 3 — Médias + récap
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStep3() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(Icons.photo_library, 'Photos du service',
          'Ajoutez jusqu\'à 5 photos (optionnel)'),
      const SizedBox(height: 16),

      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: [
          ..._mediaPreviews.asMap().entries.map((e) => Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(e.value),
                  fit: BoxFit.cover, width: double.infinity, height: double.infinity),
            ),
            Positioned(
              top: 4, right: 4,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppConstants.primaryRed.withOpacity(0.4), width: 1.5),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      color: AppConstants.primaryRed, size: 28),
                  const SizedBox(height: 4),
                  Text('Ajouter',
                      style: TextStyle(fontSize: 11, color: AppConstants.primaryRed,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
        ],
      ),

      const SizedBox(height: 24),

      _sectionTitle(Icons.checklist, 'Récapitulatif', ''),
      const SizedBox(height: 12),

      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(children: [
          _recapRow('Entreprise', _selectedEntreprise?['name']?.toString() ?? '—'),
          _recapRow('Domaine', _domaines
              .firstWhere((d) => d['id'] == _selectedDomaineId,
                  orElse: () => {'name': '—'})['name']!),
          _recapRow('Service', _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '—'),
          _recapRow('Prix',
              _isPriceOnRequest
                  ? 'Sur devis'
                  : _priceCtrl.text.isNotEmpty
                      ? '${_priceCtrl.text} FCFA'
                      : '—'),
          if (_hasPromo && _promoCtrl.text.isNotEmpty)
            _recapRow('Prix promo', '${_promoCtrl.text} FCFA'),
          _recapRow('Disponibilité',
              _isAlwaysOpen
                  ? '24h/24'
                  : '${_dayOpen.values.where((v) => v).length} jour(s)'),
          _recapRow('Photos', '${_mediaFiles.length} photo(s)'),
        ]),
      ),
      const SizedBox(height: 20),
    ]),
  );

  // ── Boutons de navigation ─────────────────────────────────────────────────────
  Widget _buildNavButtons() {
    final isLast     = _currentStep == 2;
    final canProceed = !_isLoadingEntreprises && !_isLoadingDomaines;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 12, offset: const Offset(0, -3))
        ],
      ),
      child: Row(children: [
        if (_currentStep > 0) ...[
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              onPressed: () => _goToStep(_currentStep - 1),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Précédent'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 3,
          child: ElevatedButton(
            onPressed: (_isSubmitting || !canProceed)
                ? null
                : (isLast ? _submit : _next),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isLast ? Colors.green.shade600 : AppConstants.primaryRed,
              foregroundColor: Colors.white,
              elevation: 0,
              disabledBackgroundColor: Colors.grey.shade200,
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
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  DIALOGS
  // ─────────────────────────────────────────────────────────────────────────────
  void _showTrialLimitDialog({required int maxServices, required int currentServices}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.lock_outline_rounded,
                    color: Colors.orange, size: 44),
              ),
              const SizedBox(height: 20),
              const Text('Limite de services atteinte',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.home_repair_service_outlined,
                      color: Colors.orange.shade700, size: 16),
                  const SizedBox(width: 8),
                  Text('$currentServices / $maxServices services utilisés',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700)),
                ]),
              ),
              const SizedBox(height: 14),
              Text(
                'Votre période d\'essai vous permet de créer jusqu\'à '
                '$maxServices service${maxServices > 1 ? 's' : ''}. '
                'Souscrivez à un plan payant pour en ajouter davantage.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const PlansAbonnementScreen()));
                  },
                  icon: const Icon(Icons.subscriptions_outlined, size: 16),
                  label: const Text('Voir les plans'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: const Text('Retour'),
                ),
              ),
            ]),
          ),
        ),
      ),
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
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 44),
          ),
          const SizedBox(height: 18),
          const Text('Service créé !',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Votre service a été ajouté avec succès.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: const Text('OK'),
            ),
          ),
        ]),
      ),
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────────
  //  WIDGETS HELPERS
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _sectionTitle(IconData icon, String title, String sub) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppConstants.primaryRed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AppConstants.primaryRed, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          if (sub.isNotEmpty)
            Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ),
    ]),
  );

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
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 18),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppConstants.primaryRed, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  Widget _toggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? color,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: value
                  ? (color ?? AppConstants.primaryRed).withOpacity(0.3)
                  : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: (color ?? AppConstants.primaryRed).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color ?? AppConstants.primaryRed, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          ),
          Switch(value: value, onChanged: onChanged,
              activeColor: color ?? AppConstants.primaryRed),
        ]),
      );

  Widget _recapRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(
        width: 90,
        child: Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500,
                fontWeight: FontWeight.w500)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    ]),
  );

  Widget _loadingWidget(String msg) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(children: [
      const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryRed)),
      const SizedBox(width: 12),
      Text(msg, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
    ]),
  );

  Widget _emptyWidget(IconData icon, String title, String sub) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(children: [
      Icon(icon, size: 40, color: Colors.grey.shade300),
      const SizedBox(height: 10),
      Text(title,
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
      const SizedBox(height: 4),
      Text(sub,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _infoBox(IconData icon, Color iconColor, Color bg, Color border, String msg) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border)),
        child: Row(children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: iconColor))),
        ]),
      );

  void _showError(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Widget carte entreprise sélectionnée (cas générique / multiple entreprises)
// ─────────────────────────────────────────────────────────────────────────────
class _SelectedEntrepriseCard extends StatelessWidget {
  final Map<String, dynamic> entreprise;
  const _SelectedEntrepriseCard({required this.entreprise});

  @override
  Widget build(BuildContext context) {
    final logo   = entreprise['logo']?.toString() ?? '';
    final name   = entreprise['name']?.toString() ?? 'Entreprise';
    final status = entreprise['status']?.toString() ?? '';

    final doms    = entreprise['domaines'];
    final domList = doms is List
        ? doms.whereType<Map>().map((d) => d['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList()
        : <String>[];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.primaryRed.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.primaryRed.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            image: logo.isNotEmpty
                ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover)
                : null,
          ),
          child: logo.isEmpty
              ? Icon(Icons.business, color: Colors.grey.shade400, size: 22)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (status == 'validated')
                Row(mainAxisSize: MainAxisSize.min, children: const [
                  SizedBox(width: 4),
                  Icon(Icons.verified_rounded, size: 14, color: Color(0xFF4CAF50)),
                  SizedBox(width: 2),
                  Text('Validée',
                      style: TextStyle(fontSize: 10, color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600)),
                ]),
            ]),
            if (domList.isNotEmpty) ...[
              const SizedBox(height: 5),
              Wrap(
                spacing: 4, runSpacing: 4,
                children: domList
                    .take(3)
                    .map((d) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppConstants.primaryRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(d,
                              style: const TextStyle(fontSize: 10,
                                  color: AppConstants.primaryRed,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ],
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: AppConstants.primaryRed.withOpacity(0.1),
              shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 14, color: AppConstants.primaryRed),
        ),
      ]),
    );
  }
}