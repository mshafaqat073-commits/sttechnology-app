import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

/// Here the parent can submit a complaint to the Principal/Admin, and
/// can also view the status of their past complaints (Pending / In Review /
/// Resolved) along with the admin's reply.
///
/// Firestore: schools/{schoolId}/complaints/{autoId}
///   studentId, studentName, className, section, subject, message,
///   status, adminReply, createdAt, repliedAt
class ParentComplaintPage extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String className;
  final String section;

  const ParentComplaintPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.section,
  });

  @override
  State<ParentComplaintPage> createState() => _ParentComplaintPageState();
}

class _ParentComplaintPageState extends State<ParentComplaintPage> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitting = false;
  late final Stream<QuerySnapshot> _complaintsStream;

  @override
  void initState() {
    super.initState();
    _complaintsStream = schoolCollection('complaints')
        .where('studentId', isEqualTo: widget.studentId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _submitComplaint() async {
    if (_subjectController.text.trim().isEmpty ||
        _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Subject and complaint details are required!"),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await schoolCollection('complaints').add({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'className': widget.className,
        'section': widget.section,
        'subject': _subjectController.text.trim(),
        'message': _messageController.text.trim(),
        'status': 'Pending',
        'adminReply': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _subjectController.clear();
      _messageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Complaint has been sent to the Principal."),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Complaint to Principal"),
        backgroundColor: Colors.teal[800],
      ),
      body: SafeArea(child: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("New Complaint",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _subjectController,
                    decoration: const InputDecoration(
                        labelText: "Subject (e.g. Transport, Teacher, Fee)",
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: "Describe your complaint in detail",
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submitComplaint,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send),
                      label: const Text("Submit Complaint"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Previous Complaints",
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final status = d['status'] ?? 'Pending';
                    return Card(
                      child: ListTile(
                        title: Text(d['subject'] ?? ''),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d['message'] ?? ''),
                            if ((d['adminReply'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    "Principal's Reply: ${d['adminReply']}",
                                    style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.teal)),
                              ),
                          ],
                        ),
                        trailing: Chip(
                          label: Text(status,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
                          backgroundColor: _statusColor(status),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      )),
    );
  }
}
