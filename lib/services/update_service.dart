import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String _repoBase = 'https://github.com/dglink25/careasy_app_mobile';

  static String get _versionUrl =>
      '$_repoBase/releases/latest/download/version.json';

  static String get _downloadUrl =>
      '$_repoBase/releases/latest/download/CarEasy.apk';

  // Ne vérifier qu'une fois par session applicative
  static bool _checked = false;

  /// Réinitialise le flag (utile si on veut forcer une nouvelle vérification)
  static void reset() {
    _checked = false;
  }

  static Future<void> checkForUpdate(BuildContext context) async {
    if (_checked) return;
    _checked = true;

    try {
      // Timeout court pour ne pas bloquer l'UI
      final response = await http
          .get(
            Uri.parse(_versionUrl),
            headers: {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[UpdateService] Statut HTTP: ${response.statusCode}');
        return;
      }

      final body = response.body.trim();
      if (body.isEmpty) return;

      Map<String, dynamic> remote;
      try {
        remote = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[UpdateService] JSON invalide: $e');
        return;
      }

      final remoteVersion = remote['version']?.toString() ?? '0.0.0';

      final info = await PackageInfo.fromPlatform();
      // Ignorer le build number, comparer seulement la version sémantique
      final localVersion = info.version.split('+').first.trim();

      debugPrint('[UpdateService] Local: $localVersion | Remote: $remoteVersion');

      if (_isNewer(remoteVersion, localVersion)) {
        if (context.mounted) {
          // Petit délai pour laisser l'UI se stabiliser
          await Future.delayed(const Duration(seconds: 2));
          if (context.mounted) {
            _showUpdateDialog(
              context,
              remoteVersion,
              remote['release_notes']?.toString() ?? 'Nouvelle version disponible',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Erreur (ignorée): $e');
      // Erreur silencieuse — pas critique pour l'UX
    }
  }

  /// Retourne true si remote > local
  static bool _isNewer(String remote, String local) {
    try {
      final r = _parseVersion(remote);
      final l = _parseVersion(local);
      for (int i = 0; i < 3; i++) {
        if (r[i] > l[i]) return true;
        if (r[i] < l[i]) return false;
      }
      return false; // Égaux
    } catch (e) {
      debugPrint('[UpdateService] Erreur comparaison versions: $e');
      return false;
    }
  }

  static List<int> _parseVersion(String v) {
    // Nettoyer : retirer le build number, les espaces, le 'v' prefix
    final clean = v
        .split('+').first
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .trim();
    final parts = clean.split('.');
    return List.generate(3, (i) =>
        i < parts.length ? (int.tryParse(parts[i].trim()) ?? 0) : 0);
  }

  static void _showUpdateDialog(
      BuildContext context, String newVersion, String notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.system_update, color: Color(0xFFE63946)),
            const SizedBox(width: 8),
            const Text('Mise à jour disponible'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('La version $newVersion est disponible.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(notes,
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
              const SizedBox(height: 8),
              const Text(
                'Téléchargez la nouvelle version pour bénéficier des dernières améliorations et corrections de bugs.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Plus tard',
                  style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE63946),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                final uri = Uri.parse(_downloadUrl);
                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  debugPrint('[UpdateService] Erreur lancement URL: $e');
                }
              },
              child: const Text('Télécharger'),
            ),
          ],
        ),
      ),
    );
  }
}