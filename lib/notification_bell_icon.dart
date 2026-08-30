import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'notifications_page.dart';

/// The bell icon shown in the dashboard's AppBar — counts [uids]'s
/// (student's [studentId], or all siblings' ids for a parent, or the
/// [staffDocId] for a teacher) notifications that aren't 'read' yet,
/// and shows that number in a small RED badge in the top-right corner
/// (like WhatsApp/Gmail-style apps). Tapping the badge opens
/// NotificationsPage directly, where tapping a notification marks it
/// 'read' and the count automatically decreases.
class NotificationBellIcon extends StatelessWidget {
  final List<String> uids;
  final Color iconColor;

  const NotificationBellIcon({
    super.key,
    required this.uids,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final queryIds = uids.take(30).toList();

    if (queryIds.isEmpty) {
      return IconButton(
        icon: Icon(Icons.notifications, color: iconColor),
        tooltip: "Notifications",
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NotificationsPage(uids: uids)),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      // To avoid needing a composite index, only a 'toId whereIn' query
      // is done, and 'read' is counted below in Dart (NotificationsPage
      // does the same thing with 'orderBy' in Dart instead of Firestore
      // — see that file's comment).
      stream: schoolCollection('push_notifications')
          .where('toId', whereIn: queryIds)
          .snapshots(),
      builder: (context, snapshot) {
        int unread = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            if (d['read'] != true) unread++;
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.notifications, color: iconColor),
              tooltip: "Notifications",
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => NotificationsPage(uids: uids)),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
