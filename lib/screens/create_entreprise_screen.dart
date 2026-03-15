import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';

// ── OpenStreetMap (PRIORITAIRE - GRATUIT) ────────
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'dart:ui' as ui;

// ── Google Maps (COMMENTÉ - PEUT DEVENIR PAYANT) ──
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geocoding/geocoding.dart';

class DomaineModel {
  final int id;
  final String name;
  DomaineModel({required this.id, required this.name});
  factory DomaineModel.fromJson(Map<String, dynamic> j) =>
      DomaineModel(id: j['id'], name: j['name']);
}

class CreateEntrepriseScreen extends StatefulWidget {
  const CreateEntrepriseScreen({super.key});
  @override
  State<CreateEntrepriseScreen> createState() => _CreateEntrepriseScreenState();
}

class _CreateEntrepriseScreenState extends State<CreateEntrepriseScreen>
    with TickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  final _pageController = PageController();
  late AnimationController _progressController;

  int _currentStep = 0;
  bool _isSubmitting = false;
  bool _isLoadingDomaines = true;

  List<DomaineModel> _domaines = [];
  List<int> _selectedDomaineIds = [];

  final _nameCtrl = TextEditingController();
  final _ifuNumCtrl = TextEditingController();
  final _rccmNumCtrl = TextEditingController();
  final _certNumCtrl = TextEditingController();
  File? _ifuFile, _rccmFile, _certFile;
  String? _ifuFileName, _rccmFileName, _certFileName;

  final _pdgNameCtrl = TextEditingController();
  final _pdgProfCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _callPhoneCtrl = TextEditingController();
  final _customRoleCtrl = TextEditingController();
  String? _selectedRole;
  bool _showCustomRole = false;
  final List<String> _roles = ['PDG','Directeur Général','Gérant','Directeur','Manager','Autre'];

  final _siegeCtrl = TextEditingController();
  final _locationSearchCtrl = TextEditingController();
  double? _latitude, _longitude;
  String _formattedAddress = '';
  bool _isLocating = false, _isSearchingAddress = false;

  // OSM
  final MapController _mapController = MapController();
  LatLng _mapCenter = const LatLng(6.3703, 2.3912);
  LatLng? _markerPosition;

  // Google Maps (commenté)
  // GoogleMapController? _googleMapController;

  File? _logoFile, _imageBoutiqueFile;
  String? _logoPreviewPath, _boutiquePreviewPath;
  bool _attestationAccepted = false, _privacyAccepted = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fetchDomaines();
  }

  @override
  void dispose() {
    _progressController.dispose(); _pageController.dispose();
    _nameCtrl.dispose(); _ifuNumCtrl.dispose(); _rccmNumCtrl.dispose();
    _certNumCtrl.dispose(); _pdgNameCtrl.dispose(); _pdgProfCtrl.dispose();
    _whatsappCtrl.dispose(); _callPhoneCtrl.dispose(); _customRoleCtrl.dispose();
    _siegeCtrl.dispose(); _locationSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDomaines() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      final res = await http.get(Uri.parse('${AppConstants.apiBaseUrl}/domaines'),
          headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'});
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() { _domaines = data.map((d) => DomaineModel.fromJson(d)).toList(); _isLoadingDomaines = false; });
      }
    } catch (_) { setState(() => _isLoadingDomaines = false); }
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_nameCtrl.text.trim().isEmpty) { _showError('Le nom de l\'entreprise est requis'); return false; }
        if (_selectedDomaineIds.isEmpty) { _showError('Sélectionnez au moins un domaine'); return false; }
        return true;
      case 1:
        if (_ifuNumCtrl.text.trim().isEmpty) { _showError('Le numéro IFU est requis'); return false; }
        if (_ifuFile == null) { _showError('Veuillez joindre le fichier IFU'); return false; }
        if (_rccmNumCtrl.text.trim().isEmpty) { _showError('Le numéro RCCM est requis'); return false; }
        if (_rccmFile == null) { _showError('Veuillez joindre le fichier RCCM'); return false; }
        if (_certNumCtrl.text.trim().isEmpty) { _showError('Le numéro de certificat est requis'); return false; }
        if (_certFile == null) { _showError('Veuillez joindre le fichier certificat'); return false; }
        return true;
      case 2:
        if (_pdgNameCtrl.text.trim().isEmpty) { _showError('Le nom du dirigeant est requis'); return false; }
        if (_pdgProfCtrl.text.trim().isEmpty) { _showError('La profession est requise'); return false; }
        if (_selectedRole == null) { _showError('Veuillez sélectionner votre rôle'); return false; }
        if (_selectedRole == 'Autre' && _customRoleCtrl.text.trim().isEmpty) { _showError('Précisez votre rôle'); return false; }
        if (_whatsappCtrl.text.trim().isEmpty) { _showError('Le numéro WhatsApp est requis'); return false; }
        if (_callPhoneCtrl.text.trim().isEmpty) { _showError('Le numéro d\'appel est requis'); return false; }
        return true;
      case 3:
        if (_latitude == null || _longitude == null) { _showError('La localisation est requise'); return false; }
        return true;
      default: return true;
    }
  }

  void _next() { if (!_validateCurrentStep()) return; if (_currentStep < 3) _goToStep(_currentStep + 1); }
  void _previous() { if (_currentStep > 0) _goToStep(_currentStep - 1); }

  // OSM Nominatim
  Future<void> _searchAddressOSM(String query) async {
    if (query.length < 3) return;
    setState(() => _isSearchingAddress = true);
    try {
      final encoded = Uri.encodeComponent('$query, Bénin');
      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=$encoded&limit=1&addressdetails=1'),
        headers: {'Accept-Language': 'fr', 'User-Agent': 'CarEasyApp/1.0'},
      );
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          await _updatePosition(double.parse(data[0]['lat']), double.parse(data[0]['lon']), address: data[0]['display_name']);
        } else { _showError('Adresse non trouvée'); }
      }
    } catch (_) { _showError('Erreur lors de la recherche'); }
    finally { setState(() => _isSearchingAddress = false); }
  }

  Future<String> _reverseGeocodeOSM(double lat, double lng) async {
    try {
      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng'),
        headers: {'Accept-Language': 'fr', 'User-Agent': 'CarEasyApp/1.0'},
      );
      if (res.statusCode == 200) return jsonDecode(res.body)['display_name']?.toString() ?? '';
    } catch (_) {}
    return '';
  }

  // Google Maps (commenté)
  // Future<void> _searchAddressGoogle(String query) async { ... }
  // Future<String> _reverseGeocodeGoogle(double lat, double lng) async { ... }

  Future<void> _updatePosition(double lat, double lng, {String? address}) async {
    final addr = address ?? await _reverseGeocodeOSM(lat, lng);
    setState(() {
      _latitude = lat; _longitude = lng;
      _formattedAddress = addr; _locationSearchCtrl.text = addr;
      _markerPosition = LatLng(lat, lng); _mapCenter = LatLng(lat, lng);
      if (_siegeCtrl.text.isEmpty && addr.isNotEmpty) {
        final parts = addr.split(',');
        if (parts.length >= 2) _siegeCtrl.text = '${parts[0].trim()}, ${parts[1].trim()}';
      }
    });
    _mapController.move(LatLng(lat, lng), 16.0);
    // Google Maps (commenté)
    // _googleMapController?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(lat, lng), zoom: 17)));
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _showError('Permission de localisation refusée'); return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _updatePosition(pos.latitude, pos.longitude);
    } catch (_) { _showError('Impossible d\'obtenir votre position'); }
    finally { setState(() => _isLocating = false); }
  }

  Future<void> _pickDocument(String field) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','jpg','jpeg','png']);
      if (result != null && result.files.single.path != null) {
        setState(() {
          if (field == 'ifu') { _ifuFile = File(result.files.single.path!); _ifuFileName = result.files.single.name; }
          else if (field == 'rccm') { _rccmFile = File(result.files.single.path!); _rccmFileName = result.files.single.name; }
          else if (field == 'cert') { _certFile = File(result.files.single.path!); _certFileName = result.files.single.name; }
        });
      }
    } catch (_) { _showError('Erreur lors de la sélection du fichier'); }
  }

  Future<void> _pickImage(String field) async {
    final source = await _showImageSourceDialog();
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
      if (picked != null) setState(() {
        if (field == 'logo') { _logoFile = File(picked.path); _logoPreviewPath = picked.path; }
        else { _imageBoutiqueFile = File(picked.path); _boutiquePreviewPath = picked.path; }
      });
    } catch (_) { _showError('Erreur lors de la sélection de l\'image'); }
  }

  Future<ImageSource?> _showImageSourceDialog() => showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.camera_alt, color: AppConstants.primaryRed)), title: const Text('Prendre une photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
      ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.photo_library, color: Colors.blue)), title: const Text('Choisir depuis la galerie'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
    ]))),
  );

  Future<void> _submit() async {
    if (!_attestationAccepted || !_privacyAccepted) { _showError('Veuillez accepter les conditions'); return; }
    setState(() => _isSubmitting = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final request = http.MultipartRequest('POST', Uri.parse('${AppConstants.apiBaseUrl}/entreprises'));
      request.headers.addAll({'Authorization': 'Bearer $token', 'Accept': 'application/json'});
      final role = _selectedRole == 'Autre' ? _customRoleCtrl.text.trim() : _selectedRole!;
      request.fields.addAll({
        'name': _nameCtrl.text.trim(), 'ifu_number': _ifuNumCtrl.text.trim(),
        'rccm_number': _rccmNumCtrl.text.trim(), 'certificate_number': _certNumCtrl.text.trim(),
        'pdg_full_name': _pdgNameCtrl.text.trim(), 'pdg_full_profession': _pdgProfCtrl.text.trim(),
        'role_user': role, 'whatsapp_phone': _whatsappCtrl.text.trim(),
        'call_phone': _callPhoneCtrl.text.trim(), 'latitude': _latitude.toString(), 'longitude': _longitude.toString(),
        if (_siegeCtrl.text.isNotEmpty) 'siege': _siegeCtrl.text.trim(),
        if (_formattedAddress.isNotEmpty) 'google_formatted_address': _formattedAddress,
      });
      for (final id in _selectedDomaineIds) request.fields['domaine_ids[]'] = id.toString();
      Future<void> addFile(File f, String field) async {
        final ext = f.path.split('.').last.toLowerCase();
        request.files.add(await http.MultipartFile.fromPath(field, f.path, contentType: ext == 'pdf' ? MediaType('application','pdf') : MediaType('image', ext == 'jpg' ? 'jpeg' : ext)));
      }
      await addFile(_ifuFile!, 'ifu_file'); await addFile(_rccmFile!, 'rccm_file'); await addFile(_certFile!, 'certificate_file');
      if (_logoFile != null) await addFile(_logoFile!, 'logo');
      if (_imageBoutiqueFile != null) await addFile(_imageBoutiqueFile!, 'image_boutique');
      final response = await request.send();
      final body = await response.stream.bytesToString();
      if (response.statusCode == 201 || response.statusCode == 200) {
  _showSuccessDialog();
} else {
  // DEBUG TEMPORAIRE - à supprimer après correction
  print('=== ERREUR API ===');
  print('Status: ${response.statusCode}');
  print('Body: $body');
  print('==================');
  
  final data = jsonDecode(body);
  
  // Afficher les erreurs de validation détaillées
  String errorMsg = data['message'] ?? 'Erreur inconnue';
  if (data['errors'] != null) {
    final errors = data['errors'] as Map<String, dynamic>;
    final details = errors.entries
        .map((e) => '• ${e.key}: ${(e.value as List).join(', ')}')
        .join('\n');
    errorMsg = '$errorMsg\n\n$details';
  }
  
  _showError(errorMsg);
}
    } catch (_) { _showError('Erreur de connexion. Vérifiez votre réseau.'); }
    finally { setState(() => _isSubmitting = false); }
  }

  void _showSuccessDialog() => showDialog(context: context, barrierDismissible: false, builder: (_) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.check_circle, color: Colors.green, size: 50)),
      const SizedBox(height: 20),
      const Text('Demande envoyée !', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text('Votre entreprise a été soumise pour validation. Vous serez notifié dès qu\'elle sera approuvée.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5)),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); },
        style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: const Text('Retour à l\'accueil'))),
    ])),
  ));

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
    backgroundColor: Colors.red[700], behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.all(12),
  ));

  @override
  Widget build(BuildContext context) {
    final steps = ['Informations', 'Documents', 'Dirigeant', 'Localisation'];
    final icons = [Icons.business, Icons.folder_open, Icons.person, Icons.location_on];
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(children: [
        _buildHeader(steps, icons),
        Expanded(child: PageView(controller: _pageController, physics: const NeverScrollableScrollPhysics(), children: [_buildStep1(), _buildStep2(), _buildStep3(), _buildStep4()])),
        _buildNavButtons(),
      ]),
    );
  }

  Widget _buildHeader(List<String> steps, List<IconData> icons) {
    return Container(
      decoration: const BoxDecoration(color: AppConstants.primaryRed, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28))),
      child: SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), child: Column(children: [
        Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.arrow_back, color: Colors.white, size: 20))),
          const SizedBox(width: 12),
          const Expanded(child: Text('Créer une entreprise', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: Text('Étape ${_currentStep + 1}/4', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 20),
        Row(children: List.generate(4, (i) {
          final isDone = i < _currentStep, isCurrent = i == _currentStep;
          return Expanded(child: Padding(padding: EdgeInsets.only(right: i < 3 ? 8 : 0), child: Column(children: [
            Row(children: [
              AnimatedContainer(duration: const Duration(milliseconds: 300), width: isCurrent ? 36 : 28, height: isCurrent ? 36 : 28,
                decoration: BoxDecoration(color: isDone || isCurrent ? Colors.white : Colors.white.withOpacity(0.3), shape: BoxShape.circle, boxShadow: isCurrent ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))] : null),
                child: Icon(isDone ? Icons.check : icons[i], size: isCurrent ? 18 : 14, color: isDone || isCurrent ? AppConstants.primaryRed : Colors.white)),
              if (i < 3) Expanded(child: Container(height: 2, color: i < _currentStep ? Colors.white : Colors.white.withOpacity(0.3))),
            ]),
            const SizedBox(height: 6),
            Text(steps[i], style: TextStyle(color: isCurrent ? Colors.white : Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center),
          ])));
        })),
      ]))),
    );
  }

  Widget _buildStep1() => SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _stepTitle(icon: Icons.business, title: 'Informations générales', subtitle: 'Nom de votre entreprise et domaines d\'activité'),
    const SizedBox(height: 24),
    _fieldLabel('Nom de l\'entreprise', required: true),
    _textField(controller: _nameCtrl, hint: 'Ex: Garage Auto Excellence', icon: Icons.business_center),
    const SizedBox(height: 24),
    _fieldLabel('Domaines d\'activité', required: true),
    Text('Sélectionnez au moins un domaine', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    const SizedBox(height: 10),
    _isLoadingDomaines
      ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed))
      : Wrap(spacing: 8, runSpacing: 8, children: _domaines.map((d) {
          final selected = _selectedDomaineIds.contains(d.id);
          return GestureDetector(onTap: () => setState(() { selected ? _selectedDomaineIds.remove(d.id) : _selectedDomaineIds.add(d.id); }),
            child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: selected ? AppConstants.primaryRed : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? AppConstants.primaryRed : Colors.grey[300]!), boxShadow: selected ? [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : null),
              child: Row(mainAxisSize: MainAxisSize.min, children: [if (selected) ...[const Icon(Icons.check, size: 14, color: Colors.white), const SizedBox(width: 4)], Text(d.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? Colors.white : Colors.black87))])));
        }).toList()),
    const SizedBox(height: 20),
  ]));

  Widget _buildStep2() => SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _stepTitle(icon: Icons.folder_open, title: 'Documents légaux', subtitle: 'Fournissez vos justificatifs officiels (PDF ou image)'),
    const SizedBox(height: 24),
    _docSection(label: 'Numéro IFU', controller: _ifuNumCtrl, hint: 'Ex: 1234567890123', field: 'ifu', fileName: _ifuFileName, icon: Icons.badge),
    const SizedBox(height: 16),
    _docSection(label: 'Numéro RCCM', controller: _rccmNumCtrl, hint: 'Ex: RB/COT/12/B/345', field: 'rccm', fileName: _rccmFileName, icon: Icons.article),
    const SizedBox(height: 16),
    _docSection(label: 'Numéro de certificat', controller: _certNumCtrl, hint: 'Ex: CERT-2024-12345', field: 'cert', fileName: _certFileName, icon: Icons.workspace_premium),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue[200]!)),
      child: Row(children: [Icon(Icons.info_outline, color: Colors.blue[700], size: 18), const SizedBox(width: 10), Expanded(child: Text('Formats acceptés : PDF, JPG, PNG — Max 5 Mo', style: TextStyle(fontSize: 12, color: Colors.blue[700])))])),
    const SizedBox(height: 20),
  ]));

  Widget _docSection({required String label, required TextEditingController controller, required String hint, required String field, required String? fileName, required IconData icon}) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: AppConstants.primaryRed, size: 18)), const SizedBox(width: 10), Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), const Text(' *', style: TextStyle(color: Colors.red, fontSize: 14))]),
        const SizedBox(height: 12),
        TextFormField(controller: controller, style: const TextStyle(fontSize: 14), decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13), filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[200]!)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[200]!)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppConstants.primaryRed)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
        const SizedBox(height: 10),
        GestureDetector(onTap: () => _pickDocument(field), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: fileName != null ? Colors.green : Colors.grey[300]!, width: 1.5), borderRadius: BorderRadius.circular(10), color: fileName != null ? Colors.green.withOpacity(0.05) : Colors.grey[50]),
          child: Row(children: [Icon(fileName != null ? Icons.check_circle : Icons.upload_file, size: 18, color: fileName != null ? Colors.green : Colors.grey[500]), const SizedBox(width: 8), Expanded(child: Text(fileName ?? 'Joindre le fichier (PDF/Image)', style: TextStyle(fontSize: 12, color: fileName != null ? Colors.green[700] : Colors.grey[500], overflow: TextOverflow.ellipsis))), if (fileName == null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppConstants.primaryRed, borderRadius: BorderRadius.circular(6)), child: const Text('Parcourir', style: TextStyle(color: Colors.white, fontSize: 11)))]))),
      ]));
  }

  Widget _buildStep3() => SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _stepTitle(icon: Icons.person, title: 'Dirigeant & Contacts', subtitle: 'Informations sur le responsable et contacts'),
    const SizedBox(height: 24),
    _fieldLabel('Nom complet du PDG', required: true), _textField(controller: _pdgNameCtrl, hint: 'Ex: Jean Dupont', icon: Icons.person_outline),
    const SizedBox(height: 16),
    _fieldLabel('Profession du PDG', required: true), _textField(controller: _pdgProfCtrl, hint: 'Ex: Ingénieur mécanicien', icon: Icons.work_outline),
    const SizedBox(height: 16),
    _fieldLabel('Votre rôle', required: true),
    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Wrap(children: _roles.map((r) { final selected = _selectedRole == r; return GestureDetector(onTap: () => setState(() { _selectedRole = r; _showCustomRole = r == 'Autre'; if (r != 'Autre') _customRoleCtrl.clear(); }), child: Container(margin: const EdgeInsets.all(4), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: selected ? AppConstants.primaryRed : Colors.grey[100], borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? AppConstants.primaryRed : Colors.grey[300]!)), child: Text(r, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? Colors.white : Colors.black87)))); }).toList())),
    if (_showCustomRole) ...[const SizedBox(height: 10), _textField(controller: _customRoleCtrl, hint: 'Précisez votre rôle...', icon: Icons.edit)],
    const SizedBox(height: 20),
    Row(children: [Expanded(child: Divider(color: Colors.grey[300])), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('CONTACTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1.2))), Expanded(child: Divider(color: Colors.grey[300]))]),
    const SizedBox(height: 16),
    _fieldLabel('Téléphone WhatsApp', required: true), Text('Numéro pour recevoir les messages clients', style: TextStyle(fontSize: 12, color: Colors.grey[500])), const SizedBox(height: 6),
    _textField(controller: _whatsappCtrl, hint: '+229 97 00 00 00', icon: Icons.chat, keyboardType: TextInputType.phone),
    const SizedBox(height: 16),
    _fieldLabel('Téléphone pour appels', required: true), Text('Numéro pour les appels directs', style: TextStyle(fontSize: 12, color: Colors.grey[500])), const SizedBox(height: 6),
    _textField(controller: _callPhoneCtrl, hint: '+229 97 00 00 00', icon: Icons.phone, keyboardType: TextInputType.phone),
    const SizedBox(height: 20),
  ]));

  Widget _buildStep4() => SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _stepTitle(icon: Icons.location_on, title: 'Localisation & Médias', subtitle: 'Positionnez votre entreprise sur la carte'),
    const SizedBox(height: 12),
    // Badge OSM
    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green[200]!)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.map, size: 14, color: Colors.green[700]), const SizedBox(width: 6), Text('OpenStreetMap — Gratuit & Open Source', style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600))])),
    const SizedBox(height: 16),
    _fieldLabel('Rechercher une adresse'),
    Row(children: [
      Expanded(child: TextFormField(controller: _locationSearchCtrl, style: const TextStyle(fontSize: 14), textInputAction: TextInputAction.search, onFieldSubmitted: _searchAddressOSM,
        decoration: InputDecoration(hintText: 'Ex: Akpakpa, Cotonou...', hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13), prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
          suffixIcon: _isSearchingAddress ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryRed))) : null,
          filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppConstants.primaryRed)), contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16)))),
      const SizedBox(width: 8),
      GestureDetector(onTap: _getCurrentLocation, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppConstants.primaryRed, borderRadius: BorderRadius.circular(12)),
        child: _isLocating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.my_location, color: Colors.white, size: 20))),
    ]),
    const SizedBox(height: 14),
    // Carte OSM
    ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(height: 240, decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(16)),
      child: FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: _mapCenter, initialZoom: 12.0, onTap: (_, point) => _updatePosition(point.latitude, point.longitude)), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.careasy.app'),
        // Google Maps (commenté)
        // GoogleMap(onMapCreated: (c) => _googleMapController = c, initialCameraPosition: CameraPosition(target: _defaultPosition, zoom: 12), markers: _googleMarkers, onTap: (pos) => _updatePosition(pos.latitude, pos.longitude)),
        if (_markerPosition != null) MarkerLayer(markers: [Marker(point: _markerPosition!, width: 50, height: 50, child: Column(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]), child: const Icon(Icons.business, color: Colors.white, size: 16)),
          CustomPaint(size: const Size(10, 6), painter: _TrianglePainter(AppConstants.primaryRed)),
        ]))]),
      ]))),
    Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4), child: Row(children: [Icon(Icons.touch_app, size: 12, color: Colors.grey[400]), const SizedBox(width: 4), Text('Appuyez sur la carte pour placer votre marqueur  •  © OpenStreetMap contributors', style: TextStyle(fontSize: 10, color: Colors.grey[400]))])),
    if (_formattedAddress.isNotEmpty) ...[
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green[200]!)),
        child: Row(children: [Icon(Icons.location_pin, color: Colors.green[700], size: 16), const SizedBox(width: 8), Expanded(child: Text(_formattedAddress, style: TextStyle(fontSize: 12, color: Colors.green[700])))])),
    ],
    const SizedBox(height: 16),
    _fieldLabel('Siège (adresse courte)'), _textField(controller: _siegeCtrl, hint: 'Ex: Cotonou, Akpakpa', icon: Icons.apartment),
    const SizedBox(height: 20),
    Row(children: [Expanded(child: Divider(color: Colors.grey[300])), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('MÉDIAS (OPTIONNEL)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1.2))), Expanded(child: Divider(color: Colors.grey[300]))]),
    const SizedBox(height: 14),
    Row(children: [Expanded(child: _imagePickerCard(label: 'Logo', previewPath: _logoPreviewPath, icon: Icons.business, onTap: () => _pickImage('logo'))), const SizedBox(width: 12), Expanded(child: _imagePickerCard(label: 'Image boutique', previewPath: _boutiquePreviewPath, icon: Icons.storefront, onTap: () => _pickImage('boutique')))]),
    const SizedBox(height: 24),
    _buildRecap(),
    const SizedBox(height: 16),
    _buildCGU(),
    const SizedBox(height: 20),
  ]));

  Widget _imagePickerCard({required String label, required String? previewPath, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap, child: Container(height: 110, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: previewPath != null ? AppConstants.primaryRed : Colors.grey[300]!, width: 1.5)),
      child: previewPath != null ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [Image.file(File(previewPath), fit: BoxFit.cover), Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(vertical: 6), color: Colors.black.withOpacity(0.5), child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))))]))
      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 28, color: Colors.grey[400]), const SizedBox(height: 6), Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey[500])), const SizedBox(height: 4), Text('Appuyer pour ajouter', style: TextStyle(fontSize: 10, color: Colors.grey[400]))])));
  }

  Widget _buildRecap() {
    final domNames = _domaines.where((d) => _selectedDomaineIds.contains(d.id)).map((d) => d.name).join(', ');
    final role = _selectedRole == 'Autre' ? _customRoleCtrl.text : _selectedRole ?? '-';
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.checklist, color: AppConstants.primaryRed, size: 20), const SizedBox(width: 8), const Text('Récapitulatif', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 12), const Divider(height: 1), const SizedBox(height: 12),
        _recapRow('Entreprise', _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '-'),
        _recapRow('Domaines', domNames.isNotEmpty ? domNames : '-'),
        _recapRow('PDG', _pdgNameCtrl.text.isNotEmpty ? _pdgNameCtrl.text : '-'),
        _recapRow('Rôle', role), _recapRow('WhatsApp', _whatsappCtrl.text.isNotEmpty ? _whatsappCtrl.text : '-'),
        _recapRow('Téléphone', _callPhoneCtrl.text.isNotEmpty ? _callPhoneCtrl.text : '-'),
        _recapRow('Localisation', _latitude != null ? '${_latitude!.toStringAsFixed(4)}°, ${_longitude!.toStringAsFixed(4)}°' : '⚠ Non définie', valueColor: _latitude == null ? Colors.orange : Colors.green[700]),
        _recapRow('IFU', _ifuFile != null ? '✓ Fourni' : '⚠ Manquant', valueColor: _ifuFile == null ? Colors.red : Colors.green),
        _recapRow('RCCM', _rccmFile != null ? '✓ Fourni' : '⚠ Manquant', valueColor: _rccmFile == null ? Colors.red : Colors.green),
        _recapRow('Certificat', _certFile != null ? '✓ Fourni' : '⚠ Manquant', valueColor: _certFile == null ? Colors.red : Colors.green),
      ]));
  }

  Widget _recapRow(String label, String value, {Color? valueColor}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500))), Expanded(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor ?? Colors.black87)))]));

  Widget _buildCGU() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.04), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppConstants.primaryRed.withOpacity(0.2))),
    child: Column(children: [
      Row(children: [Icon(Icons.shield_outlined, color: AppConstants.primaryRed, size: 18), const SizedBox(width: 8), const Text('Validation finale', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
      const SizedBox(height: 12),
      _checkboxRow(value: _attestationAccepted, label: 'J\'atteste que toutes les informations fournies sont exactes et authentiques.', onChanged: (v) => setState(() => _attestationAccepted = v ?? false)),
      const SizedBox(height: 8),
      _checkboxRow(value: _privacyAccepted, label: 'J\'accepte les conditions générales d\'utilisation de CarEasy.', onChanged: (v) => setState(() => _privacyAccepted = v ?? false)),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber[300]!)),
        child: Row(children: [Icon(Icons.warning_amber, color: Colors.amber[700], size: 16), const SizedBox(width: 8), Expanded(child: Text('Votre demande sera examinée par un administrateur avant publication.', style: TextStyle(fontSize: 11, color: Colors.amber[800])))])),
    ]));

  Widget _checkboxRow({required bool value, required String label, required ValueChanged<bool?> onChanged}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 24, height: 24, child: Checkbox(value: value, onChanged: onChanged, activeColor: AppConstants.primaryRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)))), const SizedBox(width: 8), Expanded(child: Text(label, style: const TextStyle(fontSize: 12, height: 1.4)))]);

  Widget _buildNavButtons() {
    final isLastStep = _currentStep == 3;
    return Container(padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12), decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, -4))]),
      child: Row(children: [
        if (_currentStep > 0) ...[Expanded(flex: 2, child: OutlinedButton.icon(onPressed: _previous, icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Précédent'), style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))), const SizedBox(width: 12)],
        Expanded(flex: 3, child: ElevatedButton(onPressed: _isSubmitting ? null : (isLastStep ? _submit : _next),
          style: ElevatedButton.styleFrom(backgroundColor: isLastStep ? Colors.green[600] : AppConstants.primaryRed, foregroundColor: Colors.white, disabledBackgroundColor: Colors.grey[300], elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(isLastStep ? Icons.check_circle_outline : Icons.arrow_forward, size: 18), const SizedBox(width: 8), Text(isLastStep ? 'Soumettre la demande' : 'Suivant', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))]))),
      ]));
  }

  Widget _stepTitle({required IconData icon, required String title, required String subtitle}) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))]),
    child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppConstants.primaryRed, size: 22)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.3))]))]));

  Widget _fieldLabel(String label, {bool required = false}) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)), if (required) const Text(' *', style: TextStyle(color: Colors.red, fontSize: 14))]));

  Widget _textField({required TextEditingController controller, required String hint, required IconData icon, TextInputType keyboardType = TextInputType.text}) => TextFormField(controller: controller, keyboardType: keyboardType, style: const TextStyle(fontSize: 14), decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13), prefixIcon: Icon(icon, color: Colors.grey[500], size: 18), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppConstants.primaryRed, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)));
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()..moveTo(0, 0)..lineTo(size.width, 0)..lineTo(size.width / 2, size.height)..close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}