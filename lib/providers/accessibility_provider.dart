import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccessibilityProvider extends ChangeNotifier {
  static const String _kScaleKey = 'text_scale_factor';

  // ── Valeurs disponibles (5 niveaux) ───────────────────────────────────────
  static const List<double> scales = [0.85, 0.95, 1.0, 1.15, 1.30, 1.45];
  static const List<String> scaleLabels = [ 'Très peu', 'Petit', 'Moyen', 'Normal', 'Grand', 'Très grand'];

  double _scaleFactor = 1.0;

  double get scaleFactor => _scaleFactor;

  /// Index courant dans [scales]
  int get currentIndex =>
      scales.indexWhere((s) => (s - _scaleFactor).abs() < 0.01).clamp(0, scales.length - 1);

  String get currentLabel => scaleLabels[currentIndex];

  bool get canDecrease => currentIndex > 0;
  bool get canIncrease => currentIndex < scales.length - 1;

  // ── Initialisation ─────────────────────────────────────────────────────────
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_kScaleKey);
      if (saved != null && scales.contains(saved)) {
        _scaleFactor = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ── Mutations ──────────────────────────────────────────────────────────────
  Future<void> setScale(double scale) async {
    if ((scale - _scaleFactor).abs() < 0.001) return;
    _scaleFactor = scale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kScaleKey, scale);
    } catch (_) {}
  }

  Future<void> increase() async {
    if (!canIncrease) return;
    await setScale(scales[currentIndex + 1]);
  }

  Future<void> decrease() async {
    if (!canDecrease) return;
    await setScale(scales[currentIndex - 1]);
  }

  Future<void> reset() async => setScale(1.0);
}