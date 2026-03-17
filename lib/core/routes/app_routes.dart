import 'package:flutter/material.dart';
import '../../screens/welcome_screen.dart';
import '../../screens/login_screen.dart';
import '../../screens/register_screen.dart';
import '../../screens/google_auth_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/create_service_screen.dart';
import '../../screens/edit_service_screen.dart';

class AppRoutes {
  static const String welcome = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String googleAuth = '/google-auth';
  static const String home = '/home';
  
  static const String entreprises = '/entreprises';
  static const String entrepriseDetail = '/entreprise/:id';
  static const String createEntreprise = '/entreprise/create';
  static const String editEntreprise = '/entreprise/edit/:id';
  
  static const String services = '/services';
  static const String serviceDetail = '/service/:id';
  static const String createService = '/service/create';
  static const String editService = '/service/edit/:id';
  
  static const String conversations = '/conversations';
  static const String conversation = '/conversation/:id';
  
  static const String rendezVous = '/rendez-vous';
  static const String createRendezVous = '/rendez-vous/create';
  
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  static const String myEntreprises = '/profile/entreprises';
  static const String myServices = '/profile/services';
  static const String myAbonnements = '/profile/abonnements';
  
  static const String plans = '/plans';
  static const String paiement = '/paiement/:planId';
  
  static const String aiChat = '/ai-chat';
  static const String nearbyServices = '/nearby';

  static final Map<String, WidgetBuilder> routes = {
    welcome: (context) => const WelcomeScreen(),
    login: (context) => const LoginScreen(),
    register: (context) => const RegisterScreen(),
    googleAuth: (context) => const GoogleAuthScreen(),
    home: (context) => const HomeScreen(),
    
    '/create-service': (ctx) {
    final e = ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>;
    return CreateServiceScreen(entreprise: e);
  },
  '/edit-service': (ctx) {
    final args = ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>;
    return EditServiceScreen(service: args['service'], entreprise: args['entreprise']);
  },
    
    // Other routes will be defined here as needed
  };
}