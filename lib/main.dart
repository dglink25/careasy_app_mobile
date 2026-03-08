import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';
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