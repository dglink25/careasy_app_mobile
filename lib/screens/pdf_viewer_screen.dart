// lib/screens/pdf_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../utils/constants.dart';

class PdfViewerScreen extends StatelessWidget {
  final String title;
  
  const PdfViewerScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppConstants.primaryRed,
      ),
      body: PDFView(
        filePath: 'assets/Manuel_Utilisateur_CarEasy.pdf',
        enableSwipe: true,
        swipeHorizontal: true,
        autoSpacing: false,
        pageFling: true,
      ),
    );
  }
}