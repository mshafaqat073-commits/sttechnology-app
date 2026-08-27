import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'performance_bar_chart.dart';
import 'teacher_performance_page.dart';

/// Admin > Reports > "Teachers Performance" — har staff member ki apni
/// attendance % + un ki assigned class(es) ka result avg % + remark, ek
/// list mein. Tap karne par wahi detail page khulta hai jo Teacher
/// Dashboard se "My Performance" par khulta hai — koi duplicate detail
/// page nahi banaya.
///
/// Data existing collections/fields se:
///   staff              (name, designation, assignedClasses/assignedClass)
///   teacher_attendance (teacherId, status)
///   results            (class, section, percentage)
class AdminTeacherPerformanceReportPage extends StatefulWidget {
  const AdminTeacherPerformanceReportPage({super.key});

  @override
  State<AdminTeacherPerformanceReportPage> createState() =>
      _AdminTeacherPerformanceReportPageState();
}

class _AdminTeacherPerformanceReportPageState
    extends State<AdminTeacherPerformanceReportPage> {
  late Future<List<_StaffPerformanceRow>> _future;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  List<Map<String, String>> _assignedClassesOf(Map<String, dynamic> data) {
    List<Map<String, String>> assignedClasses = [];
    if (data['assignedClasses'] is List) {
      assignedClasses = List<dynamic>.from(data['assignedClasses'] as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } else if (data['assignedClass'] != null) {
      assignedClasses = [
        {
          'class': data['assignedClass'].toString(),
          'section': data['assignedSection']?.toString() ?? '',
        }
      ];
    }
    return assignedClasses;
  }

  Future<List<_StaffPerformanceRow>> _load() async {
    final staffSnap = await schoolCollection('staff').get();
    final attendanceSnap = await schoolCollection('teacher_attendance').get();
    final resultsSnap = await schoolCollection('results').get();

    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        attendanceByTeacher = {};
    for (var d in attendanceSnap.docs) {
      final tid = (d.data())['teacherId']?.toString() ?? '';
      if (tid.isEmpty) continue;
      attendanceByTeacher.putIfAbsent(tid, () => []).add(d);
    }

    // class|section -> result docs, taake har staff ki assigned class(es)
    // ke sath jaldi match ho jaye.
    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        resultsByClassSection = {};
    for (var d in resultsSnap.docs) {
      final data = d.data();
      final cls = (data['class'] ?? '').toString();
      final sec = (data['section'] ?? '').toString().trim();
      resultsByClassSection.putIfAbsent('$cls|$sec', () => []).add(d);
      // Section-less bucket bhi, agar teacher ki assigned section khali ho
      resultsByClassSection.putIfAbsent('$cls|', () => []).add(d);
    }

    List<_StaffPerformanceRow> rows = [];
    for (var doc in staffSnap.docs) {
      final data = doc.data();
      final assignedClasses = _assignedClassesOf(data);

      final attendanceDocs = attendanceByTeacher[doc.id] ?? [];
      int present = 0;
      for (var a in attendanceDocs) {
        if ((a.data())['status']?.toString() == 'Present') present++;
      }
      final attendancePercent =
          attendanceDocs.isNotEmpty ? (present / attendanceDocs.length) * 100 : null;

      final Set<String> seenResultIds = {};
      List<QueryDocumentSnapshot<Map<String, dynamic>>> classResultDocs = [];
      for (var ac in assignedClasses) {
        final cls = ac['class'] ?? '';
        final sec = (ac['section'] ?? '').trim();
        if (cls.isEmpty) continue;
        final key = sec.isNotEmpty ? '$cls|$sec' : '$cls|';
        for (var d in (resultsByClassSection[key] ?? [])) {
          if (seenResultIds.add(d.id)) classResultDocs.add(d);
        }
      }

      double? avgResultPercent;
      if (classResultDocs.isNotEmpty) {
        double sum = 0;
        for (var r in classResultDocs) {
          sum += double.tryParse((r.data())['percentage']?.toString() ?? '0') ?? 0;
        }
        avgResultPercent = sum / classResultDocs.length;
      }

      rows.add(_StaffPerformanceRow(
        staffDocId: doc.id,
        name: (data['name'] ?? 'N/A').toString(),
        designation: (data['designation'] ?? 'Teacher').toString(),
        data: data,
        assignedClasses: assignedClasses,
        attendancePercent: attendancePercent,
        avgResultPercent: avgResultPercent,
      ));
    }

    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Teachers Performance"),
        backgroundColor: Colors.teal[800],
      ),
      body: FutureBuilder<List<_StaffPerformanceRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final rows = snapshot.data!;
          final filtered = _searchQuery.isEmpty
              ? rows
              : rows
                  .where((r) => r.name.toLowerCase().contains(_searchQuery))
                  .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search teacher/staff name...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.trim().toLowerCase()),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text("No staff found.",
                            style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _staffTile(context, filtered[index]);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _staffTile(BuildContext context, _StaffPerformanceRow r) {
    final remark = PerformanceRemark.overall(
      r.attendancePercent ?? 0,
      r.avgResultPercent ?? 0,
      hasAttendance: r.attendancePercent != null,
      hasResults: r.avgResultPercent != null,
    );
    final classLabel = r.assignedClasses.isEmpty
        ? "No class assigned"
        : r.assignedClasses
            .map((a) => (a['section'] ?? '').isNotEmpty
                ? "${a['class']} - ${a['section']}"
                : (a['class'] ?? ''))
            .join(", ");

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade100,
          child: Text(
            r.name.isNotEmpty ? r.name[0].toUpperCase() : "T",
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Colors.teal.shade800),
          ),
        ),
        title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${r.designation}  •  $classLabel"),
        isThreeLine: false,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(remark.icon, size: 14, color: remark.color),
                const SizedBox(width: 4),
                Text(
                  r.attendancePercent != null
                      ? "${r.attendancePercent!.toStringAsFixed(0)}% att"
                      : "No att.",
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: remark.color),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              r.avgResultPercent != null
                  ? "${r.avgResultPercent!.toStringAsFixed(0)}% class avg"
                  : "No result",
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TeacherPerformancePage(
                staffDocId: r.staffDocId,
                staffData: r.data,
                assignedClasses: r.assignedClasses,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StaffPerformanceRow {
  final String staffDocId;
  final String name;
  final String designation;
  final Map<String, dynamic> data;
  final List<Map<String, String>> assignedClasses;
  final double? attendancePercent;
  final double? avgResultPercent;

  _StaffPerformanceRow({
    required this.staffDocId,
    required this.name,
    required this.designation,
    required this.data,
    required this.assignedClasses,
    required this.attendancePercent,
    required this.avgResultPercent,
  });
}
