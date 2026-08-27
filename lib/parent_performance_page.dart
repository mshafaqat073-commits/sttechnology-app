import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'performance_bar_chart.dart';

/// "Overall Performance" button ka page — Parent Dashboard se ek bache ke
/// child-menu me khulta hai. Teen collections se live data uthata hai
/// (koi naya collection/field nahi banaya — jo already app me use ho raha
/// hai wahi read kiya hai):
///   - results        (studentId, term, percentage, grade, date)
///   - attendance     (studentId, date, status)
///   - fee_history    (studentId, date, amountPaid)
/// Aur inhi teeno se combine karke ek graph + remarks bana deta hai.
class ParentPerformancePage extends StatefulWidget {
  final String studentId;
  final String studentName;
  final Map<String, dynamic> studentData;

  const ParentPerformancePage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.studentData,
  });

  @override
  State<ParentPerformancePage> createState() => _ParentPerformancePageState();
}

class _ParentPerformancePageState extends State<ParentPerformancePage> {
  late Future<_PerformanceBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<_PerformanceBundle> _load() async {
    final results = await schoolCollection('results')
        .where('studentId', isEqualTo: widget.studentId)
        .get();
    final attendance = await schoolCollection('attendance')
        .where('studentId', isEqualTo: widget.studentId)
        .get();
    final feeHistory = await schoolCollection('fee_history')
        .where('studentId', isEqualTo: widget.studentId)
        .get();

    return _PerformanceBundle(
      results: results.docs,
      attendance: attendance.docs,
      feeHistory: feeHistory.docs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Performance - ${widget.studentName}"),
        backgroundColor: Colors.indigo[700],
      ),
      body: FutureBuilder<_PerformanceBundle>(
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
                  _buildHeader(bundle),
                  const SizedBox(height: 18),
                  _sectionTitle("Attendance"),
                  _buildAttendanceSection(bundle),
                  const SizedBox(height: 22),
                  _sectionTitle("Result History"),
                  _buildResultSection(bundle),
                  const SizedBox(height: 22),
                  _sectionTitle("Fee Payment History"),
                  _buildFeeSection(bundle),
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

  Widget _buildHeader(_PerformanceBundle bundle) {
    final className = (widget.studentData['class'] ?? 'N/A').toString();
    final section = (widget.studentData['section'] ?? '').toString().trim();
    final imageUrl = (widget.studentData['imageUrl'] ?? '').toString();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.indigo.shade100,
              backgroundImage:
                  imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
              child:
                  imageUrl.isEmpty ? const Icon(Icons.person, color: Colors.indigo) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.studentName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    section.isNotEmpty
                        ? "Class: $className - $section"
                        : "Class: $className",
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Attendance ----------------

  Widget _buildAttendanceSection(_PerformanceBundle bundle) {
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
                color: Colors.indigo,
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
                _statChip("Total Days", total, Colors.indigo),
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

  // ---------------- Results ----------------

  Widget _buildResultSection(_PerformanceBundle bundle) {
    final docs = List.of(bundle.results)
      ..sort((a, b) {
        final ta = (a.data())['date'] as Timestamp?;
        final tb = (b.data())['date'] as Timestamp?;
        if (ta == null || tb == null) return 0;
        return tb.compareTo(ta); // latest first
      });

    if (docs.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text("No result available yet.",
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    // Chart chronological order (oldest -> newest) taake trend samajh aaye.
    final chronological = List.of(docs.reversed);
    final chartBars = chronological.map((d) {
      final data = d.data();
      final pct = double.tryParse(data['percentage']?.toString() ?? '0') ?? 0;
      final term = (data['term'] ?? 'N/A').toString();
      return PerformanceBarData(label: term, value: pct, color: Colors.deepPurple);
    }).toList();

    return Column(
      children: [
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Percentage Trend",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                PerformanceBarChart(
                    maxValue: 100, bars: chartBars, valueSuffix: '%'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...docs.map((d) {
          final data = d.data();
          final grade = data['grade']?.toString() ?? 'N/A';
          String formattedDate = "N/A";
          if (data['date'] != null) {
            formattedDate =
                DateFormat('dd-MM-yyyy').format((data['date'] as Timestamp).toDate());
          }
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              leading: const Icon(Icons.analytics, color: Colors.deepPurple),
              title: Text(data['term']?.toString() ?? 'Result',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Date: $formattedDate  •  Grade: $grade"),
              trailing: Text("${data['percentage']}%",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            ),
          );
        }),
      ],
    );
  }

  // ---------------- Fee ----------------

  Widget _buildFeeSection(_PerformanceBundle bundle) {
    final docs = List.of(bundle.feeHistory)
      ..sort((a, b) {
        final ta = (a.data())['date'] as Timestamp?;
        final tb = (b.data())['date'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

    double totalPaid = 0;
    for (var d in docs) {
      totalPaid += ((d.data())['amountPaid'] ?? 0).toDouble();
    }
    double dues =
        double.tryParse(widget.studentData['dues']?.toString() ?? '0') ?? 0;

    if (docs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("No payment record found.",
                  style: TextStyle(color: Colors.grey)),
              if (dues > 0) ...[
                const SizedBox(height: 6),
                Text("Current Dues: Rs. ${dues.toStringAsFixed(0)}",
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
        ),
      );
    }

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
                    Text("Rs. ${totalPaid.toStringAsFixed(0)}",
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                    const Text("Total Paid", style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  children: [
                    Text("Rs. ${dues.toStringAsFixed(0)}",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: dues > 0 ? Colors.red : Colors.green)),
                    const Text("Current Dues", style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  children: [
                    Text("${docs.length}",
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo)),
                    const Text("Payments", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...docs.map((d) {
          final data = d.data();
          double paid = (data['amountPaid'] ?? 0).toDouble();
          String formattedDate = "N/A";
          if (data['date'] != null) {
            formattedDate = DateFormat('dd-MM-yyyy')
                .format((data['date'] as Timestamp).toDate());
          }
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.teal),
              title: Text("Rs. ${paid.toStringAsFixed(0)} Paid",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Date: $formattedDate"),
            ),
          );
        }),
      ],
    );
  }

  // ---------------- Remarks ----------------

  Widget _buildRemarks(_PerformanceBundle bundle) {
    final attendanceDocs = bundle.attendance;
    int present = 0;
    for (var d in attendanceDocs) {
      if ((d.data())['status']?.toString() == 'Present') present++;
    }
    final totalAttendance = attendanceDocs.length;
    final attendancePercent =
        totalAttendance > 0 ? (present / totalAttendance) * 100 : 0.0;

    final resultDocs = bundle.results;
    double avgPercentage = 0;
    if (resultDocs.isNotEmpty) {
      double sum = 0;
      for (var d in resultDocs) {
        sum += double.tryParse((d.data())['percentage']?.toString() ?? '0') ?? 0;
      }
      avgPercentage = sum / resultDocs.length;
    }

    final overall = PerformanceRemark.overall(
      attendancePercent,
      avgPercentage,
      hasResults: resultDocs.isNotEmpty,
      hasAttendance: totalAttendance > 0,
    );

    List<String> subRemarks = [];
    if (totalAttendance > 0) {
      subRemarks.add(
          "${PerformanceRemark.attendanceRemark(attendancePercent).text} (${attendancePercent.toStringAsFixed(1)}% present)");
    }
    if (resultDocs.isNotEmpty) {
      subRemarks.add(
          "${PerformanceRemark.academicRemark(avgPercentage).text} (avg ${avgPercentage.toStringAsFixed(1)}%)");
    }

    return PerformanceRemarkCard(remark: overall, subRemarks: subRemarks);
  }
}

class _PerformanceBundle {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> results;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> attendance;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> feeHistory;

  _PerformanceBundle({
    required this.results,
    required this.attendance,
    required this.feeHistory,
  });
}
