import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'CarEasy';
  
  // Couleurs
  static const Color primaryRed = Color(0xFFE53935);
  static const Color white = Colors.white;
  static const Color lightGrey = Color(0xFFF5F5F5);
  static const Color darkGrey = Color(0xFF757575);
  
  // URLs API (à modifier selon votre backend)
  static const String baseUrl = 'http://192.168.1.x:8000/api'; // Mettez votre IP locale
  static const String loginUrl = '$baseUrl/login';
  static const String registerUrl = '$baseUrl/register';
  
  // Messages
  static const String welcomeTitle = 'Bienvenue sur CarEasy';
  static const String welcomeSubtitle = 'Votre solution automobile intelligente';
}