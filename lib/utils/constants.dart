import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'CarEasy';


  static const String apiBaseUrl = 'http://10.244.255.115:8000/api';

  static const String pusherKey     = 'cab84ca4d5eac6def57e';
  static const String pusherCluster = 'eu';

  static const Color primaryRed    = Color(0xFFE63946);
  static const Color darkGrey      = Color(0xFF2C3E50);
  static const Color lightGrey     = Color(0xFFF1F5F9);

  static const String welcomeSubtitle = 'Votre partenaire mobilité premium';

  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color asphaltColor  = Color(0xFF2C3E50);
  static const Color roadMarking   = Color(0xFFF1C40F);

  static String get googleAuthUrl => '$apiBaseUrl/google';
  static const String appCallbackScheme = 'careasy';
  static const String appCallbackHost   = 'auth';
}