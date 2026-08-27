import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

// Read-only attendance history for one student, read straight from the
// same 'attendance' collection the admin's Student Attendance Report uses
// (fields: studentId, class, date [yyyy-MM-dd string], status).
class ParentAttendancePage extends StatelessWidget {
  final String studentId;
  final String studentName;

  const ParentAttendancePage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'Present':
        return Colors.green;
      case 'Absent':
        return Colors.red;
      case 'Leave':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Attendance - $studentName"),
        backgroundColor: Colors.indigo[700],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('attendance')
            .where('studentId', isEqualTo: studentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No attendance record found."));
          }

          docs.sort((a, b) {
            final da = (a.data() as Map)['date']?.toString() ?? '';
            final db = (b.data() as Map)['date']?.toString() ?? '';
            return db.compareTo(da); // latest first
          });

          int present = 0, absent = 0, leave = 0;
          for (var d in docs) {
            final status = (d.data() as Map)['status']?.toString() ?? '';
            if (status == 'Present') present++;
            if (status == 'Absent') absent++;
            if (status == 'Leave') leave++;
          }

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border.all(color: Colors.indigo.shade100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statChip("Present", present, Colors.green),
                    _statChip("Absent", absent, Colors.red),
                    _statChip("Leave", leave, Colors.orange),
                    _statChip("Total", docs.length, Colors.indigo),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final d = docs[index].data() as Map<String, dynamic>;
                    final status = d['status']?.toString() ?? 'N/A';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                          child: Icon(Icons.event, color: _statusColor(status)),
                        ),
                        title: Text(d['date']?.toString() ?? 'N/A'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                                color: _statusColor(status),
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Column(
      children: [
        Text("$count",
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}
