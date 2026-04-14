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

  static bool _checked = false; // Vérifier une seule fois par session

  static Future<void> checkForUpdate(BuildContext context) async {
    if (_checked) return;
    _checked = true;

    try {
      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final remote = jsonDecode(response.body) as Map<String, dynamic>;
      final remoteVersion = remote['version']?.toString() ?? '0.0.0';

      final info = await PackageInfo.fromPlatform();
      // Comparer seulement la partie version (avant le +)
      final localVersion = info.version.split('+').first;

      debugPrint('[Update] Local: $localVersion | Remote: $remoteVersion');

      if (_isNewer(remoteVersion, localVersion)) {
        if (context.mounted) {
          _showUpdateDialog(
            context,
            remoteVersion,
            remote['release_notes']?.toString() ?? 'Nouvelle version disponible',
          );
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Erreur (ignorée): $e');
      // Erreur silencieuse — pas critique
    }
  }

  static bool _isNewer(String remote, String local) {
    try {
      final r = _parse(remote);
      final l = _parse(local);
      for (int i = 0; i < 3; i++) {
        if (r[i] > l[i]) return true;
        if (r[i] < l[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static List<int> _parse(String v) {
    final parts = v.split('+').first.trim().split('.');
    return List.generate(3, (i) =>
        i < parts.length ? (int.tryParse(parts[i].trim()) ?? 0) : 0);
  }

  static void _showUpdateDialog(
      BuildContext context, String newVersion, String notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
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
            Text('La version $newVersion est disponible.'),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(notes, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
            const SizedBox(height: 8),
            const Text(
              'Téléchargez la nouvelle version pour bénéficier des dernières améliorations.',
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
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
  }
}