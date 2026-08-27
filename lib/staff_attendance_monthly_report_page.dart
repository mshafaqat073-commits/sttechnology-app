import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

/// A whole month's attendance summary for every staff member — how many
/// days each teacher/staff was Present / Absent / on Leave in the
/// selected month, with a % attendance, plus a printable PDF.
///
/// Complements staff_attendance_report_page.dart (a single-day snapshot).
class StaffAttendanceMonthlyReportPage extends StatefulWidget {
  const StaffAttendanceMonthlyReportPage({super.key});

  @override
  State<StaffAttendanceMonthlyReportPage> createState() =>
      _StaffAttendanceMonthlyReportPageState();
}

class _StaffAttendanceMonthlyReportPageState
    extends State<StaffAttendanceMonthlyReportPage> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: "Pick any date in the month",
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
    }
  }

  String get _monthStartStr => DateFormat('yyyy-MM-dd')
      .format(DateTime(_selectedMonth.year, _selectedMonth.month, 1));
  String get _monthEndStr => DateFormat('yyyy-MM-dd')
      .format(DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0));

  Future<List<Map<String, dynamic>>> _loadMonthlyData() async {
    final results = await Future.wait([
      schoolCollection('staff').get(),
      schoolCollection('teacher_attendance')
          .where('date', isGreaterThanOrEqualTo: _monthStartStr)
          .where('date', isLessThanOrEqualTo: _monthEndStr)
          .get(),
    ]);

    final staffSnap = results[0];
    final attendanceSnap = results[1];

    // teacherId -> {present, absent, leave}
    Map<String, Map<String, int>> counts = {};
    for (var doc in attendanceSnap.docs) {
      var data = doc.data();
      String teacherId =
          (data['teacherId'] ?? data['staffId'] ?? '').toString();
      String status = (data['status'] ?? 'Present').toString();
      counts.putIfAbsent(
          teacherId, () => {'Present': 0, 'Absent': 0, 'Leave': 0});
      if (counts[teacherId]!.containsKey(status)) {
        counts[teacherId]![status] = counts[teacherId]![status]! + 1;
      }
    }

    List<Map<String, dynamic>> result = [];
    for (var doc in staffSnap.docs) {
      var data = doc.data();
      String staffId = doc.id;
      var c = counts[staffId] ?? {'Present': 0, 'Absent': 0, 'Leave': 0};
      int marked = c['Present']! + c['Absent']! + c['Leave']!;
      double pct = marked > 0 ? (c['Present']! / marked) * 100 : 0;
      String name = data['name']?.toString() ??
          data['staffName']?.toString() ??
          data['teacherName']?.toString() ??
          data['fullName']?.toString() ??
          'N/A';
      String role = data['role']?.toString() ??
          data['designation']?.toString() ??
          'Staff';
      result.add({
        'name': name,
        'role': role,
        'present': c['Present']!,
        'absent': c['Absent']!,
        'leave': c['Leave']!,
        'marked': marked,
        'percent': pct,
      });
    }

    result.sort((a, b) => a['name']
        .toString()
        .toLowerCase()
        .compareTo(b['name'].toString().toLowerCase()));

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Staff Attendance (Monthly)"),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Download/Print PDF",
            onPressed: () => _generateAndPrintPdf(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              border: Border.all(color: Colors.teal.shade200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Month: ${DateFormat('MMMM yyyy').format(_selectedMonth)}",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800]),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700),
                  icon: const Icon(Icons.calendar_month,
                      color: Colors.white, size: 18),
                  label: const Text("Change Month",
                      style: TextStyle(color: Colors.white)),
                  onPressed: _pickMonth,
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(_selectedMonth),
              future: _loadMonthlyData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return const Center(child: Text("No staff record found."));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final s = list[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade100,
                          child: Text(
                              s['name'].toString().isNotEmpty
                                  ? s['name'].toString()[0]
                                  : 'S',
                              style: TextStyle(
                                  color: Colors.teal[900],
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(s['name'],
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            "${s['role']}\nPresent: ${s['present']}  Absent: ${s['absent']}  Leave: ${s['leave']}  (Marked: ${s['marked']} day(s))"),
                        isThreeLine: true,
                        trailing: Text(
                          "${(s['percent'] as double).toStringAsFixed(0)}%",
                          style: TextStyle(
                              color: (s['percent'] as double) >= 75
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
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

  Future<void> _generateAndPrintPdf(BuildContext context) async {
    final list = await _loadMonthlyData();
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context ctx) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(currentSchoolDisplayName(),
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Staff Attendance (Monthly)",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text("Month: $monthLabel",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Name', 'Role', 'Present', 'Absent', 'Leave', '%'],
              data: list
                  .map((s) => [
                        s['name'],
                        s['role'],
                        s['present'].toString(),
                        s['absent'].toString(),
                        s['leave'].toString(),
                        "${(s['percent'] as double).toStringAsFixed(0)}%",
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
            ),
          ];
        },
      ),
    );

    if (!context.mounted) return;
    await showPdfPreviewPage(
      context,
      title: "Staff Attendance Monthly Preview",
      shareFileName: "staff_attendance_$monthLabel.pdf",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
