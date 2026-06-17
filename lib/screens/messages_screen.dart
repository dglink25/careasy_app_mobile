import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/message_provider.dart';
import '../models/conversation_model.dart';
import '../utils/constants.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import '../main.dart';
import '../services/message_service.dart';
import '../widgets/app_bottom_nav.dart';
import 'carai_screen.dart';
import '../widgets/accessibility_button.dart';
import '../models/message_model.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dateFormat = DateFormat('dd/MM/yy');

  bool                    _isSearching    = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String                  _searchQuery    = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Chargement initial uniquement — Pusher gère les mises à jour suivantes
      context.read<MessageProvider>().loadConversations();
      setupNotificationNavigation(context);
    });

    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Rechargement au retour au premier plan (pour rattraper les messages
      // reçus pendant que l'app était en arrière-plan)
      context.read<MessageProvider>().loadConversations();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _formatTime(DateTime t) {
    final now  = DateTime.now();
    final diff = now.difference(t);
    if (diff.inDays == 0) return _timeFormat.format(t);
    if (diff.inDays == 1) return 'Hier';
    return _dateFormat.format(t);
  }

  Future<void> _openChat(ConversationModel conv, MessageProvider provider) async {
    await provider.markConversationAsRead(conv.id);
    if (!mounted) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: provider,
          child: ChatScreen(
            conversationId : conv.id,
            otherUser      : conv.otherUser,
            serviceName    : conv.serviceName,
            entrepriseName : conv.entrepriseName,
          ),
        ),
      ),
    );

    if (!mounted) return;

    // Conversation supprimée depuis le ChatScreen
    if (result == 'deleted') {
      provider.loadConversations();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Conversation avec ${conv.otherUser.name} supprimée'),
          ]),
          backgroundColor: Colors.green[700],
          behavior       : SnackBarBehavior.floating,
          shape          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Retour normal : rafraîchir la liste
    provider.loadConversations();
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
            : const Text('Messages', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        actions: [
          if (!_isSearching) ...[
            // Indicateur de connexion WebSocket
            Consumer<MessageProvider>(builder: (_, pv, __) {
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: pv.isRealtimeConnected ? 'Temps réel actif' : 'Reconnexion…',
                  child: Icon(
                    pv.isRealtimeConnected ? Icons.wifi : Icons.wifi_off,
                    size: 18,
                    color: pv.isRealtimeConnected
                        ? Colors.white
                        : Colors.white54,
                  ),
                ),
              );
            }),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<MessageProvider>().loadConversations(),
              tooltip: 'Actualiser',
            ),
            const AccessibilityButton(),
          ],
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
        controller: _searchCtrl,
        autofocus: true,
        style: const TextStyle(color: Colors.black87, fontSize: 14),
        decoration: InputDecoration(
          hintText   : 'Rechercher une conversation...',
          hintStyle  : TextStyle(color: Colors.grey[500], fontSize: 13),
          prefixIcon : const Icon(Icons.search, color: AppConstants.primaryRed, size: 20),
          suffixIcon : IconButton(
            icon: Icon(Icons.close, color: Colors.grey[600], size: 18),
            onPressed: () {
              _searchCtrl.clear();
              setState(() { _isSearching = false; _searchQuery = ''; });
            },
          ),
          border           : InputBorder.none,
          contentPadding   : const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Consumer<MessageProvider>(builder: (_, provider, __) {
      if (_searchQuery.isEmpty) {
        return _emptySearch('Tapez pour rechercher une conversation');
      }
      final filtered = provider.conversations.where((conv) {
        final name        = conv.otherUser.name.toLowerCase();
        final lastMsg     = conv.lastMessage?.content.toLowerCase() ?? '';
        final service     = (conv.serviceName ?? '').toLowerCase();
        final entreprise  = (conv.entrepriseName ?? '').toLowerCase();
        return name.contains(_searchQuery)     ||
               lastMsg.contains(_searchQuery)  ||
               service.contains(_searchQuery)  ||
               entreprise.contains(_searchQuery);
      }).toList();

      if (filtered.isEmpty) return _emptySearch('Aucune conversation trouvée');
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _buildConvItem(filtered[i], provider),
      );
    });
  }

  Widget _emptySearch(String msg) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 16),
      Text(msg, style: TextStyle(color: Colors.grey[500], fontSize: 14)),
    ],
  ));

  // ── Liste principale ───────────────────────────────────────────────────────
  Widget _buildConversationList() {
    return Consumer<MessageProvider>(builder: (_, provider, __) {
      if (provider.isLoading && provider.conversations.isEmpty) {
        return const Center(
            child: CircularProgressIndicator(color: AppConstants.primaryRed));
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
          padding   : const EdgeInsets.all(12),
          itemCount : provider.conversations.length,
          itemBuilder: (_, i) => _buildConvItem(provider.conversations[i], provider),
        ),
      );
    });
  }

  Widget _buildError(MessageProvider provider) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
      const SizedBox(height: 16),
      Text('Erreur de chargement', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
      const SizedBox(height: 8),
      Text(provider.error!, style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: provider.loadConversations,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white),
        child: const Text('Réessayer'),
      ),
    ]),
  );

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding   : const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
        child: Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[600]),
      ),
      const SizedBox(height: 20),
      Text('Aucune conversation',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
      const SizedBox(height: 8),
      Text('Commencez à discuter avec des professionnels',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen())),
        icon    : const Icon(Icons.explore),
        label   : const Text('Découvrir des services'),
        style   : ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryRed, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
      ),
    ]),
  );

  // ── Tuile conversation ─────────────────────────────────────────────────────
  Widget _buildConvItem(ConversationModel conv, MessageProvider provider) {
    final hasUnread    = conv.unreadCount > 0;
    final isOnline     = provider.getUserOnlineStatus(conv.otherUser.id) || conv.otherUser.isOnline;
    final isTyping     = provider.isUserTyping(conv.id, conv.otherUser.id);
    final isRecording  = provider.isUserRecording(conv.id, conv.otherUser.id);
    final contextLabel = conv.contextLabel;

    return Dismissible(
      key: Key('conv_${conv.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title  : const Text('Supprimer la conversation'),
          content: Text('Supprimer la conversation avec ${conv.otherUser.name} ?\nTous les messages seront perdus.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Oui'),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        final success = await MessageService().deleteConversation(conv.id);
        if (mounted) {
          provider.loadConversations();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content         : Text(success
                ? 'Conversation avec ${conv.otherUser.name} supprimée'
                : 'Erreur lors de la suppression'),
            backgroundColor : success ? Colors.green : Colors.red,
            behavior        : SnackBarBehavior.floating,
            duration        : const Duration(seconds: 2),
          ));
        }
      },
      background: Container(
        margin    : const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
        alignment : Alignment.centerRight,
        padding   : const EdgeInsets.only(right: 20),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.delete_outline, color: Colors.white, size: 28),
          SizedBox(height: 4),
          Text('Supprimer', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
      child: Card(
        margin    : const EdgeInsets.only(bottom: 8),
        elevation : hasUnread ? 3 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: hasUnread
              ? BorderSide(color: AppConstants.primaryRed.withAlpha(77), width: 1)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap        : () => _openChat(conv, provider),
          borderRadius : BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              // ── Avatar + point en ligne ───────────────────────────────
              Stack(children: [
                CircleAvatar(
                  radius          : 28,
                  backgroundColor : Colors.grey[200],
                  backgroundImage : conv.otherUser.photoUrl != null
                      ? NetworkImage(conv.otherUser.photoUrl!) : null,
                  child: conv.otherUser.photoUrl == null
                      ? Text(
                          conv.otherUser.name.isNotEmpty
                              ? conv.otherUser.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold,
                              color: AppConstants.primaryRed))
                      : null,
                ),
                if (isOnline) Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                        color : const Color(0xFF25D366),
                        shape : BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
              ]),
              const SizedBox(width: 12),

              // ── Contenu texte ─────────────────────────────────────────
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ligne nom + label service + heure
                  Row(children: [
                    Expanded(child: Text(
                      conv.otherUser.name,
                      style: TextStyle(
                          fontSize    : 16,
                          fontWeight  : hasUnread ? FontWeight.bold : FontWeight.w600,
                          color       : hasUnread ? AppConstants.primaryRed : Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    )),
                    if (contextLabel != null)
                      Container(
                        margin     : const EdgeInsets.only(right: 6),
                        padding    : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        constraints: const BoxConstraints(maxWidth: 100),
                        decoration : BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(contextLabel,
                            style   : TextStyle(fontSize: 10, color: Colors.blue[800],
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                    Text(
                      conv.lastMessage != null
                          ? _formatTime(conv.lastMessage!.createdAt)
                          : _formatTime(conv.updatedAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ]),
                  const SizedBox(height: 4),

                  // ── Aperçu : typing / recording / dernier message ─────
                  if (isRecording)
                    _RecordingPreview(name: conv.otherUser.name)
                  else if (isTyping)
                    _TypingPreview(name: conv.otherUser.name)
                  else if (conv.lastMessage != null)
                    Row(children: [
                      if (conv.lastMessage!.isMe)
                        Text('Vous: ', style: TextStyle(
                            fontSize: 13, color: Colors.grey[700],
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal)),
                      Expanded(child: Text(
                        _lastMsgPreview(conv.lastMessage!),
                        style: TextStyle(
                            fontSize  : 13,
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                            color     : Colors.grey[600]),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      )),
                    ]),
                ],
              )),

              // ── Badge non lus ─────────────────────────────────────────
              if (hasUnread && !isTyping && !isRecording)
                Container(
                  margin : const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color        : AppConstants.primaryRed,
                    borderRadius : BorderRadius.circular(12)),
                  child: Text('${conv.unreadCount}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  String _lastMsgPreview(MessageModel msg) {
    switch (msg.type) {
      case 'image'   : return '📷 Image';
      case 'video'   : return '🎥 Vidéo';
      case 'audio'   :
      case 'vocal'   : return '🎤 Message vocal';
      case 'document': return '📎 Document';
      case 'location': return '📍 Localisation';
      default        : return msg.content;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Widgets temps réel pour la liste des conversations
// ═══════════════════════════════════════════════════════════════════════════

/// "en train d'écrire…" avec trois points animés — style WhatsApp
class _TypingPreview extends StatefulWidget {
  final String name;
  const _TypingPreview({required this.name});
  @override
  State<_TypingPreview> createState() => _TypingPreviewState();
}

class _TypingPreviewState extends State<_TypingPreview>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children    : [
        // Trois points en cascade
        AnimatedBuilder(
          animation: _anim,
          builder  : (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children    : List.generate(3, (i) {
              final phase = (_anim.value + i * 0.33) % 1.0;
              final scale = 0.5 + 0.5 *
                  (1.0 - (phase * 2 - 1).abs().clamp(0.0, 1.0));
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width : 6 * scale,
                height: 6 * scale,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'en train d\'écrire…',
          style: const TextStyle(
            fontSize  : 13,
            color     : Color(0xFF25D366),
            fontStyle : FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// "enregistre un vocal…" avec micro pulsant — style WhatsApp
class _RecordingPreview extends StatefulWidget {
  final String name;
  const _RecordingPreview({required this.name});
  @override
  State<_RecordingPreview> createState() => _RecordingPreviewState();
}

class _RecordingPreviewState extends State<_RecordingPreview>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children    : [
        AnimatedBuilder(
          animation: _anim,
          builder  : (_, __) => Icon(
            Icons.mic,
            size : 15,
            color: Color.lerp(
              Colors.red.withAlpha(80),
              Colors.red,
              _anim.value,
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          'enregistre un vocal…',
          style: TextStyle(
            fontSize  : 13,
            color     : Colors.red,
            fontStyle : FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}