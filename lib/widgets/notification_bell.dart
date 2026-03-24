import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/notification_provider.dart';
import '../utils/constants.dart';
import '../screens/notifications_screen.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, prov, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 26),
              tooltip: 'Notifications',
              onPressed: () => _showDropdown(context, prov),
            ),
            // Badge
            if (prov.unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: _Badge(count: prov.unreadCount),
              ),
          ],
        );
      },
    );
  }

  void _showDropdown(BuildContext context, NotificationProvider prov) {
    // Recharger silencieusement à l'ouverture
    prov.fetchNotifications(silent: true);

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final buttonPos = button.localToGlobal(Offset.zero, ancestor: overlay);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => _NotifDropdown(
        position: buttonPos,
        buttonWidth: button.size.width,
        prov: prov,
        onSeeAll: () {
          Navigator.pop(ctx);
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()));
        },
        onNavigate: (notif) {
          Navigator.pop(ctx);
          _navigate(context, notif);
        },
      ),
    );
  }

  void _navigate(BuildContext context, AppNotification n) {
    if (!n.isRead) context.read<NotificationProvider>().markAsRead(n.id);
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

// ─── Badge numérique ─────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppConstants.primaryRed, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Dropdown ────────────────────────────────────────────────────────────────
class _NotifDropdown extends StatelessWidget {
  final Offset position;
  final double buttonWidth;
  final NotificationProvider prov;
  final VoidCallback onSeeAll;
  final ValueChanged<AppNotification> onNavigate;

  const _NotifDropdown({
    required this.position,
    required this.buttonWidth,
    required this.prov,
    required this.onSeeAll,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    const dropWidth = 320.0;
    double left = position.dx - dropWidth + buttonWidth;
    if (left < 8) left = 8;
    if (left + dropWidth > screenW - 8) left = screenW - dropWidth - 8;
    final top = position.dy + 48;

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: dropWidth,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        const Text('Notifications',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        const Spacer(),
                        if (prov.unreadCount > 0)
                          TextButton(
                            onPressed: prov.markAllAsRead,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                            child: Text('Tout lire',
                                style: TextStyle(
                                    color: AppConstants.primaryRed,
                                    fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 0),

                  // 3 dernières
                  if (prov.recentThree.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 24, horizontal: 16),
                      child: Column(
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              size: 36, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text('Aucune notification',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 13)),
                        ],
                      ),
                    )
                  else
                    ...prov.recentThree.map((n) => _DropdownTile(
                          notif: n,
                          onTap: () => onNavigate(n),
                        )),

                  const Divider(height: 0),

                  // Voir plus
                  InkWell(
                    onTap: onSeeAll,
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Voir toutes les notifications',
                            style: TextStyle(
                              color: AppConstants.primaryRed,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 12, color: AppConstants.primaryRed),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tuile dans le dropdown ──────────────────────────────────────────────────
class _DropdownTile extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onTap;

  const _DropdownTile({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: notif.isRead
            ? Colors.transparent
            : AppConstants.primaryRed.withOpacity(0.04),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: notif.iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(notif.icon, color: notif.iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif.title,
                    style: TextStyle(
                      fontWeight:
                          notif.isRead ? FontWeight.w500 : FontWeight.w700,
                      fontSize: 13,
                      color: Colors.grey[900],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notif.body,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    timeago.format(notif.createdAt, locale: 'fr'),
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
            if (!notif.isRead)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
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