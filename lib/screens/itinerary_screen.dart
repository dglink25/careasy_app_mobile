import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/constants.dart';

const _kOrsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjU5YWUyNTQ2MjU4MTQ0ZDBiMzk0MGJkMzZlZDc5NTQwIiwiaCI6Im11cm11cjY0In0='; 

class ItineraryScreen extends StatefulWidget {
  final LatLng  destination;
  final String  destinationName;
  final LatLng? userPosition;

  const ItineraryScreen({
    super.key,
    required this.destination,
    required this.destinationName,
    this.userPosition,
  });

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> with TickerProviderStateMixin {
  final _mapCtrl = MapController();

  LatLng?  _origin;
  List<LatLng> _route    = [];
  bool _isLoading        = true;
  bool _isLocating       = false;
  String? _errorMsg;
  String _travelMode     = 'driving-car'; // driving-car | foot-walking | cycling-regular
  double? _distanceKm;
  int?    _durationMin;

  // Animation bouton mode
  late AnimationController _modeCtrl;

  // Suivi temps réel
  StreamSubscription<Position>? _positionSub;
  bool _isTracking = false;

  // Panel infos
  late AnimationController _panelCtrl;
  late Animation<double>   _panelAnim;
  bool _panelExpanded = false;

  // Étapes
  List<Map<String, dynamic>> _steps = [];

  @override
  void initState() {
    super.initState();
    _modeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _panelCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _panelAnim = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOutCubic);

    _origin = widget.userPosition;
    if (_origin != null) {
      _buildRoute();
    } else {
      _getLocation();
    }
  }

  @override
  void dispose() {
    _modeCtrl.dispose();
    _panelCtrl.dispose();
    _positionSub?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  // ── Géolocalisation ────────────────────────────────────────────────────────
  Future<void> _getLocation() async {
    setState(() => _isLocating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        setState(() { _errorMsg = "Permission de localisation refusée"; _isLoading = false; });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      setState(() => _origin = LatLng(pos.latitude, pos.longitude));
      await _buildRoute();
    } catch (e) {
      setState(() { _errorMsg = "Impossible d'obtenir votre position"; _isLoading = false; });
    } finally {
      setState(() => _isLocating = false);
    }
  }

  // ── Construction de la route ───────────────────────────────────────────────
  Future<void> _buildRoute() async {
    if (_origin == null) return;
    setState(() { _isLoading = true; _errorMsg = null; _route = []; _steps = []; });

    try {
      if (_kOrsApiKey.isNotEmpty) {
        await _fetchOrsRoute();
      } else {
        // Fallback : route simplifiée (ligne droite avec courbe)
        await _buildStraightLineRoute();
      }
      _fitBounds();
    } catch (e) {
      debugPrint('Route error: $e');
      await _buildStraightLineRoute();
      _fitBounds();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchOrsRoute() async {
    final url = 'https://api.openrouteservice.org/v2/directions/$_travelMode/geojson';
    final body = jsonEncode({
      'coordinates': [
        [_origin!.longitude, _origin!.latitude],
        [widget.destination.longitude, widget.destination.latitude],
      ],
      'instructions': true,
      'language': 'fr',
    });

    final resp = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': _kOrsApiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json, application/geo+json',
      },
      body: body,
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) throw Exception('ORS ${resp.statusCode}');
    final data = jsonDecode(resp.body);

    final coords = data['features'][0]['geometry']['coordinates'] as List;
    final points = coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();

    final summary = data['features'][0]['properties']['summary'];
    final distance = (summary['distance'] as num).toDouble() / 1000;
    final duration = ((summary['duration'] as num).toDouble() / 60).round();

    final segs = data['features'][0]['properties']['segments'] as List;
    final steps = <Map<String, dynamic>>[];
    for (final seg in segs) {
      for (final step in (seg['steps'] as List)) {
        steps.add({
          'instruction': step['instruction']?.toString() ?? '',
          'distance': ((step['distance'] as num).toDouble() / 1000).toStringAsFixed(1),
          'type': step['type'] ?? 0,
        });
      }
    }

    if (mounted) setState(() {
      _route = points;
      _distanceKm = distance;
      _durationMin = duration;
      _steps = steps;
    });
  }

  Future<void> _buildStraightLineRoute() async {
    // Route simplifiée avec quelques points intermédiaires pour simuler une courbe
    if (_origin == null) return;
    final o = _origin!;
    final d = widget.destination;
    final dist = const Distance().as(LengthUnit.Kilometer, o, d);
    final dur   = (dist / 40 * 60).round(); // ~40 km/h en ville

    // Interpolation avec légère courbe
    final points = <LatLng>[o];
    const steps = 20;
    for (int i = 1; i < steps; i++) {
      final t = i / steps;
      final lat = o.latitude  + (d.latitude  - o.latitude)  * t;
      final lng = o.longitude + (d.longitude - o.longitude) * t;
      // Légère ondulation
      final offset = math.sin(t * math.pi) * 0.001;
      points.add(LatLng(lat + offset, lng));
    }
    points.add(d);

    if (mounted) setState(() {
      _route = points;
      _distanceKm = dist;
      _durationMin = dur;
      _steps = [
        {'instruction': 'Suivre la direction vers ${widget.destinationName}', 'distance': dist.toStringAsFixed(1), 'type': 0},
        {'instruction': 'Arriver à ${widget.destinationName}', 'distance': '0', 'type': 10},
      ];
    });
  }

  void _fitBounds() {
    if (_route.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lats = _route.map((p) => p.latitude);
      final lngs = _route.map((p) => p.longitude);
      final sw = LatLng(lats.reduce(math.min), lngs.reduce(math.min));
      final ne = LatLng(lats.reduce(math.max), lngs.reduce(math.max));
      _mapCtrl.fitCamera(
        CameraFit.bounds(bounds: LatLngBounds(sw, ne), padding: const EdgeInsets.all(60)),
      );
    });
  }

