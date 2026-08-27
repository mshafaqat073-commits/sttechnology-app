import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';

/// Parent submits a leave application for their child here.
/// Admin approves/rejects it — the status keeps updating here in real time.
///
/// Firestore: schools/{schoolId}/leave_applications/{autoId}
///   studentId, studentName, className, section, fromDate, toDate,
///   reason, status, adminRemarks, createdAt, decidedAt
class ParentLeaveApplicationPage extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String className;
  final String section;

  const ParentLeaveApplicationPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.section,
  });

  @override
  State<ParentLeaveApplicationPage> createState() =>
      _ParentLeaveApplicationPageState();
}

class _ParentLeaveApplicationPageState
    extends State<ParentLeaveApplicationPage> {
  final _reasonController = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isSubmitting = false;

  final _fmt = DateFormat('dd-MM-yyyy');

  // Created ONCE here instead of inline in build(). If it were built inside
  // build(), every setState() (e.g. right after submit clears the form)
  // would hand StreamBuilder a brand-new Stream object, forcing it to drop
  // the old subscription and start over at ConnectionState.waiting — which
  // is exactly the "loading flashes once then gets stuck" symptom.
  late final Stream<QuerySnapshot> _applicationsStream;

  @override
  void initState() {
    super.initState();
    _applicationsStream = schoolCollection('leave_applications')
        .where('studentId', isEqualTo: widget.studentId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (_fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select both From and To dates!"),
          backgroundColor: Colors.red));
      return;
    }
    if (_toDate!.isBefore(_fromDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("To date cannot be before the From date!"),
          backgroundColor: Colors.red));
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please enter the reason for leave!"),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await schoolCollection('leave_applications').add({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'className': widget.className,
        'section': widget.section,
        'fromDate': _fmt.format(_fromDate!),
        'toDate': _fmt.format(_toDate!),
        'reason': _reasonController.text.trim(),
        'status': 'Pending',
        'adminRemarks': '',
        // NOTE: using Timestamp.now() (client time) instead of
        // FieldValue.serverTimestamp() on purpose. serverTimestamp()
        // resolves to null on the client until the server confirms it,
        // and since this collection is queried with orderBy('createdAt'),
        // the new document would briefly sort incorrectly (or drop out of
        // the ordered results) and then "pop back in" once the real
        // timestamp arrived — which is what looked like the item
        // "showing then getting deleted" right after submit.
        'createdAt': Timestamp.now(),
      });
      _reasonController.clear();
      setState(() {
        _fromDate = null;
        _toDate = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Leave application submitted successfully."),
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
      case 'Approved':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Leave Application"),
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
                  const Text("New Application",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(true),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(_fromDate == null
                              ? "From Date"
                              : _fmt.format(_fromDate!)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(false),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(_toDate == null
                              ? "To Date"
                              : _fmt.format(_toDate!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: "Reason for Leave",
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send),
                      label: const Text("Submit Application"),
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
              child: Text("Previous Applications",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _applicationsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  // Most common cause here: Firestore needs a composite
                  // index for a where() + orderBy() combo on different
                  // fields. Without this check the error was swallowed
                  // and the list just looked permanently stuck/empty.
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "Couldn't load applications:\n${snapshot.error}",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text("No applications found."));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final status = d['status'] ?? 'Pending';
                    return Card(
                      child: ListTile(
                        title: Text("${d['fromDate']} to ${d['toDate']}"),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d['reason'] ?? ''),
                            if ((d['adminRemarks'] ?? '')
                                .toString()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text("Remarks: ${d['adminRemarks']}",
                                    style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.teal)),
                              ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Chip(
                          label: Text(status,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
                          backgroundColor: _statusColor(status),
                        ),
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
