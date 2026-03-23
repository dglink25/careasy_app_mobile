import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../providers/message_provider.dart';
import '../providers/rendez_vous_provider.dart';
import '../utils/constants.dart';

// ── Imports des écrans (lazy — pas de circularité) ───────────────────────────
import '../screens/home_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/rendez_vous/rendez_vous_list_screen.dart';
import '../screens/mes_entreprises_screen.dart';
import '../screens/settings_screen.dart';

class AppBottomNav extends StatefulWidget {
  final int currentIndex;
  const AppBottomNav({super.key, required this.currentIndex});

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  late int _index;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _index = widget.currentIndex;
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final raw = await _storage.read(key: 'user_data');
      if (raw != null && raw.isNotEmpty && mounted) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          setState(() => _userData = Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {}
  }

  // ── Logique de navigation — copie exacte de home_screen ──────────────────
  void _onTap(int index) {
    if (index == _index && index != 0) return;
    setState(() => _index = index);

    switch (index) {
      case 0:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
        break;

      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MessagesScreen()),
        ).then((_) {
          if (mounted) {
            try {
              context.read<MessageProvider>().loadConversations();
            } catch (_) {}
          }
        });
        break;

      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: context.read<RendezVousProvider>(),
              child: const RendezVousListScreen(),
            ),
          ),
        );
        break;

      case 3:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MesEntreprisesScreen()),
        );
        break;

      case 4:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ).then((_) {
          if (mounted) _loadUser();
        });
        break;
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final userPhoto = _userData?['profile_photo_url'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).cardColor
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _item(Icons.home_rounded,           'Accueil',     0),
              _itemBadge(Icons.message_rounded,   'Messages',    1),
              _item(Icons.calendar_today_rounded, 'Rendez-vous', 2),
              _item(Icons.business_rounded,       'Entreprise',  3),
              _profileItem(userPhoto, 4),
            ],
          ),
        ),
      ),
    );
  }

  // ── Item simple ───────────────────────────────────────────────────────────
  Widget _item(IconData icon, String label, int index) {
    final sel = _index == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onTap(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                color: sel ? AppConstants.primaryRed : Colors.grey,
                size: 22),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  color: sel ? AppConstants.primaryRed : Colors.grey,
                  fontWeight:
                      sel ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  // ── Item Messages avec badge non-lus ──────────────────────────────────────
  Widget _itemBadge(IconData icon, String label, int index) {
    final sel = _index == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onTap(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(icon,
                  color: sel ? AppConstants.primaryRed : Colors.grey,
                  size: 22),
              Consumer<MessageProvider>(builder: (_, p, __) {
                if (p.totalUnreadCount == 0) return const SizedBox.shrink();
                return Positioned(
                  right: -6, top: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.amber, shape: BoxShape.circle),
                    constraints: const BoxConstraints(
                        minWidth: 14, minHeight: 14),
                    child: Text(
                      p.totalUnreadCount > 99
                          ? '99+'
                          : '${p.totalUnreadCount}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }),
            ]),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  color: sel ? AppConstants.primaryRed : Colors.grey,
                  fontWeight:
                      sel ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  // ── Item Profil avec avatar ───────────────────────────────────────────────
  Widget _profileItem(String photo, int index) {
    final sel = _index == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onTap(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 22, height: 22,
              decoration: sel
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppConstants.primaryRed, width: 2))
                  : null,
              child: CircleAvatar(
                radius: 10,
                backgroundImage:
                    photo.isNotEmpty ? NetworkImage(photo) : null,
                backgroundColor: Colors.grey[200],
                child: photo.isEmpty
                    ? Icon(Icons.person,
                        size: 12, color: Colors.grey[600])
                    : null,
              ),
            ),
            const SizedBox(height: 2),
            Text('Profil',
                style: TextStyle(
                  fontSize: 10,
                  color: sel ? AppConstants.primaryRed : Colors.grey,
                  fontWeight:
                      sel ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}