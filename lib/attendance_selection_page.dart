import 'package:flutter/material.dart';
//import 'package:cloud_firestore/cloud_firestore.dart';
import 'attendance_page.dart';
import 'school_context.dart';

class AttendanceSelectionPage extends StatefulWidget {
  const AttendanceSelectionPage({super.key});

  @override
  State<AttendanceSelectionPage> createState() =>
      _AttendanceSelectionPageState();
}

class _AttendanceSelectionPageState extends State<AttendanceSelectionPage> {
  // Summary variables for Students
  int totalStudentsCount = 0;
  int studentsPresent = 0;
  int studentsAbsent = 0;
  int studentsLeave = 0;

  // Summary variables for Teachers
  int totalTeachersCount = 0;
  int teachersPresent = 0;
  int teachersAbsent = 0;
  int teachersLeave = 0;

  bool _isLoading = true;
  String get formattedDate => DateTime.now().toString().split(' ')[0];

  @override
  void initState() {
    super.initState();
    _fetchOverallAttendanceSummary();
  }

  // Function to fetch the full summary data for today's date
  Future<void> _fetchOverallAttendanceSummary() async {
    try {
      // Previously a separate doc().get() call was made here for each
      // student/teacher (N+1 pattern) — for the whole school, this was
      // the heaviest query. Now students/teachers and their attendance
      // for today are fetched in just 4 queries, in parallel.
      final results = await Future.wait([
        schoolCollection('students').get(),
        schoolCollection('attendance')
            .where('date', isEqualTo: formattedDate)
            .get(),
        schoolCollection('staff').get(),
        schoolCollection('teacher_attendance')
            .where('date', isEqualTo: formattedDate)
            .get(),
      ]);
      var studentsSnapshot = results[0];
      var studentAttSnapshot = results[1];
      var teachersSnapshot = results[2];
      var teacherAttSnapshot = results[3];

      // 1. Students Attendance Summary (All Classes combined for today)
      int sTotal = studentsSnapshot.docs.length;
      int sPresent = 0;
      int sAbsent = 0;
      int sLeave = 0;

      Map<String, String> studentStatusById = {
        for (var doc in studentAttSnapshot.docs)
          (doc.data()['studentId'] as String? ?? doc.id):
              (doc.data()['status'] as String? ?? 'Present')
      };

      for (var doc in studentsSnapshot.docs) {
        String status = studentStatusById[doc.id] ?? 'Present';
        if (status == 'Present') {
          sPresent++;
        } else if (status == 'Absent') {
          sAbsent++;
        } else if (status == 'Leave') {
          sLeave++;
        }
      }

      // 2. Teachers Attendance Summary from 'staff' collection for today
      int tTotal = teachersSnapshot.docs.length;
      int tPresent = 0;
      int tAbsent = 0;
      int tLeave = 0;

      Map<String, String> teacherStatusById = {
        for (var doc in teacherAttSnapshot.docs)
          (doc.data()['teacherId'] as String? ?? doc.id):
              (doc.data()['status'] as String? ?? 'Present')
      };

      for (var doc in teachersSnapshot.docs) {
        String status = teacherStatusById[doc.id] ?? 'Present';
        if (status == 'Present') {
          tPresent++;
        } else if (status == 'Absent') {
          tAbsent++;
        } else if (status == 'Leave') {
          tLeave++;
        }
      }

      if (mounted) {
        setState(() {
          totalStudentsCount = sTotal;
          studentsPresent = sPresent;
          studentsAbsent = sAbsent;
          studentsLeave = sLeave;

          totalTeachersCount = tTotal;
          teachersPresent = tPresent;
          teachersAbsent = tAbsent;
          teachersLeave = tLeave;

          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching summary: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Attendance Type"),
        backgroundColor: Colors.teal[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- LOADING OR SUMMARY CARDS SECTION (above the Category text) ---
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // Students Summary Card (above the Students Button)
                      _buildSummaryCard(
                        title: "Students Today's Summary",
                        total: totalStudentsCount,
                        present: studentsPresent,
                        absent: studentsAbsent,
                        leave: studentsLeave,
                        cardColor: Colors.teal.shade50,
                        borderColor: Colors.teal.shade200,
                      ),
                      const SizedBox(height: 12),

                      // Teachers Summary Card (above the Teachers Button)
                      _buildSummaryCard(
                        title: "Teachers Today's Summary",
                        total: totalTeachersCount,
                        present: teachersPresent,
                        absent: teachersAbsent,
                        leave: teachersLeave,
                        cardColor: Colors.deepPurple.shade50,
                        borderColor: Colors.deepPurple.shade200,
                      ),
                    ],
                  ),

            const SizedBox(height: 20),
            const Text(
              "Please choose attendance category",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal),
            ),
            const SizedBox(height: 30),

            // Students Attendance Button (Opens Index 0)
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal[800],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.school, color: Colors.white, size: 28),
                label: const Text(
                  "Students Attendance",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const AttendancePage(initialTabIndex: 0)),
                  );
                  // Wapis anay par summary refresh ho jaye gi
                  _fetchOverallAttendanceSummary();
                },
              ),
            ),
            const SizedBox(height: 20),

            // Teacher Attendance Button (Opens Index 1)
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon:
                    const Icon(Icons.co_present, color: Colors.white, size: 28),
                label: const Text(
                  "Teacher Attendance",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const AttendancePage(initialTabIndex: 1)),
                  );
                  // Wapis anay par summary refresh ho jaye gi
                  _fetchOverallAttendanceSummary();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Summary Card Helper Widget
  Widget _buildSummaryCard({
    required String title,
    required int total,
    required int present,
    required int absent,
    required int leave,
    required Color cardColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87),
          ),
          const Divider(height: 10, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem("Total", total.toString(), Colors.blue),
              _summaryItem("Present", present.toString(), Colors.green),
              _summaryItem("Absent", absent.toString(), Colors.red),
              _summaryItem("Leave", leave.toString(), Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String count, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(count,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
