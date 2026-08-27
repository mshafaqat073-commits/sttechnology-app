import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'school_context.dart';

/// Parents can view their child's online classes here, and tapping
/// "Join" opens the meeting link.
class ParentOnlineClassesPage extends StatelessWidget {
  final String className;
  final String section;

  const ParentOnlineClassesPage(
      {super.key, required this.className, required this.section});

  Future<void> _joinLink(BuildContext context, String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Could not open the link."), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd-MM-yyyy hh:mm a');
    return Scaffold(
      appBar: AppBar(
        title: const Text("Online Classes"),
        backgroundColor: Colors.teal[800],
      ),
      // NOTE: deliberately no .orderBy('scheduledAt') combined with the
      // className equality filter here — that combination needs a
      // composite Firestore index. If that index isn't created in the
      // Firebase Console, the query throws and (since the error wasn't
      // being checked) this page just silently showed "No online classes
      // yet." even when classes existed. Sorting is done client-side
      // below instead, so no composite index is required at all.
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('online_classes')
            .where('className', isEqualTo: className)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Could not load online classes.\n${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          final docs = (snapshot.data?.docs ?? []).where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final sec = (d['section'] ?? '').toString().trim();
            return sec.isEmpty || sec == section;
          }).toList()
            ..sort((a, b) {
              final da = a.data() as Map<String, dynamic>;
              final db = b.data() as Map<String, dynamic>;
              final ta = (da['scheduledAt'] as Timestamp?)?.toDate();
              final tb = (db['scheduledAt'] as Timestamp?)?.toDate();
              if (ta == null || tb == null) return 0;
              return tb.compareTo(ta); // descending
            });
          if (docs.isEmpty) {
            return const Center(child: Text("No online classes yet."));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final ts = (d['scheduledAt'] as Timestamp?)?.toDate();
              final isPast =
                  ts != null && ts.isBefore(DateTime.now().subtract(const Duration(hours: 2)));
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.video_camera_front, color: Colors.teal),
                  title: Text(d['title'] ?? ''),
                  subtitle: Text(
                      "${d['subject'] ?? ''} • ${d['platform']}\n"
                      "${ts != null ? fmt.format(ts) : ''}"),
                  isThreeLine: true,
                  trailing: ElevatedButton(
                    onPressed: isPast ? null : () => _joinLink(context, d['link'] ?? ''),
                    child: const Text("Join"),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
