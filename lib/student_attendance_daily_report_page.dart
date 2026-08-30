import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'class_section_service.dart';

/// Any class's attendance for a single selected date — pick a class and a
/// date and see, for every student in that class, whether they were
/// Present / Absent / on Leave / Not Marked on that date, plus a
/// printable PDF summary.
///
/// This complements student_attendance_monthly_report_page.dart (which
/// summarises one class across an entire month) — this one is one class,
/// snapshotted on a single chosen date.
class StudentAttendanceDailyReportPage extends StatefulWidget {
  const StudentAttendanceDailyReportPage({super.key});

  @override
  State<StudentAttendanceDailyReportPage> createState() =>
      _StudentAttendanceDailyReportPageState();
}

class _StudentAttendanceDailyReportPageState
    extends State<StudentAttendanceDailyReportPage> {
  DateTime _selectedDate = DateTime.now();
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: "Pick a date",
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // _selectedDate formatted 'yyyy-MM-dd' — the attendance docs store
  // 'date' as this same string format, so an equality query works
  // correctly for a single calendar day.
  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  // Fetches the class's students + this date's attendance docs, and
  // combines them into a per-student status for that day.
  Future<List<Map<String, dynamic>>> _loadDailyData() async {
    if (_selectedClass == null) return [];

    final results = await Future.wait([
      schoolCollection('students')
          .where('class', isEqualTo: _selectedClass)
          .where('status', isEqualTo: 'active')
          .get(),
      schoolCollection('attendance')
          .where('class', isEqualTo: _selectedClass)
          .where('date', isEqualTo: _dateStr)
          .get(),
    ]);

    final studentsSnap = results[0];
    final attendanceSnap = results[1];

    // studentId -> status
    Map<String, String> statusByStudent = {};
    for (var doc in attendanceSnap.docs) {
      var data = doc.data();
      String studentId = (data['studentId'] ?? '').toString();
      String status = (data['status'] ?? 'Present').toString();
      statusByStudent[studentId] = status;
    }

    List<Map<String, dynamic>> result = [];
    for (var doc in studentsSnap.docs) {
      var data = doc.data();
      String studentId = doc.id;
      String status = statusByStudent[studentId] ?? 'Not Marked';
      result.add({
        'name': data['name']?.toString() ?? 'N/A',
        'rollNo': data['rollNo']?.toString() ?? '',
        'status': status,
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
        title: const Text("Student Attendance Daily"),
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
                      "Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}",
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
                      label: const Text("Change Date",
                          style: TextStyle(color: Colors.white)),
                      onPressed: _pickDate,
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
                    key: ValueKey('$_selectedClass-$_dateStr'),
                    future: _loadDailyData(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      // Same fix as the monthly report page: surface real
                      // Firestore errors (e.g. a missing composite index)
                      // instead of silently falling back to an empty list.
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "ERROR loading daily attendance:\n${snapshot.error}",
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ),
                        );
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
                              trailing: Text(
                                s['status'],
                                style: TextStyle(
                                    color: _statusColor(s['status']),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
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
    List<Map<String, dynamic>> list;
    try {
      list = await _loadDailyData();
    } catch (e) {
      // Same fix as the on-screen FutureBuilder: don't let a Firestore
      // error (e.g. missing composite index) crash silently — tell the
      // user what actually happened.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not load attendance: $e")),
        );
      }
      return;
    }
    final dateLabel = DateFormat('dd MMM yyyy').format(_selectedDate);

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
                  pw.Text("Student Attendance Daily",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text("Class: $_selectedClass   |   Date: $dateLabel",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Roll', 'Name', 'Status'],
              data: list
                  .map((s) => [
                        s['rollNo'].toString().isEmpty ? '-' : s['rollNo'],
                        s['name'],
                        s['status'],
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
      title: "Student Attendance Daily Preview",
      shareFileName: "attendance_${_selectedClass}_$dateLabel.pdf",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
