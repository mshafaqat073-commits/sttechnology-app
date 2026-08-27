import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

// Read-only result history for one student, read straight from the same
// 'results' collection enter_result_page.dart writes to (fields:
// studentId, term, subjects [{subjectName, totalMarks, obtainedMarks}],
// grandTotal, grandObtained, percentage, grade, date).
class ParentResultPage extends StatelessWidget {
  final String studentId;
  final String studentName;

  const ParentResultPage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'A+':
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.blue;
      case 'C':
        return Colors.orange;
      case 'D':
        return Colors.deepOrange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Result - $studentName"),
        backgroundColor: Colors.indigo[700],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('results')
            .where('studentId', isEqualTo: studentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No result available yet."));
          }

          docs.sort((a, b) {
            final ta = (a.data() as Map)['date'] as Timestamp?;
            final tb = (b.data() as Map)['date'] as Timestamp?;
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta); // latest first
          });

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index].data() as Map<String, dynamic>;
              final grade = d['grade']?.toString() ?? 'N/A';
              final subjects = List<dynamic>.from(d['subjects'] ?? []);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(d['term']?.toString() ?? 'Result',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _gradeColor(grade).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text("Grade: $grade",
                                style: TextStyle(
                                    color: _gradeColor(grade),
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const Divider(),
                      ...subjects.map((s) {
                        final subj = Map<String, dynamic>.from(s as Map);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(subj['subjectName']?.toString() ?? ''),
                              Text(
                                  "${subj['obtainedMarks']} / ${subj['totalMarks']}"),
                            ],
                          ),
                        );
                      }),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              "Total: ${d['grandObtained']} / ${d['grandTotal']}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text("Percentage: ${d['percentage']}%",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
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
    );
  }
}
