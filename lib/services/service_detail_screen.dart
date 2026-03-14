// screens/service_detail_screen.dart
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class ServiceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> service;

  const ServiceDetailScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        title: Text(service['name'] ?? 'Détails du service'),
      ),
      body: Center(
        child: Text('Détails du service: ${service['name']}'),
      ),
    );
  }
}