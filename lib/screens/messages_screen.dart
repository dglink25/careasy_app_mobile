// lib/screens/messages_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// CORRECTIONS:
// - Suppression des icônes d'appel
// - Ajout recherche de conversation
// ═══════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../providers/message_provider.dart';
import '../providers/auth_provider.dart';
import '../models/conversation_model.dart';
import '../utils/constants.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'welcome_screen.dart';
import 'all_services_screen.dart';
import 'all_entreprises_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../main.dart';
import '../services/message_polling_service.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dateFormat = DateFormat('dd/MM/yy');
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  int _currentIndex = 1;
  Map<String, dynamic>? _userData;
  bool _hasEntreprise = false;

  // Recherche
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
      context.read<MessageProvider>().loadConversations();
      MessagePollingService().setActiveConversation(null);
      setupNotificationNavigation(context);
    });

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<MessageProvider>().loadConversations();
      MessagePollingService().setActiveConversation(null);
    }
  }

  Future<void> _loadUserData() async {
    try {
      final s = await _storage.read(key: 'user_data');
      if (s != null) {
        setState(() {
          _userData = jsonDecode(s);
          _hasEntreprise = _userData?['has_entreprise'] ?? false;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (now.difference(t).inDays == 0) return _timeFormat.format(t);
    if (now.difference(t).inDays == 1) return 'Hier';
    return _dateFormat.format(t);
  }

  void _showComingSoon(String f) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$f — Bientôt disponible'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2)),
      );

  void _handleEntrepriseTap() {
    _showComingSoon('Mon entreprise');
  }

  void _showProfileDialog() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))
        .then((_) => _loadUserData());
  }

  Future<void> _logout() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('${AppConstants.apiBaseUrl}/logout'),
            headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
    } catch (_) {}
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_data');
    await _storage.delete(key: 'fcm_token_pending');
    await _storage.delete(key: 'remember_me');
    await _storage.delete(key: 'login_time');
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final userName = _userData?['name'] ?? 'Utilisateur';
    final userPhoto = _userData?['profile_photo_url'] ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: _isSearching
            ? Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Rechercher une conversation...',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: AppConstants.primaryRed, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[600], size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() { _isSearching = false; _searchQuery = ''; });
                      },
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              )
            : const Text('Messages',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
        ],
        bottom: _isSearching ? null : TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              child: Consumer<MessageProvider>(builder: (_, provider, __) {
                return Stack(clipBehavior: Clip.none, children: [
                  const Text('Messages'),
                  if (provider.totalUnreadCount > 0)
                    Positioned(
                      right: -12,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.amber, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text('${provider.totalUnreadCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center),
                      ),
                    ),
                ]);
              }),
            ),
            const Tab(text: 'Groupes'),
          ],
        ),
      ),
      body: _isSearching
          ? _buildSearchResults()
          : TabBarView(
              controller: _tabController,
              children: [_buildMessagesTab(), _buildGroupsTab()],
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -5))
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _navItem(Icons.home, 'Accueil', 0, size),
              _navItem(Icons.message, 'Messages', 1, size),
              _navItem(Icons.calendar_today, 'Rendez-vous', 2, size),
              _navItem(
                  _hasEntreprise ? Icons.business : Icons.add_business,
                  _hasEntreprise ? 'Entreprise' : 'Créer',
                  3,
                  size),
              _profileNavItem(userName, userPhoto, 4, size),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Recherche de conversations ─────────────────────────────────────
  Widget _buildSearchResults() {
    return Consumer<MessageProvider>(builder: (_, provider, __) {
      final query = _searchQuery;
      if (query.isEmpty) {
        return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.search, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Tapez pour rechercher une conversation',
                style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ]),
        );
      }

      final filtered = provider.conversations.where((conv) {
        final name = conv.otherUser.name.toLowerCase();
        final lastMsg = conv.lastMessage?.content.toLowerCase() ?? '';
        final service = (conv.serviceName ?? '').toLowerCase();
        return name.contains(query) || lastMsg.contains(query) || service.contains(query);
      }).toList();

      if (filtered.isEmpty) {
        return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Aucune conversation trouvée',
                style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ]),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _buildConvItem(filtered[i], provider),
      );
    });
  }

  Widget _navItem(IconData icon, String label, int index, Size size) {
    final sel = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);
          if (index == 0) {
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          } else if (index == 2) {
            _showComingSoon('Rendez-vous');
          } else if (index == 3) {
            _handleEntrepriseTap();
          } else if (index == 4) {
            _showProfileDialog();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(icon, color: sel ? AppConstants.primaryRed : Colors.grey, size: 22),
              if (index == 1)
                Consumer<MessageProvider>(builder: (_, p, __) {
                  if (p.totalUnreadCount == 0) return const SizedBox.shrink();
                  return Positioned(
                    right: -6,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.amber, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                      child: Text('${p.totalUnreadCount}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                    ),
                  );
                }),
            ]),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: sel ? AppConstants.primaryRed : Colors.grey,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _profileNavItem(String name, String photo, int index, Size size) {
    final sel = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);
          _showProfileDialog();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 11,
              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
              backgroundColor: Colors.grey[200],
              child: photo.isEmpty
                  ? Icon(Icons.person, size: 12, color: Colors.grey[600])
                  : null,
            ),
            const SizedBox(height: 2),
            Text('Profil',
                style: TextStyle(
                    fontSize: 10,
                    color: sel ? AppConstants.primaryRed : Colors.grey,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _buildMessagesTab() {
    return Consumer<MessageProvider>(builder: (_, provider, __) {
      if (provider.isLoading && provider.conversations.isEmpty) {
        return const Center(
            child: CircularProgressIndicator(color: AppConstants.primaryRed));
      }

      if (provider.error != null) {
        return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Erreur de chargement',
              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text(provider.error!, style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: provider.loadConversations,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryRed,
                foregroundColor: Colors.white),
            child: const Text('Réessayer'),
          ),
        ]));
      }

      if (provider.conversations.isEmpty) {
        return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration:
                BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
            child: Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Text('Aucune conversation',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
          const SizedBox(height: 8),
          Text('Commencez à discuter avec des professionnels',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const HomeScreen())),
            icon: const Icon(Icons.explore),
            label: const Text('Découvrir des services'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryRed,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          ),
        ]));
      }

      return RefreshIndicator(
        onRefresh: provider.loadConversations,
        color: AppConstants.primaryRed,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: provider.conversations.length,
          itemBuilder: (_, i) =>
              _buildConvItem(provider.conversations[i], provider),
        ),
      );
    });
  }

  Widget _buildConvItem(ConversationModel conv, MessageProvider provider) {
    final hasUnread = conv.unreadCount > 0;
    final isOnline = conv.otherUser.isOnline;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: hasUnread ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasUnread
            ? BorderSide(color: AppConstants.primaryRed.withOpacity(0.3), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () async {
          await provider.markConversationAsRead(conv.id);
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: provider,
                  child: ChatScreen(
                    conversationId: conv.id,
                    otherUser: conv.otherUser,
                    serviceName: conv.serviceName,
                    entrepriseName: conv.entrepriseName,
                  ),
                ),
              ),
            ).then((_) {
              MessagePollingService().setActiveConversation(null);
              provider.loadConversations();
            });
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Avatar
            Stack(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey[200],
                backgroundImage: conv.otherUser.photoUrl != null
                    ? NetworkImage(conv.otherUser.photoUrl!)
                    : null,
                child: conv.otherUser.photoUrl == null
                    ? Text(
                        conv.otherUser.name.isNotEmpty
                            ? conv.otherUser.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryRed))
                    : null,
              ),
              if (isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
            ]),
            const SizedBox(width: 12),

            // Contenu
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Row(children: [
                Expanded(
                  child: Text(conv.otherUser.name,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              hasUnread ? FontWeight.bold : FontWeight.w600,
                          color: hasUnread
                              ? AppConstants.primaryRed
                              : Colors.black87)),
                ),
                if (conv.serviceName != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('Service',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600)),
                  ),
                Text(
                  conv.lastMessage != null
                      ? _formatTime(conv.lastMessage!.createdAt)
                      : _formatTime(conv.updatedAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ]),
              const SizedBox(height: 4),
              if (conv.lastMessage != null)
                Row(children: [
                  if (conv.lastMessage!.isMe)
                    Text('Vous: ',
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                hasUnread ? Colors.grey[700] : Colors.grey[600],
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.normal)),
                  Expanded(
                    child: Text(
                      _lastMsgPreview(conv.lastMessage!),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.normal,
                          color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
            ])),

            // Badge non lus
            if (hasUnread)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppConstants.primaryRed,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${conv.unreadCount}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
      ),
    );
  }

  String _lastMsgPreview(lastMsg) {
    switch (lastMsg.type) {
      case 'image':    return 'Image';
      case 'video':    return 'Vidéo';
      case 'audio':
      case 'vocal':    return 'Message vocal';
      case 'document': return 'Document';
      case 'location': return 'Localisation';
      default:         return lastMsg.content ?? '';
    }
  }

  Widget _buildGroupsTab() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.group_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text('Groupes',
            style: TextStyle(fontSize: 18, color: Colors.grey[600])),
        const SizedBox(height: 8),
        Text('Bientôt disponible',
            style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      ]),
    );
  }
}