  // ── Suivi temps réel ───────────────────────────────────────────────────────
  void _toggleTracking() {
    if (_isTracking) {
      _positionSub?.cancel();
      setState(() => _isTracking = false);
    } else {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((pos) {
        if (!mounted) return;
        setState(() => _origin = LatLng(pos.latitude, pos.longitude));
        _mapCtrl.move(_origin!, _mapCtrl.camera.zoom);
      });
      setState(() => _isTracking = true);
    }
  }

  // ── Ouvrir Google Maps externe ─────────────────────────────────────────────
  Future<void> _openInGoogleMaps() async {
    final dest = widget.destination;
    final url  = 'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}&travelmode=driving';
    try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); }
    catch (_) {}
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [

        // ── Carte principale ─────────────────────────────────────────────────
        _buildMap(),

        // ── AppBar custom ────────────────────────────────────────────────────
        _buildAppBar(),

        // ── Sélecteur de mode de transport ────────────────────────────────
        _buildModeSelector(),

        // ── Bouton tracking + Google Maps ──────────────────────────────────
        _buildRightButtons(),

        // ── Panel infos en bas ─────────────────────────────────────────────
        _buildBottomPanel(),

        // ── Loading overlay ────────────────────────────────────────────────
        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: AppConstants.primaryRed),
                  const SizedBox(height: 12),
                  Text(_isLocating ? 'Localisation en cours…' : 'Calcul de l\'itinéraire…',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ])),
          ),

        // ── Erreur ────────────────────────────────────────────────────────
        if (_errorMsg != null)
          Center(child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: Colors.orange, size: 40),
              const SizedBox(height: 12),
              Text(_errorMsg!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _getLocation,
                style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryRed),
                child: const Text('Réessayer', style: TextStyle(color: Colors.white)),
              ),
            ]),
          )),
      ]),
    );
  }

  Widget _buildMap() {
    final center = _origin ?? widget.destination;
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13.0,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.careasy.app',
          maxZoom: 19,
        ),

        // Route
        if (_route.isNotEmpty) ...[
          // Ombre
          PolylineLayer(polylines: [
            Polyline(points: _route, color: Colors.black.withOpacity(0.12), strokeWidth: 10),
          ]),
          // Couleur principale
          PolylineLayer(polylines: [
            Polyline(
              points: _route,
              color: AppConstants.primaryRed,
              strokeWidth: 5,
              borderColor: Colors.white,
              borderStrokeWidth: 2,
            ),
          ]),
        ],

        // Marqueurs
        MarkerLayer(markers: [
          // Destination
          Marker(
            point: widget.destination,
            width: 60, height: 70,
            child: _DestinationMarker(name: widget.destinationName),
          ),
          // Origine (utilisateur)
          if (_origin != null)
            Marker(
              point: _origin!,
              width: 50, height: 50,
              child: _OriginMarker(isTracking: _isTracking),
            ),
        ]),
      ],
    );
  }

  Widget _buildAppBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.75), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            child: Row(children: [
              _MapButton(
                onTap: () => Navigator.pop(context),
                icon: Icons.arrow_back_ios_new,
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Itinéraire', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                Text(
                  widget.destinationName,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ])),
              _MapButton(onTap: _openInGoogleMaps, icon: Icons.open_in_new, tooltip: 'Google Maps'),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 68,
      left: 14,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _ModeBtn(icon: Icons.directions_car, label: 'Voiture', mode: 'driving-car',   current: _travelMode, onTap: _changeMode),
          _ModeBtn(icon: Icons.directions_walk, label: 'Marche',  mode: 'foot-walking',  current: _travelMode, onTap: _changeMode),
          _ModeBtn(icon: Icons.pedal_bike,      label: 'Vélo',    mode: 'cycling-regular', current: _travelMode, onTap: _changeMode),
        ]),
      ),
    );
  }

  void _changeMode(String mode) {
    if (mode == _travelMode) return;
    HapticFeedback.selectionClick();
    setState(() => _travelMode = mode);
    _buildRoute();
  }

  Widget _buildRightButtons() {
    return Positioned(
      right: 14,
      bottom: _panelExpanded ? 340 : 210,
      child: Column(children: [
        // Tracking
        _MapButton(
          onTap: _toggleTracking,
          icon: _isTracking ? Icons.gps_fixed : Icons.gps_not_fixed,
          color: _isTracking ? AppConstants.primaryRed : Colors.white,
          iconColor: _isTracking ? Colors.white : Colors.black87,
        ),
        const SizedBox(height: 10),
        // Recentrer
        _MapButton(
          onTap: _fitBounds,
          icon: Icons.fit_screen,
        ),
      ]),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: AnimatedBuilder(
        animation: _panelAnim,
        builder: (_, __) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Poignée
              GestureDetector(
                onTap: () {
                  setState(() => _panelExpanded = !_panelExpanded);
                  _panelExpanded ? _panelCtrl.forward() : _panelCtrl.reverse();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  )),
                ),
              ),

              // Résumé
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  // Distance
                  Expanded(child: _InfoChip(
                    icon: Icons.straighten,
                    value: _distanceKm != null ? '${_distanceKm!.toStringAsFixed(1)} km' : '---',
                    label: 'Distance',
                    color: Colors.blue,
                  )),
                  const SizedBox(width: 10),
                  // Durée
                  Expanded(child: _InfoChip(
                    icon: Icons.access_time_rounded,
                    value: _durationMin != null
                        ? _durationMin! >= 60
                            ? '${_durationMin! ~/ 60}h ${_durationMin! % 60}min'
                            : '$_durationMin min'
                        : '---',
                    label: 'Durée estimée',
                    color: AppConstants.primaryRed,
                  )),
                  const SizedBox(width: 10),
                  // Mode
                  _InfoChip(
                    icon: _travelMode == 'driving-car' ? Icons.directions_car
                        : _travelMode == 'foot-walking' ? Icons.directions_walk : Icons.pedal_bike,
                    value: _travelMode == 'driving-car' ? 'Voiture'
                        : _travelMode == 'foot-walking' ? 'Marche' : 'Vélo',
                    label: 'Mode',
                    color: Colors.green,
                  ),
                ]),
              ),

              // Étapes (panel étendu)
              ClipRect(
                child: SizeTransition(
                  sizeFactor: _panelAnim,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: _steps.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            itemCount: _steps.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final step = _steps[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(children: [
                                  Container(
                                    width: 32, height: 32,
                                    decoration: BoxDecoration(
                                      color: AppConstants.primaryRed.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(_stepIcon(step['type'] as int? ?? 0), size: 16, color: AppConstants.primaryRed),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(step['instruction']?.toString() ?? '', style: const TextStyle(fontSize: 12))),
                                  if (step['distance'] != '0') Text('${step['distance']} km',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                ]),
                              );
                            },
                          ),
                  ),
                ),
              ),

              // Bouton démarrer navigation
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
                child: ElevatedButton.icon(
                  onPressed: _openInGoogleMaps,
                  icon: const Icon(Icons.navigation, size: 20),
                  label: const Text('Démarrer la navigation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryRed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  IconData _stepIcon(int type) {
    switch (type) {
      case 0:  return Icons.straight;
      case 1:  return Icons.turn_right;
      case 2:  return Icons.turn_left;
      case 3:  return Icons.turn_slight_right;
      case 4:  return Icons.turn_slight_left;
      case 5:  return Icons.turn_sharp_right;
      case 6:  return Icons.turn_sharp_left;
      case 10: return Icons.flag;
      case 11: return Icons.trip_origin;
      default: return Icons.arrow_forward;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Marqueur destination
// ═════════════════════════════════════════════════════════════════════════════
class _DestinationMarker extends StatelessWidget {
  final String name;
  const _DestinationMarker({required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppConstants.primaryRed,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Text(
          name.length > 12 ? '${name.substring(0, 12)}…' : name,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ),
      CustomPaint(size: const Size(12, 8), painter: _TrianglePainter()),
      Container(
        width: 16, height: 16,
        decoration: BoxDecoration(
          color: AppConstants.primaryRed,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.5), blurRadius: 8)],
        ),
      ),
    ]);
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()..color = AppConstants.primaryRed;
    final path  = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    c.drawPath(path, paint);
  }
  @override bool shouldRepaint(_) => false;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Marqueur origine
