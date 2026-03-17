import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

class EditServiceScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  final Map<String, dynamic> entreprise;
  const EditServiceScreen(
      {super.key, required this.service, required this.entreprise});

  @override
  State<EditServiceScreen> createState() => _EditServiceScreenState();
}

class _EditServiceScreenState extends State<EditServiceScreen>
    with TickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSubmitting = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _promoCtrl;
  late bool _isPriceOnRequest;
  late bool _hasPromo;
  String? _selectedDomaineId;
  List<dynamic> _domaines = [];

  late bool _isAlwaysOpen;
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

  List<String> _existingMediaUrls = [];
  List<String> _deletedMediaUrls = [];
  final List<File> _newMediaFiles = [];
  final List<String> _newMediaPreviews = [];

  @override
  void initState() {
    super.initState();
    final s = widget.service;

    _nameCtrl = TextEditingController(text: s['name'] ?? '');
    _descCtrl = TextEditingController(text: s['descriptions'] ?? '');
    _priceCtrl = TextEditingController(text: s['price']?.toString() ?? '');
    _promoCtrl = TextEditingController(text: s['price_promo']?.toString() ?? '');
    _isPriceOnRequest = s['is_price_on_request'] == true;
    _hasPromo = s['has_promo'] == true;
    _isAlwaysOpen = s['is_always_open'] == true;
    _selectedDomaineId = s['domaine']?['id']?.toString();
    _existingMediaUrls =
        List<String>.from(s['medias'] is List ? s['medias'] : []);

    for (final day in _dayNames.keys) {
      final schedule = s['schedule'] as Map? ?? {};
      final dayData = schedule[day] as Map? ?? {};
      _dayOpen[day] = dayData['is_open'] == true;
      _dayStart[day] = TextEditingController(
          text: dayData['start']?.toString() ?? '08:00');
      _dayEnd[day] = TextEditingController(
          text: dayData['end']?.toString() ?? '18:00');
    }

    _fetchDomaines();
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

  Future<void> _fetchDomaines() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/domaines'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final List raw = jsonDecode(res.body);
        final entrepriseDomaines =
            (widget.entreprise['domaines'] as List? ?? [])
                .map((d) => d['id'].toString())
                .toSet();
        setState(() {
          _domaines = raw
              .where((d) => entrepriseDomaines.contains(d['id'].toString()))
              .toList();
          if (_selectedDomaineId == null && _domaines.isNotEmpty) {
            _selectedDomaineId = _domaines.first['id'].toString();
          }
        });
      }
    } catch (_) {}
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  bool _validateStep() {
    switch (_currentStep) {
      case 0:
        if (_nameCtrl.text.trim().isEmpty) {
          _showError('Le nom est requis'); return false;
        }
        if (!_isPriceOnRequest && _priceCtrl.text.trim().isEmpty) {
          _showError('Entrez un prix ou cochez "Sur devis"'); return false;
        }
        return true;
      case 1:
        if (!_isAlwaysOpen && !_dayOpen.values.any((v) => v)) {
          _showError('Sélectionnez au moins un jour'); return false;
        }
        return true;
      default: return true;
    }
  }

  Future<void> _pickMedia() async {
    final total = _existingMediaUrls.length + _newMediaFiles.length;
    if (total >= 5) { _showError('Maximum 5 photos'); return; }
    final source = await _showSourceDialog();
    if (source == null) return;
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, imageQuality: 70, maxWidth: 1200);
      if (picked != null) setState(() {
        _newMediaFiles.add(File(picked.path));
        _newMediaPreviews.add(picked.path);
      });
    } catch (_) {}
  }

  Future<ImageSource?> _showSourceDialog() =>
      showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.camera_alt, color: AppConstants.primaryRed),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
          const SizedBox(height: 8),
        ])),
      );

  Future<void> _submit() async {
    if (!_validateStep()) return;
    setState(() => _isSubmitting = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.apiBaseUrl}/services/${widget.service['id']}'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'X-HTTP-Method-Override': 'PUT',
      });
      request.fields['_method'] = 'PUT';

      request.fields['name'] = _nameCtrl.text.trim();
      // ✅ Envoyer descriptions seulement si non vide (comme le web)
      if (_descCtrl.text.trim().isNotEmpty) {
        request.fields['descriptions'] = _descCtrl.text.trim();
      }
      request.fields['is_price_on_request'] = _isPriceOnRequest ? '1' : '0';

      if (!_isPriceOnRequest) {
        if (_priceCtrl.text.isNotEmpty) {
          request.fields['price'] = _priceCtrl.text.trim();
        }
        request.fields['has_promo'] = _hasPromo ? '1' : '0';
        if (_hasPromo && _promoCtrl.text.isNotEmpty) {
          request.fields['price_promo'] = _promoCtrl.text.trim();
        }
      } else {
        request.fields['has_promo'] = '0';
      }

      // ✅ CORRECTION 1 : envoyer le domaine_id
      if (_selectedDomaineId != null) {
        request.fields['domaine_id'] = _selectedDomaineId!;
      }

      request.fields['is_always_open'] = _isAlwaysOpen ? '1' : '0';
      if (!_isAlwaysOpen) {
        for (final day in _dayNames.keys) {
          request.fields['schedule[$day][is_open]'] = _dayOpen[day]! ? '1' : '0';
          if (_dayOpen[day]!) {
            request.fields['schedule[$day][start]'] = _dayStart[day]!.text;
            request.fields['schedule[$day][end]'] = _dayEnd[day]!.text;
          }
        }
      }

      // ✅ CORRECTION 2 : envoyer deleted_medias avec index numérique
      // (évite que Flutter écrase la même clé en boucle)
      for (int i = 0; i < _deletedMediaUrls.length; i++) {
        request.fields['deleted_medias[$i]'] = _deletedMediaUrls[i];
      }

      // Nouveaux médias
      for (final f in _newMediaFiles) {
        final ext = f.path.split('.').last.toLowerCase();
        request.files.add(await http.MultipartFile.fromPath(
          'medias[]', f.path,
          contentType: MediaType('image', ext == 'jpg' ? 'jpeg' : ext),
        ));
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Service mis à jour avec succès !'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
          Navigator.pop(context);
        }
      } else {
        // ✅ CORRECTION 3 : afficher le vrai message d'erreur Laravel
        try {
          final data = jsonDecode(body);
          String errorMsg = data['message'] ?? 'Erreur lors de la mise à jour';
          if (data['errors'] != null) {
            final errors = data['errors'] as Map;
            errorMsg = errors.values.first[0];
          }
          _showError(errorMsg);
        } catch (_) {
          _showError('Erreur ${response.statusCode}');
        }
      }
    } catch (e) {
      _showError('Erreur de connexion : $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
  );

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

  Widget _buildHeader(List<String> steps, List<IconData> icons) =>
      Container(
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
              GestureDetector(onTap: () => Navigator.pop(context),
                child: Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 20))),
              const SizedBox(width: 12),
              const Expanded(child: Text('Modifier le service',
                  style: TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.bold))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${_currentStep + 1}/3',
                    style: const TextStyle(color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 16),
            Row(children: List.generate(3, (i) {
              final isDone = i < _currentStep, isCurrent = i == _currentStep;
              return Expanded(child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                child: Column(children: [
                  Row(children: [
                    AnimatedContainer(duration: const Duration(milliseconds: 300),
                      width: isCurrent ? 34 : 26, height: isCurrent ? 34 : 26,
                      decoration: BoxDecoration(
                          color: isDone || isCurrent ? Colors.white : Colors.white.withOpacity(0.3),
                          shape: BoxShape.circle),
                      child: Icon(isDone ? Icons.check : icons[i],
                          size: isCurrent ? 16 : 13,
                          color: isDone || isCurrent ? AppConstants.primaryRed : Colors.white)),
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

  Widget _buildStep1() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionCard(Icons.info_outline, 'Informations de base', ''),
      const SizedBox(height: 20),
      _label('Nom du service', required: true),
      _field(_nameCtrl, 'Nom du service', Icons.build_circle_outlined),
      const SizedBox(height: 14),
      _label('Description'),
      TextFormField(controller: _descCtrl, maxLines: 3,
          style: const TextStyle(fontSize: 14),
          decoration: _inputDeco('Description...', Icons.description_outlined)),
      const SizedBox(height: 14),
      if (_domaines.isNotEmpty) ...[
        _label('Domaine'),
        Container(
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDomaineId,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              items: _domaines.map((d) => DropdownMenuItem(
                value: d['id'].toString(),
                child: Text(d['name'] ?? ''),
              )).toList(),
              onChanged: (v) => setState(() => _selectedDomaineId = v),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      _toggleCard(Icons.request_quote_outlined, 'Prix sur devis', '',
          _isPriceOnRequest, (v) => setState(() {
            _isPriceOnRequest = v;
            if (v) _hasPromo = false;
          })),
      if (!_isPriceOnRequest) ...[
        const SizedBox(height: 12),
        _label('Prix (FCFA)', required: true),
        _field(_priceCtrl, 'Prix', Icons.attach_money,
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        _toggleCard(Icons.local_offer_outlined, 'Promotion', '',
            _hasPromo, (v) => setState(() => _hasPromo = v)),
        if (_hasPromo) ...[
          const SizedBox(height: 12),
          _label('Prix promo (FCFA)'),
          _field(_promoCtrl, 'Prix promotionnel', Icons.sell_outlined,
              keyboardType: TextInputType.number),
        ],
      ],
      const SizedBox(height: 20),
    ]),
  );

  Widget _buildStep2() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionCard(Icons.schedule, 'Horaires', ''),
      const SizedBox(height: 16),
      _toggleCard(Icons.all_inclusive, '24h/24', 'Service disponible en permanence',
          _isAlwaysOpen, (v) => setState(() => _isAlwaysOpen = v), color: Colors.green),
      if (!_isAlwaysOpen) ...[
        const SizedBox(height: 14),
        ..._dayNames.entries.map((entry) {
          final day = entry.key;
          final name = entry.value;
          final isOpen = _dayOpen[day]!;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isOpen ? AppConstants.primaryRed.withOpacity(0.3) : Colors.grey[200]!),
            ),
            child: Column(children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Text(name, style: TextStyle(fontSize: 14,
                      fontWeight: isOpen ? FontWeight.w700 : FontWeight.normal,
                      color: isOpen ? Colors.black87 : Colors.grey[500])),
                  const Spacer(),
                  Switch(value: isOpen,
                      onChanged: (v) => setState(() => _dayOpen[day] = v),
                      activeColor: AppConstants.primaryRed),
                ])),
              if (isOpen)
                Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Row(children: [
                    Expanded(child: _timeField(_dayStart[day]!, 'Ouverture')),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('—', style: TextStyle(color: Colors.grey))),
                    Expanded(child: _timeField(_dayEnd[day]!, 'Fermeture')),
                  ])),
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
              hour: int.tryParse(ctrl.text.split(':').first) ?? 8,
              minute: int.tryParse(ctrl.text.split(':').last) ?? 0,
            ),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(colorScheme:
                  const ColorScheme.light(primary: AppConstants.primaryRed)),
              child: child!,
            ),
          );
          if (t != null) {
            ctrl.text = '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
            setState(() {});
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
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

  Widget _buildStep3() {
    final totalPhotos = _existingMediaUrls.length + _newMediaFiles.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionCard(Icons.photo_library, 'Photos', 'Max 5 photos'),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 8, mainAxisSpacing: 8,
          children: [
            ..._existingMediaUrls.map((url) => Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                child: Image.network(url, fit: BoxFit.cover,
                    width: double.infinity, height: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: Icon(Icons.broken_image, color: Colors.grey[400])))),
              Positioned(top: 4, right: 4,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _deletedMediaUrls.add(url);
                    _existingMediaUrls.remove(url);
                  }),
                  child: Container(padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 12, color: Colors.white)),
                )),
            ])),
            ..._newMediaPreviews.asMap().entries.map((e) => Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                child: Image.file(File(e.value), fit: BoxFit.cover,
                    width: double.infinity, height: double.infinity)),
              Positioned(top: 4, right: 4,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _newMediaFiles.removeAt(e.key);
                    _newMediaPreviews.removeAt(e.key);
                  }),
                  child: Container(padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 12, color: Colors.white)),
                )),
            ])),
            if (totalPhotos < 5)
              GestureDetector(
                onTap: _pickMedia,
                child: Container(
                  decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppConstants.primaryRed.withOpacity(0.4), width: 1.5)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        color: AppConstants.primaryRed, size: 26),
                    const SizedBox(height: 4),
                    Text('Ajouter', style: TextStyle(fontSize: 10,
                        color: AppConstants.primaryRed, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
          ],
        ),
        if (_deletedMediaUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange[200]!)),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange[700], size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  '${_deletedMediaUrls.length} photo(s) seront supprimées à la sauvegarde.',
                  style: TextStyle(fontSize: 12, color: Colors.orange[800]))),
            ])),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildNavButtons() {
    final isLast = _currentStep == 2;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 12, offset: const Offset(0, -3))]),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
          const SizedBox(width: 12),
        ],
        Expanded(flex: 3, child: ElevatedButton(
          onPressed: _isSubmitting ? null : (isLast ? _submit : () {
            if (_validateStep()) _goToStep(_currentStep + 1);
          }),
          style: ElevatedButton.styleFrom(
              backgroundColor: isLast ? Colors.blue[600] : AppConstants.primaryRed,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(isLast ? Icons.save : Icons.arrow_forward, size: 18),
                  const SizedBox(width: 8),
                  Text(isLast ? 'Enregistrer' : 'Suivant',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
        )),
      ]),
    );
  }

  Widget _sectionCard(IconData icon, String title, String sub) =>
      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppConstants.primaryRed, size: 20)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
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
      TextFormField(controller: ctrl, keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14),
          decoration: _inputDeco(hint, icon));

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
    prefixIcon: Icon(icon, color: Colors.grey[500], size: 18),
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppConstants.primaryRed, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  Widget _toggleCard(IconData icon, String title, String sub,
      bool value, ValueChanged<bool> onChange, {Color? color}) =>
      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
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
            if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ])),
          Switch(value: value, onChanged: onChange,
              activeColor: color ?? AppConstants.primaryRed),
        ]));
}