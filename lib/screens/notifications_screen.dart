import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/notification_provider.dart';
import '../utils/constants.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Consumer<NotificationProvider>(
            builder: (_, prov, __) => prov.unreadCount > 0
                ? TextButton.icon(
                    onPressed: prov.markAllAsRead,
                    icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
                    label: const Text('Tout lire',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, prov, _) {
          if (prov.isLoading && prov.notifications.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (prov.notifications.isEmpty) {
            return _buildEmpty();
          }
          return RefreshIndicator(
            onRefresh: () => prov.fetchNotifications(),
            color: AppConstants.primaryRed,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: prov.notifications.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 0, indent: 72),
              itemBuilder: (context, i) {
                final n = prov.notifications[i];
                return _NotifTile(
                  notif: n,
                  onTap: () {
                    if (!n.isRead) prov.markAsRead(n.id);
                    _navigate(context, n);
                  },
                  onDismiss: () => prov.delete(n.id),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none_rounded,
                size: 56, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text('Aucune notification',
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600,
                color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text('Vous êtes à jour !',
              style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, AppNotification n) {
    final rdvId = n.data['rdv_id']?.toString() ?? '';
    final convId = n.data['conversation_id']?.toString() ?? '';

    if (rdvId.isNotEmpty) {
      Navigator.pushNamed(context, '/rendez-vous/$rdvId');
    } else if (convId.isNotEmpty) {
      Navigator.pushNamed(context, '/messages');
    } else if (n.type.contains('rdv')) {
      Navigator.pushNamed(context, '/rendez-vous');
    } else if (n.type.contains('message')) {
      Navigator.pushNamed(context, '/messages');
    }
  }
}

// ─── Tuile notification ────────────────────────────────────────────────────
class _NotifTile extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotifTile({
    required this.notif,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notif.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red[400],
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      onDismissed: (_) => onDismiss(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: notif.isRead ? Colors.white : AppConstants.primaryRed.withOpacity(0.04),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icône
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: notif.iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(notif.icon, color: notif.iconColor, size: 22),
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
                            notif.title,
                            style: TextStyle(
                              fontWeight: notif.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              fontSize: 14,
                              color: Colors.grey[900],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeago.format(notif.createdAt, locale: 'fr'),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notif.body,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          height: 1.35),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Point non lu
              if (!notif.isRead) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryRed,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}