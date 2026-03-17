
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'providers/auth_provider.dart';
import 'providers/message_provider.dart';
import 'providers/service_provider.dart';
import 'services/notification_service.dart';
import 'services/pusher_service.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/chat_screen.dart';
import 'models/user_model.dart';
import 'utils/constants.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) { debugPrint('Firebase init: $e'); }

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
        home: const SplashScreen(),
        routes: {
          '/welcome':  (_) => const WelcomeScreen(),
          '/login':    (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/home':     (_) => const HomeScreen(),
          '/messages': (_) => const MessagesScreen(),
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

void setupNotificationNavigation(BuildContext context) {
  NotificationService().onNotificationTap = (Map<String, dynamic> data) async {
    final convId    = data['conversation_id']?.toString() ?? '';
    final senderName = data['sender_name']?.toString() ?? 'Contact';
    final senderPhoto = data['sender_photo']?.toString();
    final senderId   = data['sender_id']?.toString() ?? '';

    if (convId.isEmpty) {
      // Pas de conv_id → ouvrir la liste des messages
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/messages', (r) => r.isFirst);
      return;
    }

    // Récupérer les infos de la conversation pour ouvrir le bon chat
    try {
      final storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );
      final token = await storage.read(key: 'auth_token');
      
      if (token == null || token.isEmpty) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/messages', (r) => r.isFirst);
        return;
      }

      // Essayer de récupérer les détails de la conversation
      UserModel otherUser = UserModel(
        id:       senderId.isNotEmpty ? senderId : convId,
        name:     senderName,
        photoUrl: senderPhoto?.isNotEmpty == true ? senderPhoto : null,
        isOnline: false,
      );

      // Si on a le sender_id, essayer de charger son profil
      if (senderId.isNotEmpty) {
        try {
          final resp = await http.get(
            Uri.parse('${AppConstants.apiBaseUrl}/user/$senderId/online-status'),
            headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 5));
          
          if (resp.statusCode == 200) {
            final userData = jsonDecode(resp.body) as Map<String, dynamic>;
            // Mettre à jour avec les données fraîches si disponibles
          }
        } catch (_) {}
      }

      // Naviguer directement vers le ChatScreen
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (ctx) => ChangeNotifierProvider.value(
            value: navigatorKey.currentContext!.read<MessageProvider>(),
            child: ChatScreen(
              conversationId: convId,
              otherUser:      otherUser,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NotifNav] Erreur navigation: $e');
      // Fallback : ouvrir la liste des messages
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/messages', (r) => r.isFirst);
    }
  };
}