import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal() { _init(); }

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  // Expose un stream pour écouter les changements depuis n'importe quel widget
  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _controller.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> _init() async {
    // Vérification initiale
    final results = await Connectivity().checkConnectivity();
    _update(results);

    // Écoute des changements
    _subscription = Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);

    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(_isOnline);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.close();
    super.dispose();
  }
}