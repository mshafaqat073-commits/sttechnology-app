import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'performance_bar_chart.dart';

/// "My Performance" page — Teacher Dashboard se khulta hai. Do cheezein
/// dikhata hai (dono hi already app me maujood collections se, koi naya
/// field/collection nahi banaya):
///   - Teacher ki apni attendance -> 'teacher_attendance' (teacherId, date, status)
///   - Us ki assigned class(es) ka result -> 'results' (class, section, percentage, grade, term, date)
/// Aur inhi do se combine karke overall remarks + graphs bana deta hai.
class TeacherPerformancePage extends StatefulWidget {
  final String staffDocId;
  final Map<String, dynamic> staffData;
  final List<Map<String, String>> assignedClasses;

  const TeacherPerformancePage({
    super.key,
    required this.staffDocId,
    required this.staffData,
    required this.assignedClasses,
  });

  @override
  State<TeacherPerformancePage> createState() =>
      _TeacherPerformancePageState();
}

class _TeacherPerformancePageState extends State<TeacherPerformancePage> {
  late Future<_TeacherPerformanceBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<_TeacherPerformanceBundle> _load() async {
    final attendanceSnap = await schoolCollection('teacher_attendance')
        .where('teacherId', isEqualTo: widget.staffDocId)
        .get();

    // Har assigned class-section combination ke liye alag query — Firestore
    // compound OR aasani se support nahi karta, isliye parallel queries
    // chala kar client-side merge karte hain.
    List<QueryDocumentSnapshot<Map<String, dynamic>>> resultDocs = [];
    if (widget.assignedClasses.isNotEmpty) {
      List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];
      for (var ac in widget.assignedClasses) {
        final cls = ac['class'] ?? '';
        final sec = (ac['section'] ?? '').trim();
        if (cls.isEmpty) continue;
        Query<Map<String, dynamic>> q =
            schoolCollection('results').where('class', isEqualTo: cls);
        if (sec.isNotEmpty) {
          q = q.where('section', isEqualTo: sec);
        }
        futures.add(q.get());
      }
      final snaps = await Future.wait(futures);
      final seen = <String>{};
      for (var snap in snaps) {
        for (var doc in snap.docs) {
          if (seen.add(doc.id)) resultDocs.add(doc);
        }
      }
    }

