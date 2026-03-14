import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;
import 'package:intl/intl.dart';
import '../providers/message_provider.dart';
import '../models/conversation_model.dart';
import '../utils/constants.dart';
import './chat_screen.dart';
import 'package:shimmer/shimmer.dart';

class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dateFormat = DateFormat('dd/MM/yy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessageProvider>().loadConversations();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    if (now.difference(time).inDays == 0) {
      return _timeFormat.format(time);
    } else if (now.difference(time).inDays == 1) {
      return 'Hier';
    } else {
      return _dateFormat.format(time);
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
        title: const Text(
          'Messages',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Consumer<MessageProvider>(
                builder: (context, provider, child) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Text('Messages'),
                      if (provider.totalUnreadCount > 0)
                        Positioned(
                          right: -15,
                          top: -8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '${provider.totalUnreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const Tab(text: 'Appels'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMessagesTab(),
          _buildCallsTab(),
        ],
      ),
    );
  }

  Widget _buildMessagesTab() {
    return Consumer<MessageProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.conversations.isEmpty) {
          return _buildShimmerLoading();
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Erreur de chargement',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.error!,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => provider.loadConversations(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          );
        }

        if (provider.conversations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Aucune conversation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Commencez à discuter avec des professionnels',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.explore),
                  label: const Text('Découvrir des services'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadConversations(),
          color: AppConstants.primaryRed,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: provider.conversations.length,
            itemBuilder: (context, index) {
              final conversation = provider.conversations[index];
              return _buildConversationItem(conversation, provider);
            },
          ),
        );
      },
    );
  }

  Widget _buildConversationItem(ConversationModel conversation, MessageProvider provider) {
    final hasUnread = conversation.unreadCount > 0;
    final isOnline = conversation.otherUser.isOnline;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: hasUnread ? 3 : 1,
      shadowColor: hasUnread ? AppConstants.primaryRed.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasUnread 
            ? BorderSide(color: AppConstants.primaryRed.withOpacity(0.3), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () async {
          // Marquer comme lu avant de naviguer
          await provider.markConversationAsRead(conversation.id);
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  conversationId: conversation.id,
                  otherUser: conversation.otherUser,
                  serviceName: conversation.serviceName,
                  entrepriseName: conversation.entrepriseName,
                ),
              ),
            ).then((_) {
              // Recharger les conversations au retour
              provider.loadConversations();
            });
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar avec indicateur de statut
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: conversation.otherUser.photoUrl != null
                        ? NetworkImage(conversation.otherUser.photoUrl!)
                        : null,
                    child: conversation.otherUser.photoUrl == null
                        ? Text(
                            conversation.otherUser.name.isNotEmpty
                                ? conversation.otherUser.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.primaryRed,
                            ),
                          )
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
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Contenu
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.otherUser.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                              color: hasUnread ? AppConstants.primaryRed : Colors.black87,
                            ),
                          ),
                        ),
                        if (conversation.serviceName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Service',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          conversation.lastMessage != null
                              ? _formatMessageTime(conversation.lastMessage!.createdAt)
                              : _formatMessageTime(conversation.updatedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    
                    // Dernier message
                    Row(
                      children: [
                        if (conversation.lastMessage != null) ...[
                          if (conversation.lastMessage!.type != 'text')
                            Container(
                              margin: const EdgeInsets.only(right: 4),
                              child: Icon(
                                _getMessageTypeIcon(conversation.lastMessage!.type),
                                size: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          Expanded(
                            child: Text(
                              conversation.lastMessage!.isMe ? 'Vous: ' : '',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Badge de non lus
              if (hasUnread)
                badges.Badge(
                badgeContent: Text(
                  '${conversation.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                badgeStyle: badges.BadgeStyle(
                  badgeColor: AppConstants.primaryRed,
                ),
                position: badges.BadgePosition.topEnd(),
                child: const SizedBox(width: 30, height: 30),
              )
            ],
          ),
        ),
      ),
    );
  }

  IconData _getMessageTypeIcon(String type) {
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'audio':
      case 'vocal':
        return Icons.mic;
      case 'document':
        return Icons.insert_drive_file;
      case 'location':
        return Icons.location_on;
      default:
        return Icons.message;
    }
  }

  Widget _buildCallsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.phone_in_talk, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Historique des appels',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Bientôt disponible',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      },
    );
  }
}