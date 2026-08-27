import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_ticker_widget.dart' show showAddNotificationDialog;
import 'notification_helper.dart';
import 'school_context.dart';

/// ============================================================
/// TEACHER-ONLY NOTIFICATIONS (admin side)
/// ============================================================
/// Ye general "notifications" collection se ALAG collection use
/// karta hai ('teacher_notifications'), taake ye sirf teacher
/// dashboard par dikhe — parents ya general public ticker par
/// kabhi nahi aayega.
///
/// USAGE (admin dashboard AppBar mein):
///
///   IconButton(
///     icon: const Icon(Icons.groups_2, color: Colors.yellowAccent),
///     tooltip: "Teacher Notifications",
///     onPressed: () {
///       Navigator.push(context, MaterialPageRoute(
///         builder: (context) => const ManageTeacherNotificationsPage(),
///       ));
///     },
///   ),
/// ============================================================
class ManageTeacherNotificationsPage extends StatelessWidget {
  const ManageTeacherNotificationsPage({super.key});

  CollectionReference get _collection =>
      schoolCollection('teacher_notifications');

  Future<void> _addNotification(BuildContext context) async {
    final text = await showAddNotificationDialog(
      context,
      title: "New Teacher Notification",
    );
    if (text != null && text.trim().isNotEmpty) {
      await _collection.add({
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Bell icon (Teacher Dashboard, top-right) reads from
      // 'push_notifications' with read/unread tracking — the ticker
      // write above alone doesn't reach it. Fan this notice out to every
      // teacher so it shows up there too, and sends an actual push.
      try {
        final staffSnap = await schoolCollection('staff').get();
        final targets = staffSnap.docs
            .map((d) => {
                  'id': d.id,
                  'token': (d.data())['fcmToken'] as String?,
                })
            .toList();
        await NotificationHelper.sendToMultiple(
          targets: targets,
          toRole: 'teacher',
          title: 'School Notice',
          body: text.trim(),
          type: 'general',
        );
      } catch (_) {}
    }
  }

  Future<void> _editNotification(
      BuildContext context, String id, String currentText) async {
    final text = await showAddNotificationDialog(
      context,
      initialText: currentText,
      title: "Edit Teacher Notification",
      confirmLabel: "Update",
    );
    if (text != null && text.trim().isNotEmpty) {
      await _collection.doc(id).update({'text': text.trim()});
    }
  }

  Future<void> _deleteNotification(BuildContext context, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Notification?"),
        content:
            const Text("This will remove it from the teacher notice ticker."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _collection.doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Teacher Notifications"),
        backgroundColor: Colors.deepOrange[800],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _collection.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No teacher notifications yet.\nTap + to add one.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final text =
                  (doc.data() as Map<String, dynamic>)['text'] as String? ?? '';
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: const Icon(Icons.groups_2, color: Colors.deepOrange),
                  title: Text(text),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blueGrey),
                        onPressed: () =>
                            _editNotification(context, doc.id, text),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteNotification(context, doc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepOrange[800],
        onPressed: () => _addNotification(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
