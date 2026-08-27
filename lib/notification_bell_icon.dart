import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'notifications_page.dart';

/// Bell icon jo dashboard ki AppBar mein lagta he — [uids] (student ke liye
/// [studentId], ya parent ke liye sab siblings ke ids, ya teacher ke liye
/// [staffDocId]) ke un notifications ko count karta he jo abhi tak 'read'
/// nahi huye, aur unka number ek chhote LAAL badge mein upar-right corner
/// pe dikhata he (WhatsApp/Gmail jese apps ki tarah). Badge par tap karne
/// se seedha NotificationsPage khulta he, jahan tap karte hi wo notification
/// 'read' ho jati he aur count khud-b-khud kam ho jata he.
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
      // Composite index se bachne ke liye sirf 'toId whereIn' query karte
      // hain aur 'read' ka hisaab neeche Dart mein lagate hain (isi tarah
      // NotificationsPage bhi 'orderBy' Firestore ki jagah Dart mein karta
      // he — dekhein us file ka comment).
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
