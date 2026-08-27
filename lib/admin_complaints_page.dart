import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'notification_helper.dart';

/// Here the Admin (Principal) can view all parents' complaints, reply to
/// them, and update the status (Pending / In Review / Resolved).
/// A notification is sent to the student when a reply is given.
class AdminComplaintsPage extends StatefulWidget {
  const AdminComplaintsPage({super.key});

  @override
  State<AdminComplaintsPage> createState() => _AdminComplaintsPageState();
}

class _AdminComplaintsPageState extends State<AdminComplaintsPage> {
  String _filter = 'All';
  late Stream<QuerySnapshot> _complaintsStream;

  @override
  void initState() {
    super.initState();
    _complaintsStream = _buildQuery(_filter).snapshots();
  }

  Query _buildQuery(String filter) {
    Query query =
        schoolCollection('complaints').orderBy('createdAt', descending: true);
    if (filter != 'All') {
      query = query.where('status', isEqualTo: filter);
    }
    return query;
  }

  void _setFilter(String filter) {
    setState(() {
      _filter = filter;
      // Only build a new stream when the filter actually changes,
      // so the StreamBuilder doesn't reload/flicker on every rebuild.
      _complaintsStream = _buildQuery(filter).snapshots();
    });
  }

  Future<void> _deleteComplaint(DocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Complaint?"),
        content: Text(
            "Are you sure you want to delete this complaint from ${d['studentName'] ?? 'this student'}? This cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Complaint deleted."),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Resolved':
        return Colors.green;
      case 'In Review':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Future<void> _openComplaint(DocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final replyController = TextEditingController(text: d['adminReply'] ?? '');
    String status = d['status'] ?? 'Pending';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(d['subject'] ?? 'Complaint'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Student: ${d['studentName']} (${d['className']} ${d['section']})"),
                const SizedBox(height: 8),
                Text(d['message'] ?? ''),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: "Status"),
                  items: const [
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                    DropdownMenuItem(
                        value: 'In Review', child: Text('In Review')),
                    DropdownMenuItem(
                        value: 'Resolved', child: Text('Resolved')),
                  ],
                  onChanged: (v) => setDialogState(() => status = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: replyController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: "Reply (visible to parent)",
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                await doc.reference.update({
                  'status': status,
                  'adminReply': replyController.text.trim(),
                  'repliedAt': FieldValue.serverTimestamp(),
                });
                try {
                  final studentDoc = await schoolCollection('students')
                      .doc(d['studentId'])
                      .get();
                  await NotificationHelper.sendToUser(
                    toId: d['studentId'],
                    toRole: 'student',
                    title: 'Complaint Update: $status',
                    body: replyController.text.trim().isNotEmpty
                        ? replyController.text.trim()
                        : 'The status of your complaint has been updated.',
                    type: 'complaint',
                    fcmToken: studentDoc.data()?['fcmToken'],
                  );
                } catch (_) {}
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Parents Complaints"),
        backgroundColor: Colors.teal[800],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 8,
              children: ['All', 'Pending', 'In Review', 'Resolved']
                  .map((s) => ChoiceChip(
                        label: Text(s),
                        selected: _filter == s,
                        onSelected: (_) => _setFilter(s),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _complaintsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text("Error: ${snapshot.error}",
                        textAlign: TextAlign.center),
                  ));
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text("No complaints yet."));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data() as Map<String, dynamic>;
                    final status = d['status'] ?? 'Pending';
                    return Card(
                      margin:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(d['subject'] ?? ''),
                        subtitle: Text(
                            "${d['studentName']} (${d['className']} ${d['section']})\n${d['message'] ?? ''}",
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(status,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11)),
                              backgroundColor: _statusColor(status),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: "Delete",
                              onPressed: () => _deleteComplaint(doc),
                            ),
                          ],
                        ),
                        onTap: () => _openComplaint(doc),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
