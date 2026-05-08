import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/constants.dart';

/// Affiche un PDF stocké dans les assets Flutter.
/// Le fichier est copié en cache avant d'être affiché par flutter_pdfview
/// (qui n'accepte que les chemins de fichiers locaux).
class PdfViewerScreen extends StatefulWidget {
  /// Titre affiché dans l'AppBar
  final String title;

  /// Chemin dans les assets, ex: 'assets/Manuel_Utilisateur_CarEasy.pdf'
  /// Par défaut : guide utilisateur intégré
  final String assetPath;

  const PdfViewerScreen({
    super.key,
    this.title = 'Guide d\'utilisation',
    this.assetPath = 'assets/Manuel_Utilisateur_CarEasy.pdf',
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  // ── État ──────────────────────────────────────────────────────────────
  String?  _localPath;   // chemin cache du PDF
  bool     _isLoading = true;
  String?  _error;

  // Contrôle du PDF
  PDFViewController? _pdfController;
  int _currentPage = 0;
  int _totalPages  = 0;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  // ── Chargement ────────────────────────────────────────────────────────

  Future<void> _loadPdf() async {
    try {
      // Lire le fichier depuis les assets Flutter
      final ByteData data = await rootBundle.load(widget.assetPath);
      final Uint8List bytes = data.buffer.asUint8List();

      // Copier dans le répertoire temporaire (flutter_pdfview requiert un path)
      final Directory tempDir = await getTemporaryDirectory();
      final String fileName =
          widget.assetPath.split('/').last; // ex: Manuel_Utilisateur_CarEasy.pdf
      final File file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      setState(() {
        _localPath = file.path;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error     = 'Impossible de charger le document.\n($e)';
        _isLoading = false;
      });
      debugPrint('[PdfViewer] Erreur chargement: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Indicateur de pagination
          if (_totalPages > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
      // Navigation entre pages (bas d'écran)
      bottomNavigationBar: _totalPages > 1 ? _buildPageNav() : null,
    );
  }

  Widget _buildBody() {
    // ── Chargement ─────────────────────────────────────────────────────
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppConstants.primaryRed),
            const SizedBox(height: 20),
            Text(
              'Chargement du document...',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }

    // ── Erreur ─────────────────────────────────────────────────────────
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf_outlined,
                  size: 72, color: Colors.red[300]),
              const SizedBox(height: 20),
              const Text(
                'Document introuvable',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error     = null;
                  });
                  _loadPdf();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Viewer PDF ─────────────────────────────────────────────────────
    return PDFView(
      filePath:          _localPath!,
      enableSwipe:       true,
      swipeHorizontal:   false,
      autoSpacing:       true,
      pageFling:         true,
      fitPolicy:         FitPolicy.BOTH,
      preventLinkNavigation: false,
      onRender: (pages) {
        if (!mounted) return;
        setState(() => _totalPages = pages ?? 0);
      },
      onViewCreated: (controller) {
        _pdfController = controller;
      },
      onPageChanged: (page, total) {
        if (!mounted) return;
        setState(() {
          _currentPage = page ?? 0;
          _totalPages  = total ?? 0;
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _error = error.toString();
        });
        debugPrint('[PdfViewer] onError: $error');
      },
      onPageError: (page, error) {
        debugPrint('[PdfViewer] Page $page error: $error');
      },
    );
  }

  // ── Barre de navigation (page précédente / suivante) ──────────────────

  Widget _buildPageNav() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Précédent
            IconButton(
              onPressed: _currentPage > 0
                  ? () => _pdfController?.setPage(_currentPage - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
              color: AppConstants.primaryRed,
              disabledColor: Colors.grey[300],
              tooltip: 'Page précédente',
            ),

            // Pagination
            Text(
              'Page ${_currentPage + 1} sur $_totalPages',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500),
            ),

            // Suivant
            IconButton(
              onPressed: _currentPage < _totalPages - 1
                  ? () => _pdfController?.setPage(_currentPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
              color: AppConstants.primaryRed,
              disabledColor: Colors.grey[300],
              tooltip: 'Page suivante',
            ),
          ],
        ),
      ),
    );
  }
}