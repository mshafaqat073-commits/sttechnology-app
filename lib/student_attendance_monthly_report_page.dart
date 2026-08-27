import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'class_section_service.dart';

/// Any class's attendance for a whole month — pick a class + a month and
/// see, for every student in that class, how many days they were
/// Present / Absent / on Leave that month (with a % attendance), plus a
/// printable PDF summary.
///
/// This complements student_attendance_report_page.dart (which is a
/// single-day snapshot across ALL classes) — this one is one class,
/// summarised across an entire month.
class StudentAttendanceMonthlyReportPage extends StatefulWidget {
  const StudentAttendanceMonthlyReportPage({super.key});

  @override
  State<StudentAttendanceMonthlyReportPage> createState() =>
      _StudentAttendanceMonthlyReportPageState();
}

class _StudentAttendanceMonthlyReportPageState
    extends State<StudentAttendanceMonthlyReportPage> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedClass;
  List<String> _classList = [];
  bool _loadingClasses = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final structure = await ClassSectionService.getAll();
    if (!mounted) return;
    setState(() {
      _classList = structure.classes;
      _loadingClasses = false;
      if (_classList.isNotEmpty) _selectedClass = _classList.first;
    });
  }

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

  // First and last day of _selectedMonth, formatted 'yyyy-MM-dd' — the
  // attendance docs store 'date' as this same string format, so a plain
  // lexicographic range query works correctly for a calendar month.
  String get _monthStartStr => DateFormat('yyyy-MM-dd')
      .format(DateTime(_selectedMonth.year, _selectedMonth.month, 1));
  String get _monthEndStr => DateFormat('yyyy-MM-dd')
      .format(DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0));

  // Fetches the class's students + this month's attendance docs, and
  // combines them into a per-student summary.
  Future<List<Map<String, dynamic>>> _loadMonthlyData() async {
    if (_selectedClass == null) return [];

    final results = await Future.wait([
      schoolCollection('students')
          .where('class', isEqualTo: _selectedClass)
          .where('status', isEqualTo: 'active')
          .get(),
      schoolCollection('attendance')
          .where('class', isEqualTo: _selectedClass)
          .where('date', isGreaterThanOrEqualTo: _monthStartStr)
          .where('date', isLessThanOrEqualTo: _monthEndStr)
          .get(),
    ]);

    final studentsSnap = results[0];
    final attendanceSnap = results[1];

    // studentId -> {present, absent, leave}
    Map<String, Map<String, int>> counts = {};
    for (var doc in attendanceSnap.docs) {
      var data = doc.data();
      String studentId = (data['studentId'] ?? '').toString();
      String status = (data['status'] ?? 'Present').toString();
      counts.putIfAbsent(
          studentId, () => {'Present': 0, 'Absent': 0, 'Leave': 0});
      if (counts[studentId]!.containsKey(status)) {
        counts[studentId]![status] = counts[studentId]![status]! + 1;
      }
    }

    List<Map<String, dynamic>> result = [];
    for (var doc in studentsSnap.docs) {
      var data = doc.data();
      String studentId = doc.id;
      var c = counts[studentId] ?? {'Present': 0, 'Absent': 0, 'Leave': 0};
      int marked = c['Present']! + c['Absent']! + c['Leave']!;
      double pct = marked > 0 ? (c['Present']! / marked) * 100 : 0;
      result.add({
        'name': data['name']?.toString() ?? 'N/A',
        'rollNo': data['rollNo']?.toString() ?? '',
        'present': c['Present']!,
        'absent': c['Absent']!,
        'leave': c['Leave']!,
        'marked': marked,
        'percent': pct,
      });
    }

    // Roll number ascending, fallback to name
    result.sort((a, b) {
      int ra = int.tryParse(a['rollNo'].toString()) ?? 999999;
      int rb = int.tryParse(b['rollNo'].toString()) ?? 999999;
      if (ra != rb) return ra.compareTo(rb);
      return a['name']
          .toString()
          .toLowerCase()
          .compareTo(b['name'].toString().toLowerCase());
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Class Attendance (Monthly)"),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Download/Print PDF",
            onPressed: _selectedClass == null
                ? null
                : () => _generateAndPrintPdf(context),
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
              border: Border.all(color: Colors.teal.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _loadingClasses
                          ? const LinearProgressIndicator()
                          : DropdownButtonFormField<String>(
                              initialValue: _selectedClass,
                              decoration: const InputDecoration(
                                  labelText: "Class",
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              items: _classList
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedClass = v),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Month: ${DateFormat('MMMM yyyy').format(_selectedMonth)}",
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal),
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
              ],
            ),
          ),
          Expanded(
            child: _selectedClass == null
                ? const Center(
                    child: Text("No class found. Add classes first."))
                : FutureBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey('$_selectedClass-$_selectedMonth'),
                    future: _loadMonthlyData(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final list = snapshot.data ?? [];
                      if (list.isEmpty) {
                        return const Center(
                            child: Text("No students found in this class."));
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
                                  s['rollNo'].toString().isEmpty
                                      ? "${index + 1}"
                                      : s['rollNo'].toString(),
                                  style: TextStyle(
                                      color: Colors.teal.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                              ),
                              title: Text(s['name'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  "Present: ${s['present']}  Absent: ${s['absent']}  Leave: ${s['leave']}  (Marked: ${s['marked']} day(s))"),
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
                  pw.Text("Class Attendance (Monthly)",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text("Class: $_selectedClass   |   Month: $monthLabel",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Roll', 'Name', 'Present', 'Absent', 'Leave', '%'],
              data: list
                  .map((s) => [
                        s['rollNo'].toString().isEmpty ? '-' : s['rollNo'],
                        s['name'],
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
      title: "Class Attendance Monthly Preview",
      shareFileName: "attendance_${_selectedClass}_$monthLabel.pdf",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
