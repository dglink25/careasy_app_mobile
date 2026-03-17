// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'providers/auth_provider.dart';
import 'providers/message_provider.dart';
import 'providers/service_provider.dart';
import 'services/notification_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'theme/app_theme.dart';

// ⭐ Clé de navigation globale
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase AVANT runApp
  try {
    await Firebase.initializeApp();
    // ⭐ Handler background OBLIGATOIREMENT avant runApp
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) { debugPrint('Firebase init: $e'); }

  // 2. Notifications locales
  try { await NotificationService().initialize(); }
  catch (e) { debugPrint('NotificationService init: $e'); }

  runApp(const CarEasyApp());
}

class CarEasyApp extends StatelessWidget {
  const CarEasyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..loadUserData()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
        ChangeNotifierProvider(create: (_) => ServiceProvider()),
      ],
      child: MaterialApp(
        title: 'CarEasy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        navigatorKey: navigatorKey,
        initialRoute: '/',
        routes: {
          '/': (context) => const WelcomeScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const HomeScreen(),
          '/messages': (context) => const MessagesScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name?.startsWith('/messages') == true) {
            return MaterialPageRoute(builder: (_) => const MessagesScreen());
          }
          return null;
        },
      ),
    );
  }
}

/// Appeler depuis initState() de HomeScreen ou MessagesScreen
void setupNotificationNavigation(BuildContext context) {
  NotificationService().onNotificationTap = (String conversationId) {
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/messages', (r) => r.isFirst);
  };
}