    return _TeacherPerformanceBundle(
      attendance: attendanceSnap.docs,
      results: resultDocs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.staffData['name'] ?? 'Teacher').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Performance"),
        backgroundColor: Colors.teal[800],
      ),
      body: FutureBuilder<_TeacherPerformanceBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final bundle = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(name),
                  const SizedBox(height: 18),
                  _sectionTitle("My Attendance"),
                  _buildAttendanceSection(bundle),
                  const SizedBox(height: 22),
                  _sectionTitle("My Class(es) Result Performance"),
                  _buildResultSection(bundle),
                  const SizedBox(height: 22),
                  _sectionTitle("Overall Remarks"),
                  const SizedBox(height: 8),
                  _buildRemarks(bundle),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );

  Widget _buildHeader(String name) {
    final designation = (widget.staffData['designation'] ?? 'Teacher').toString();
    final classLabel = widget.assignedClasses.isEmpty
        ? "No class assigned"
        : widget.assignedClasses
            .map((a) => (a['section'] ?? '').isNotEmpty
                ? "${a['class']} - ${a['section']}"
                : (a['class'] ?? ''))
            .join(", ");

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.teal.shade100,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : "T",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade800),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(designation, style: TextStyle(color: Colors.grey.shade700)),
                  Text(classLabel,
                      style: TextStyle(
                          color: Colors.teal.shade800,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Attendance ----------------

  Widget _buildAttendanceSection(_TeacherPerformanceBundle bundle) {
    final docs = List.of(bundle.attendance)
      ..sort((a, b) {
        final da = (a.data())['date']?.toString() ?? '';
        final db = (b.data())['date']?.toString() ?? '';
        return db.compareTo(da);
      });

    int present = 0, absent = 0, leave = 0;
    for (var d in docs) {
      final status = (d.data())['status']?.toString() ?? '';
      if (status == 'Present') present++;
      if (status == 'Absent') absent++;
      if (status == 'Leave') leave++;
    }
    final total = docs.length;
    final attendancePercent = total > 0 ? (present / total) * 100 : 0.0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (total > 0)
              PerformanceMeter(
                label: "Present Rate",
                percentage: attendancePercent,
                color: Colors.teal,
              )
            else
              const Text("No attendance record found yet.",
                  style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statChip("Present", present, Colors.green),
                _statChip("Absent", absent, Colors.red),
                _statChip("Leave", leave, Colors.orange),
                _statChip("Total Days", total, Colors.teal),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 14),
              PerformanceBarChart(
                maxValue: total.toDouble(),
                bars: [
                  PerformanceBarData(
                      label: "Present", value: present.toDouble(), color: Colors.green),
                  PerformanceBarData(
                      label: "Absent", value: absent.toDouble(), color: Colors.red),
                  PerformanceBarData(
                      label: "Leave", value: leave.toDouble(), color: Colors.orange),
                ],
              ),
            ],
          ],
        ),
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

  // ---------------- Class Results ----------------

  Widget _buildResultSection(_TeacherPerformanceBundle bundle) {
    if (widget.assignedClasses.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text("No class assigned — contact administration.",
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final docs = bundle.results;
    if (docs.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text("No result entered for your class(es) yet.",
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    // Term ke hisab se average percentage (chart ke liye)
    final Map<String, List<double>> byTerm = {};
    double sumPct = 0;
    final Map<String, int> gradeCount = {};
    final Set<String> studentIds = {};

    for (var d in docs) {
      final data = d.data();
      final pct = double.tryParse(data['percentage']?.toString() ?? '0') ?? 0;
      final term = (data['term'] ?? 'N/A').toString();
      final grade = (data['grade'] ?? 'N/A').toString();
      final sid = (data['studentId'] ?? '').toString();
      byTerm.putIfAbsent(term, () => []).add(pct);
      sumPct += pct;
      gradeCount[grade] = (gradeCount[grade] ?? 0) + 1;
      if (sid.isNotEmpty) studentIds.add(sid);
    }

    final avgPct = docs.isNotEmpty ? sumPct / docs.length : 0.0;

    final termBars = byTerm.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return PerformanceBarData(label: e.key, value: avg, color: Colors.deepPurple);
    }).toList();

    final gradeColors = <String, Color>{
      'A+': Colors.green,
      'A': Colors.green,
      'B': Colors.blue,
      'C': Colors.orange,
      'D': Colors.deepOrange,
      'F': Colors.red,
    };
    final gradeBars = gradeCount.entries.map((e) {
      return PerformanceBarData(
        label: e.key,
        value: e.value.toDouble(),
        color: gradeColors[e.key] ?? Colors.grey,
      );
    }).toList();

    return Column(
      children: [
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text("${avgPct.toStringAsFixed(1)}%",
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple)),
                    const Text("Class Avg %", style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  children: [
                    Text("${studentIds.length}",
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal)),
                    const Text("Students", style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  children: [
                    Text("${docs.length}",
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo)),
                    const Text("Results Entered", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Average % by Term",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                PerformanceBarChart(maxValue: 100, bars: termBars, valueSuffix: '%'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Grade Distribution",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                PerformanceBarChart(bars: gradeBars),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- Remarks ----------------

  Widget _buildRemarks(_TeacherPerformanceBundle bundle) {
    int present = 0;
    for (var d in bundle.attendance) {
      if ((d.data())['status']?.toString() == 'Present') present++;
    }
    final totalAttendance = bundle.attendance.length;
    final attendancePercent =
        totalAttendance > 0 ? (present / totalAttendance) * 100 : 0.0;

    double avgPct = 0;
    if (bundle.results.isNotEmpty) {
      double sum = 0;
      for (var d in bundle.results) {
        sum += double.tryParse((d.data())['percentage']?.toString() ?? '0') ?? 0;
      }
      avgPct = sum / bundle.results.length;
    }

    final overall = PerformanceRemark.overall(
      attendancePercent,
      avgPct,
      hasResults: bundle.results.isNotEmpty,
      hasAttendance: totalAttendance > 0,
    );

    List<String> subRemarks = [];
    if (totalAttendance > 0) {
      subRemarks.add(
          "${PerformanceRemark.attendanceRemark(attendancePercent).text} (${attendancePercent.toStringAsFixed(1)}% present)");
    }
    if (bundle.results.isNotEmpty) {
      final classRemark = PerformanceRemark.band(
        avgPct,
        excellent: "Class performing excellently",
        good: "Class performing well",
        average: "Class performance is average — needs improvement",
        weak: "Class performance is weak — needs focused attention",
      );
      subRemarks.add(
          "${classRemark.text} (avg ${avgPct.toStringAsFixed(1)}%)");
    }

    return PerformanceRemarkCard(remark: overall, subRemarks: subRemarks);
  }
}

class _TeacherPerformanceBundle {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> attendance;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> results;

  _TeacherPerformanceBundle({
    required this.attendance,
    required this.results,
  });
}
