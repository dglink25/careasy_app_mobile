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
import 'providers/theme_provider.dart';
import 'providers/rendez_vous_provider.dart';
import 'providers/notification_provider.dart';           // ← AJOUT
import 'services/notification_service.dart';
import 'services/pusher_service.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/notifications_screen.dart';             // ← AJOUT
import 'screens/rendez_vous/rendez_vous_list_screen.dart';
import 'screens/rendez_vous/rendez_vous_detail_screen.dart';
import 'models/user_model.dart';
import 'utils/constants.dart';
import 'theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase init: $e');
  }

  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('NotificationService init: $e');
  }
  await initializeDateFormatting('fr_FR', null);

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const CarEasyApp(),
    ),
  );
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
        ChangeNotifierProvider(create: (_) => RendezVousProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),  // ← AJOUT
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'CarEasy',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            navigatorKey: navigatorKey,
            home: const SplashScreen(),
            routes: {
              '/welcome'       : (_) => const WelcomeScreen(),
              '/login'         : (_) => const LoginScreen(),
              '/register'      : (_) => const RegisterScreen(),
              '/home'          : (_) => const HomeScreen(),
              '/messages'      : (_) => const MessagesScreen(),
              '/rendez-vous'   : (_) => const RendezVousListScreen(),
              '/notifications' : (_) => const NotificationsScreen(), // ← AJOUT
            },
            onGenerateRoute: (settings) {
              if (settings.name?.startsWith('/messages') == true) {
                return MaterialPageRoute(builder: (_) => const MessagesScreen());
              }

              if (settings.name?.startsWith('/rendez-vous/') == true) {
                final id = settings.name!.split('/rendez-vous/').last;
                if (id.isNotEmpty) {
                  return MaterialPageRoute(
                    builder: (ctx) => ChangeNotifierProvider.value(
                      value: ctx.read<RendezVousProvider>(),
                      child: RendezVousDetailScreen(rdvId: id),
                    ),
                  );
                }
              }

              return null;
            },
          );
        },
      ),
    );
  }
}

// ── Navigation depuis les notifications ───────────────────────────────────────
void setupNotificationNavigation(BuildContext context) {
  NotificationService().onNotificationTap = (Map<String, dynamic> data) async {
    final type   = data['type']?.toString() ?? '';
    final convId = data['conversation_id']?.toString() ?? '';
    final rdvId  = data['rdv_id']?.toString() ?? '';

    // Marquer le badge à 0 à la navigation
    final notifProv = navigatorKey.currentContext?.read<NotificationProvider>();

    // ── Demande de notation ───────────────────────────────────────────
    if (type == 'review_request' && rdvId.isNotEmpty) {
      notifProv?.fetchNotifications(silent: true);
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (ctx) => ChangeNotifierProvider.value(
            value: navigatorKey.currentContext!.read<RendezVousProvider>(),
            child: RendezVousDetailScreen(rdvId: rdvId),
          ),
        ),
      );
      return;
    }

    // ── Notifications RDV ─────────────────────────────────────────────
    if (type.startsWith('rdv_') || rdvId.isNotEmpty) {
      notifProv?.fetchNotifications(silent: true);
      if (rdvId.isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (ctx) => ChangeNotifierProvider.value(
              value: navigatorKey.currentContext!.read<RendezVousProvider>(),
              child: RendezVousDetailScreen(rdvId: rdvId),
            ),
          ),
        );
      } else {
        navigatorKey.currentState?.pushNamed('/rendez-vous');
      }
      return;
    }

    // ── Notifications Messages ────────────────────────────────────────
    if (convId.isEmpty) {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/messages', (r) => r.isFirst);
      return;
    }

    final senderName  = data['sender_name']?.toString()  ?? 'Contact';
    final senderPhoto = data['sender_photo']?.toString();
    final senderId    = data['sender_id']?.toString()    ?? '';

    UserModel otherUser = UserModel(
      id      : senderId.isNotEmpty ? senderId : convId,
      name    : senderName,
      photoUrl: (senderPhoto?.isNotEmpty == true) ? senderPhoto : null,
      isOnline: false,
    );

    if (senderId.isNotEmpty) {
      try {
        const storage = FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );
        final token = await storage.read(key: 'auth_token');
        if (token != null && token.isNotEmpty) {
          final resp = await http
              .get(
                Uri.parse('${AppConstants.apiBaseUrl}/user/$senderId/online-status'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Accept': 'application/json',
                },
              )
              .timeout(const Duration(seconds: 5));

          if (resp.statusCode == 200) {
            final userData = jsonDecode(resp.body) as Map<String, dynamic>;
            otherUser = UserModel(
              id      : senderId,
              name    : senderName,
              photoUrl: senderPhoto?.isNotEmpty == true ? senderPhoto : null,
              isOnline: userData['is_online'] == true,
            );
          }
        }
      } catch (_) {}
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (ctx) => ChangeNotifierProvider.value(
          value: navigatorKey.currentContext!.read<MessageProvider>(),
          child: ChatScreen(
            conversationId: convId,
            otherUser     : otherUser,
          ),
        ),
      ),
    );
  };
}