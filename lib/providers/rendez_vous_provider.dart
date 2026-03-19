// lib/providers/rendez_vous_provider.dart

import 'package:flutter/foundation.dart';
import '../models/rendez_vous_model.dart';
import '../services/rendez_vous_service.dart';

class RendezVousProvider extends ChangeNotifier {
  final _service = RendezVousService();

  // ── State ─────────────────────────────────────────────────────────────────
  List<RendezVousModel> _rendezVous = [];
  List<RendezVousModel> get rendezVous => _rendezVous;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  RendezVousModel? _selected;
  RendezVousModel? get selected => _selected;

  String _filter = 'all'; // all | pending | confirmed | cancelled | completed
  String get filter => _filter;

  // ── Computed ──────────────────────────────────────────────────────────────
  List<RendezVousModel> get filtered {
    if (_filter == 'all') return _rendezVous;
    return _rendezVous.where((r) => r.status == _filter).toList();
  }

  int get countPending   => _rendezVous.where((r) => r.isPending).length;
  int get countConfirmed => _rendezVous.where((r) => r.isConfirmed).length;
  int get countCancelled => _rendezVous.where((r) => r.isCancelled).length;
  int get countCompleted => _rendezVous.where((r) => r.isCompleted).length;

  // ── Actions ───────────────────────────────────────────────────────────────

  void setFilter(String f) {
    _filter = f;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> loadRendezVous() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _rendezVous = await _service.fetchMesRendezVous();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadRendezVousById(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _selected = await _service.fetchRendezVous(id);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createRendezVous({
    required String serviceId,
    required String date,
    required String startTime,
    required String endTime,
    String? clientNotes,
    String? phone,                 // ← AJOUT
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final rdv = await _service.createRendezVous(
        serviceId  : serviceId,
        date       : date,
        startTime  : startTime,
        endTime    : endTime,
        clientNotes: clientNotes,
        phone      : phone,        // ← AJOUT
      );
      _rendezVous.insert(0, rdv);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmRendezVous(String id) async {
    return _performAction(id, () => _service.confirmRendezVous(id));
  }

  Future<bool> cancelRendezVous(String id, {String? reason}) async {
    return _performAction(id, () => _service.cancelRendezVous(id, reason: reason));
  }

  Future<bool> completeRendezVous(String id) async {
    return _performAction(id, () => _service.completeRendezVous(id));
  }

  /// Met à jour l'item dans la liste + l'item sélectionné
  Future<bool> _performAction(
      String id, Future<RendezVousModel> Function() action) async {
    _error = null;
    notifyListeners();
    try {
      final updated = await action();
      final idx = _rendezVous.indexWhere((r) => r.id == id);
      if (idx != -1) _rendezVous[idx] = updated;
      if (_selected?.id == id) _selected = updated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Appelé par les notifications Pusher / FCM pour mettre à jour un RDV live
  void updateFromNotification(Map<String, dynamic> data) {
    final rdvId = data['rdv_id']?.toString();
    if (rdvId == null) return;
    // Recharger le RDV concerné depuis l'API
    _service.fetchRendezVous(rdvId).then((updated) {
      final idx = _rendezVous.indexWhere((r) => r.id == rdvId);
      if (idx != -1) {
        _rendezVous[idx] = updated;
      } else {
        _rendezVous.insert(0, updated);
      }
      if (_selected?.id == rdvId) _selected = updated;
      notifyListeners();
    }).catchError((_) {});
  }
}