import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'notification_helper.dart';

/// Admin views all parents' leave applications here and can
/// Approve/Reject them (with remarks). As soon as a decision is made,
/// a notification is sent to the student.
class AdminLeaveApplicationsPage extends StatefulWidget {
  const AdminLeaveApplicationsPage({super.key});

  @override
  State<AdminLeaveApplicationsPage> createState() =>
      _AdminLeaveApplicationsPageState();
}

class _AdminLeaveApplicationsPageState
    extends State<AdminLeaveApplicationsPage> {
  String _filter = 'Pending';

  Color _statusColor(String status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _decide(DocumentSnapshot doc, String decision) async {
    final d = doc.data() as Map<String, dynamic>;
    final remarksController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$decision Application"),
        content: TextField(
          controller: remarksController,
          decoration: const InputDecoration(
              labelText: "Remarks (optional)", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(decision)),
        ],
      ),
    );

    if (confirmed != true) return;

    await doc.reference.update({
      'status': decision == 'Approve' ? 'Approved' : 'Rejected',
      'adminRemarks': remarksController.text.trim(),
      'decidedAt': FieldValue.serverTimestamp(),
    });

    try {
      final studentDoc =
          await schoolCollection('students').doc(d['studentId']).get();
      await NotificationHelper.sendToUser(
        toId: d['studentId'],
        toRole: 'student',
        title: 'Leave Application ${decision == 'Approve' ? 'Approved' : 'Rejected'}',
        body: 'Your leave application from ${d['fromDate']} to ${d['toDate']} '
            'has been ${decision == 'Approve' ? 'approved' : 'rejected'}.',
        type: 'leave',
        fcmToken: studentDoc.data()?['fcmToken'],
      );
    } catch (_) {}
  }

  Future<void> _deleteApplication(DocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Application?"),
        content: Text(
            "Are you sure you want to delete the leave application from ${d['studentName'] ?? 'this student'}? This cannot be undone."),
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
              content: Text("Application deleted."),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Query query = schoolCollection('leave_applications')
        .orderBy('createdAt', descending: true);
    if (_filter != 'All') {
      query = query.where('status', isEqualTo: _filter);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Leave Applications"),
        backgroundColor: Colors.teal[800],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 8,
              children: ['All', 'Pending', 'Approved', 'Rejected']
                  .map((s) => ChoiceChip(
                        label: Text(s),
                        selected: _filter == s,
                        onSelected: (_) => setState(() => _filter = s),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text("No applications found."));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data() as Map<String, dynamic>;
                    final status = d['status'] ?? 'Pending';
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                      "${d['studentName']} (${d['className']} ${d['section']})",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
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
                                  onPressed: () => _deleteApplication(doc),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text("${d['fromDate']} to ${d['toDate']}"),
                            Text(d['reason'] ?? '',
                                style: const TextStyle(color: Colors.black54)),
                            if (status == 'Pending')
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _decide(doc, 'Reject'),
                                    icon: const Icon(Icons.close,
                                        color: Colors.red),
                                    label: const Text("Reject",
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _decide(doc, 'Approve'),
                                    icon: const Icon(Icons.check),
                                    label: const Text("Approve"),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white),
                                  ),
                                ],
                              ),
                          ],
                        ),
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
