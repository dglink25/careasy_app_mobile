import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Providers
import 'providers/auth_provider.dart';
import 'providers/message_provider.dart';
import 'providers/service_provider.dart';

// Services
import 'services/notification_service.dart';

// Screens
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/chat_screen.dart';

// Utils
import 'theme/app_theme.dart';

// Clé globale de navigation pour la navigation depuis les notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Firebase (DOIT être initialisé avant tout handler FCM) ──────────────
  try {
    await Firebase.initializeApp();
    // Enregistrer le handler background FCM ICI, avant runApp()
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } 
  catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Notification initialization error: $e');
  }

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
          // Route dynamique pour ouvrir directement une conversation
          if (settings.name?.startsWith('/chat/') == true) {
            final conversationId =
                settings.name!.replaceFirst('/chat/', '');
            final args = settings.arguments as Map<String, dynamic>?;
            // La navigation vers ChatScreen nécessite otherUser
            // On navigue vers MessagesScreen qui va charger la conv
            return MaterialPageRoute(
              builder: (_) => const MessagesScreen(),
            );
          }
          return null;
        },
      ),
    );
  }
}

/// Configurer le callback de navigation pour les notifications
/// À appeler depuis un widget qui a accès au contexte après l'init
void setupNotificationNavigation(BuildContext context) {
  NotificationService().onNotificationTap = (conversationId) {
    // Naviguer vers la liste des messages
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/messages',
      (route) => route.isFirst,
    );
  };
}