// ═════════════════════════════════════════════════════════════════════════════
class _OriginMarker extends StatelessWidget {
  final bool isTracking;
  const _OriginMarker({required this.isTracking});

  @override
  Widget build(BuildContext context) {
    return Center(child: Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(isTracking ? 0.6 : 0.3), blurRadius: 10)],
      ),
      child: isTracking ? const Icon(Icons.navigation, color: Colors.white, size: 10) : null,
    ));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Bouton mode transport
// ═════════════════════════════════════════════════════════════════════════════
class _ModeBtn extends StatelessWidget {
  final IconData icon;
  final String label, mode, current;
  final ValueChanged<String> onTap;
  const _ModeBtn({required this.icon, required this.label, required this.mode, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sel = mode == current;
    return GestureDetector(
      onTap: () => onTap(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppConstants.primaryRed : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: sel ? Colors.white : Colors.grey[600]),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.grey[600])),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Chip info (distance / durée)
// ═════════════════════════════════════════════════════════════════════════════
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  const _InfoChip({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Bouton sur la carte
// ═════════════════════════════════════════════════════════════════════════════
class _MapButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final Color? color;
  final Color? iconColor;
  final String? tooltip;
  const _MapButton({required this.onTap, required this.icon, this.color, this.iconColor, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Icon(icon, size: 20, color: iconColor ?? (color == Colors.white ? Colors.black87 : Colors.white)),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}