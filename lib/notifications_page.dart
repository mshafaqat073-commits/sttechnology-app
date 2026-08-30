import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';

// ============================================================================
// NotificationsPage
// ----------------------------------------------------------------------------
// The list of notifications for the logged-in student/teacher (or
// parent, if they have multiple children) — opened from the bell icon.
// Shows only documents from the 'push_notifications' collection for
// these [uids] (toId whereIn uids), newest at the top.
//
// Requires: intl package (add `intl: ^0.19.0` in pubspec.yaml if it
// isn't already there).
// ============================================================================

class NotificationsPage extends StatelessWidget {
  // One uid (student/teacher), or all siblings' uids in a parent's case.
  final List<String> uids;
  const NotificationsPage({super.key, required this.uids});

  IconData _iconFor(String type) {
    switch (type) {
      case 'diary':
        return Icons.menu_book;
      case 'homework':
        return Icons.assignment;
      case 'fee':
        return Icons.attach_money;
      case 'attendance':
        return Icons.check_circle;
      case 'message':
        return Icons.message;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Firestore's whereIn takes a max of 30 values — plenty for the
    // normal use case (siblings).
    final queryIds = uids.take(30).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        actions: [
          if (queryIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: "Mark all as read",
              onPressed: () async {
                final snap = await schoolCollection('push_notifications')
                    .where('toId', whereIn: queryIds)
                    .get();
                final batch = FirebaseFirestore.instance.batch();
                for (final d in snap.docs) {
                  if ((d.data())['read'] != true) {
                    batch.update(d.reference, {'read': true});
                  }
                }
                await batch.commit();
              },
            ),
        ],
      ),
      body: queryIds.isEmpty
          ? const Center(child: Text("No notifications yet."))
          : StreamBuilder<QuerySnapshot>(
              // Note: 'orderBy' is deliberately not used here — using
              // 'orderBy' on a different field alongside 'whereIn' makes
              // Firestore require a composite index (which has to be
              // built manually in the Firebase Console). To avoid that,
              // the docs are sorted in Dart below after fetching.
              stream: schoolCollection('push_notifications')
                  .where('toId', whereIn: queryIds)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final aTs = (a.data() as Map<String, dynamic>)['createdAt']
                        as Timestamp?;
                    final bTs = (b.data() as Map<String, dynamic>)['createdAt']
                        as Timestamp?;
                    if (aTs == null || bTs == null) return 0;
                    return bTs.compareTo(aTs); // newest first
                  });
                if (docs.isEmpty) {
                  return const Center(
                    child: Text("No notifications yet.",
                        style: TextStyle(fontSize: 15, color: Colors.grey)),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final docSnap = docs[index];
                    final d = docSnap.data() as Map<String, dynamic>;
                    final ts = d['createdAt'] as Timestamp?;
                    final type = (d['type'] ?? 'general').toString();
                    final isUnread = d['read'] != true;

                    return Container(
                      color: isUnread ? Colors.indigo.shade50 : null,
                      child: ListTile(
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.indigo.shade100,
                              child: Icon(_iconFor(type), color: Colors.indigo),
                            ),
                            if (isUnread)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          d['title'] ?? '',
                          style: TextStyle(
                              fontWeight:
                                  isUnread ? FontWeight.bold : FontWeight.w500),
                        ),
                        subtitle: Text(d['body'] ?? ''),
                        trailing: ts != null
                            ? Text(
                                DateFormat('dd MMM, hh:mm a')
                                    .format(ts.toDate()),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              )
                            : null,
                        onTap: () {
                          if (isUnread) {
                            docSnap.reference
                                .update({'read': true}).catchError((_) {});
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
