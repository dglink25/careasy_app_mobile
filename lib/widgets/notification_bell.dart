import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/notification_provider.dart';
import '../providers/rendez_vous_provider.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, prov, _) {
        final unread = prov.unreadCount;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().updateAppBadge(unread);
        });

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
              tooltip: 'Notifications',
              onPressed: () => _showNotifDropdown(context, prov),
            ),
            if (unread > 0)
              Positioned(
                right: 4,
                top: 4,
                child: IgnorePointer(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber[600],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showNotifDropdown(BuildContext context, NotificationProvider prov) {
    final recent = prov.recentThree;

    if (recent.isEmpty) {
      Navigator.pushNamed(context, '/notifications');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NotifDropdown(
        notifications: recent,
        unreadCount: prov.unreadCount,
        onMarkAllRead: () async {
          await prov.markAllAsRead();
          await NotificationService().clearBadge();
        },
        onViewAll: () => Navigator.pushNamed(context, '/notifications'),
        onTap: (notif, ctx) {
          if (!notif.isRead) {
            prov.markAsRead(notif.id);
          }
          _navigateToNotif(ctx, notif);
        },
      ),
    );
  }

  /// Même logique que NotificationsScreen._navigate
  void _navigateToNotif(BuildContext context, AppNotification notif) {
    final rdvId  = notif.data['rdv_id']?.toString() ?? '';
    final convId = notif.data['conversation_id']?.toString() ?? '';
    final type   = notif.type;

    if (rdvId.isNotEmpty) {
      // Rendez-vous → détail
      Navigator.pushNamed(context, '/rendez-vous/$rdvId');
    } else if (convId.isNotEmpty) {
      // Message → liste messages
      Navigator.pushNamed(context, '/messages');
    } else if (type.contains('rdv')) {
      Navigator.pushNamed(context, '/rendez-vous');
    } else if (type.contains('message')) {
      Navigator.pushNamed(context, '/messages');
    }
    // Sinon, le bottom sheet se ferme sans naviguer (type inconnu)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bottom sheet dropdown
// ─────────────────────────────────────────────────────────────────────────────
class _NotifDropdown extends StatelessWidget {
  final List<AppNotification> notifications;
  final int unreadCount;
  final VoidCallback onMarkAllRead;
  final VoidCallback onViewAll;
  final void Function(AppNotification, BuildContext) onTap;

  const _NotifDropdown({
    required this.notifications,
    required this.unreadCount,
    required this.onMarkAllRead,
    required this.onViewAll,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.notifications_rounded,
                    color: AppConstants.primaryRed, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryRed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                const Spacer(),
                if (unreadCount > 0)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onMarkAllRead();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppConstants.primaryRed,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Tout lire', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Les 3 dernières notifications
          ...notifications.map((n) => _NotifItem(
                notif: n,
                onTap: (ctx) {
                  Navigator.pop(ctx); // fermer le bottom sheet
                  onTap(n, ctx);
                },
              )),

          const Divider(height: 1),

          // Voir toutes
          InkWell(
            onTap: () {
              Navigator.pop(context);
              onViewAll();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Voir toutes les notifications',
                    style: TextStyle(
                      color: AppConstants.primaryRed,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios,
                      size: 12, color: AppConstants.primaryRed),
                ],
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tuile notification individuelle
// ─────────────────────────────────────────────────────────────────────────────
class _NotifItem extends StatelessWidget {
  final AppNotification notif;
  final void Function(BuildContext) onTap;

  const _NotifItem({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(context),
      child: Container(
        color: notif.isRead ? null : AppConstants.primaryRed.withOpacity(0.04),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icône colorée
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: notif.iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(notif.icon, color: notif.iconColor, size: 20),
            ),
            const SizedBox(width: 12),

            // Titre + corps + heure
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
                            fontSize: 13,
                            fontWeight: notif.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeago.format(notif.createdAt, locale: 'fr'),
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notif.body,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Point rouge si non lu
            if (!notif.isRead)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppConstants.primaryRed,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}