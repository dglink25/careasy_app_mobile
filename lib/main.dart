import 'package:flutter/material.dart';
import 'package:careasy_app/screens/welcome_screen.dart';
import 'package:careasy_app/theme/app_theme.dart';

void main() {
  runApp(const CarEasyApp());
}

class CarEasyApp extends StatelessWidget {
  const CarEasyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CarEasy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const WelcomeScreen(),
    );
  }
}