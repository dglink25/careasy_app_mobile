import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // ⚠️ Remplace par ton vrai dépôt GitHub
  static const String _versionUrl =
      'https://github.com/TON_USER/TON_REPO/releases/latest/download/version.json';

  static const String _downloadUrl =
      'https://github.com/TON_USER/TON_REPO/releases/latest/download/CarEasy.apk';

  /// Vérifie si une mise à jour est disponible et affiche une dialog
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final remote = jsonDecode(response.body) as Map<String, dynamic>;
      final remoteVersion = remote['version'] as String? ?? '0.0.0';

      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version;

      if (_isNewer(remoteVersion, localVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, remoteVersion, remote['release_notes'] as String? ?? '');
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Erreur: $e');
    }
  }

  static bool _isNewer(String remote, String local) {
    final r = _parse(remote);
    final l = _parse(local);
    for (int i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String v) {
    final parts = v.split('+').first.split('.');
    return List.generate(3, (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
  }

  static void _showUpdateDialog(
      BuildContext context, String newVersion, String notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Mise à jour disponible'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version $newVersion est disponible.'),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(notes, style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.parse(_downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Mettre à jour'),
          ),
        ],
      ),
    );
  }
}