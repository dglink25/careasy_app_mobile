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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';
import '../main.dart';
import '../services/message_polling_service.dart';
import 'package:careasy_app_mobile/screens/mes_entreprises_screen.dart' as entreprises;
import 'package:careasy_app_mobile/screens/rendez_vous/rendez_vous_list_screen.dart';
import '../providers/rendez_vous_provider.dart';
import '../widgets/app_bottom_nav.dart';
import 'package:careasy_app_mobile/screens/create_entreprise_screen.dart';
import 'carai_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dateFormat = DateFormat('dd/MM/yy');

  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  // ── Refresh automatique ────────────────────────────────────────────────────
  Timer? _refreshTimer;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reload();
      MessagePollingService().setActiveConversation(null);
      setupNotificationNavigation(context);
    });

    // Polling de secours toutes les 15 s (fallback si Pusher déconnecté)
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) context.read<MessageProvider>().loadConversations();
    });

    _searchController.addListener(() {
      setState(
          () => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  void _reload() {
    context.read<MessageProvider>().loadConversations();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
      MessagePollingService().setActiveConversation(null);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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

  // ── Navigation vers le chat ────────────────────────────────────────────────
  Future<void> _openChat(
      ConversationModel conv, MessageProvider provider) async {
    await provider.markConversationAsRead(conv.id);
    if (!mounted) return;
    await Navigator.push(
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
    );
    if (mounted) {
      MessagePollingService().setActiveConversation(null);
      provider.loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: _isSearching
            ? _buildSearchField()
            : const Text('Messages',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
          // Bouton refresh manuel
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
              tooltip: 'Actualiser',
            ),
        ],
      ),
      body: _isSearching ? _buildSearchResults() : _buildConversationList(),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
      floatingActionButton: const CarAIFab(),
    );
  }

  // ── Champ de recherche ─────────────────────────────────────────────────────
  Widget _buildSearchField() {
    return Container(
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
          prefixIcon: const Icon(Icons.search,
              color: AppConstants.primaryRed, size: 20),
          suffixIcon: IconButton(
            icon: Icon(Icons.close, color: Colors.grey[600], size: 18),
            onPressed: () {
              _searchController.clear();
              setState(() {
                _isSearching = false;
                _searchQuery = '';
              });
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  // ── Résultats de recherche ─────────────────────────────────────────────────
  Widget _buildSearchResults() {
    return Consumer<MessageProvider>(builder: (_, provider, __) {
      final query = _searchQuery;
      if (query.isEmpty) {
        return _emptySearch('Tapez pour rechercher une conversation');
      }

      final filtered = provider.conversations.where((conv) {
        final name = conv.otherUser.name.toLowerCase();
        final lastMsg = conv.lastMessage?.content.toLowerCase() ?? '';
        final service = (conv.serviceName ?? '').toLowerCase();
        final entreprise = (conv.entrepriseName ?? '').toLowerCase();
        return name.contains(query) ||
            lastMsg.contains(query) ||
            service.contains(query) ||
            entreprise.contains(query);
      }).toList();

      if (filtered.isEmpty) {
        return _emptySearch('Aucune conversation trouvée');
      }

      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _buildConvItem(filtered[i], provider),
      );
    });
  }

  Widget _emptySearch(String msg) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(msg,
            style: TextStyle(color: Colors.grey[500], fontSize: 14)),
      ]),
    );
  }

  // ── Liste principale ───────────────────────────────────────────────────────
  Widget _buildConversationList() {
    return Consumer<MessageProvider>(builder: (_, provider, __) {
      if (provider.isLoading && provider.conversations.isEmpty) {
        return const Center(
            child:
                CircularProgressIndicator(color: AppConstants.primaryRed));
      }

      if (provider.error != null && provider.conversations.isEmpty) {
        return _buildError(provider);
      }

      if (provider.conversations.isEmpty) {
        return _buildEmpty();
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

  Widget _buildError(MessageProvider provider) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
      const SizedBox(height: 16),
      Text('Erreur de chargement',
          style: TextStyle(fontSize: 18, color: Colors.grey[600])),
      const SizedBox(height: 8),
      Text(provider.error!,
          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          textAlign: TextAlign.center),
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

  Widget _buildEmpty() {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration:
            BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
        child:
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[600]),
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

  // ── Tuile conversation ─────────────────────────────────────────────────────
  Widget _buildConvItem(ConversationModel conv, MessageProvider provider) {
    final hasUnread = conv.unreadCount > 0;
    final isOnline = provider.getUserOnlineStatus(conv.otherUser.id) ||
        conv.otherUser.isOnline;

    // ── Label contextuel (vrai nom du service ou de l'entreprise) ─────────
    final contextLabel = conv.contextLabel; // null si aucun service attaché

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: hasUnread ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasUnread
            ? BorderSide(
                color: AppConstants.primaryRed.withOpacity(0.3), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _openChat(conv, provider),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // ── Avatar + indicateur en ligne ─────────────────────────────
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
                  bottom: 0, right: 0,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
            ]),
            const SizedBox(width: 12),

            // ── Contenu ──────────────────────────────────────────────────
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Row(children: [
                Expanded(
                  child: Text(
                    conv.otherUser.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            hasUnread ? FontWeight.bold : FontWeight.w600,
                        color: hasUnread
                            ? AppConstants.primaryRed
                            : Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // ── Badge service/entreprise (vrai nom) ──────────────────
                if (contextLabel != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    constraints: const BoxConstraints(maxWidth: 100),
                    decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      contextLabel,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue[800],
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),

                // ── Heure du dernier message ──────────────────────────────
                Text(
                  conv.lastMessage != null
                      ? _formatTime(conv.lastMessage!.createdAt)
                      : _formatTime(conv.updatedAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ]),

              const SizedBox(height: 4),

              // ── Aperçu du dernier message ─────────────────────────────
              if (conv.lastMessage != null)
                Row(children: [
                  if (conv.lastMessage!.isMe)
                    Text(
                      'Vous: ',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal),
                    ),
                  Expanded(
                    child: Text(
                      _lastMsgPreview(conv.lastMessage!),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
            ])),

            // ── Badge non-lus ─────────────────────────────────────────────
            if (hasUnread)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppConstants.primaryRed,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '${conv.unreadCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  String _lastMsgPreview(lastMsg) {
    switch (lastMsg.type) {
      case 'image':
        return 'Image';
      case 'video':
        return 'Vidéo';
      case 'audio':
      case 'vocal':
        return 'Message vocal';
      case 'document':
        return 'Document';
      case 'location':
        return 'Localisation';
      default:
        return lastMsg.content ?? '';
    }
  }
}