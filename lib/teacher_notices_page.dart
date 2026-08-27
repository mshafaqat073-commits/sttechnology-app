import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

/// Notices page opened from the "Notices" tile on the teacher dashboard.
/// Shows both the general school notices and the teacher-only notices
/// as a plain list (read-only) — no scrolling ticker here.
class TeacherNoticesPage extends StatelessWidget {
  const TeacherNoticesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Notices"),
          backgroundColor: Colors.teal[800],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: "School Notices"),
              Tab(text: "For Teachers"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NoticeList(collection: 'notifications', accent: Colors.teal),
            _NoticeList(
                collection: 'teacher_notifications', accent: Colors.deepOrange),
          ],
        ),
      ),
    );
  }
}

class _NoticeList extends StatelessWidget {
  final String collection;
  final MaterialColor accent;

  const _NoticeList({required this.collection, required this.accent});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: schoolCollection(collection)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text("No notice available."));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final text = data['text'] as String? ?? '';
            final ts = data['createdAt'];
            String dateLabel = '';
            if (ts is Timestamp) {
              final d = ts.toDate();
              dateLabel = "${d.day}/${d.month}/${d.year}";
            }
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: Icon(Icons.campaign, color: accent),
                title: Text(text),
                subtitle: dateLabel.isNotEmpty ? Text(dateLabel) : null,
              ),
            );
          },
        );
      },
    );
  }
}
