import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'school_context.dart';
import 'performance_bar_chart.dart';
import 'parent_performance_page.dart';

/// Admin > Reports > "Students Performance" — every active student's
/// attendance % + result avg % + a remark, all in one list. Tapping opens
/// the same detail page that also opens from the Parent Dashboard
/// (attendance/result/fee history + graph) — no duplicate detail page
/// was created.
///
/// Data comes from all three collections' already-existing fields:
///   students   (name, class, section, imageUrl, dues, status)
///   attendance (studentId, status)
///   results    (studentId, percentage)
class AdminStudentPerformanceReportPage extends StatefulWidget {
  const AdminStudentPerformanceReportPage({super.key});

  @override
  State<AdminStudentPerformanceReportPage> createState() =>
      _AdminStudentPerformanceReportPageState();
}

class _AdminStudentPerformanceReportPageState
    extends State<AdminStudentPerformanceReportPage> {
  late Future<_StudentReportBundle> _future;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedClass = 'All';

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

  List<_StudentPerformanceRow> _filterRows(_StudentReportBundle bundle) {
    return bundle.rows.where((r) {
      final matchesSearch =
          _searchQuery.isEmpty || r.name.toLowerCase().contains(_searchQuery);
      final matchesClass =
          _selectedClass == 'All' || r.className == _selectedClass;
      return matchesSearch && matchesClass;
    }).toList();
  }

  /// Builds the PDF document for the currently filtered list of students
  /// and opens the native preview/print sheet (Printing.layoutPdf handles
  /// both "Preview" and "Print" — the user picks Save/Print/Share from
  /// there, so no separate download button is needed).
  Future<void> _exportPdf(List<_StudentPerformanceRow> rows) async {
    final doc = pw.Document();

    final headers = [
      'Name',
      'Class',
      'Attendance %',
      'Result %',
      'Remark',
    ];

    final data = rows.map((r) {
      final classLabel =
          r.section.isNotEmpty ? '${r.className} - ${r.section}' : r.className;
      return [
        r.name,
        classLabel,
        r.attendancePercent != null
            ? '${r.attendancePercent!.toStringAsFixed(0)}%'
            : 'N/A',
        r.avgResultPercent != null
            ? '${r.avgResultPercent!.toStringAsFixed(0)}%'
            : 'N/A',
        _remarkText(r.attendancePercent, r.avgResultPercent),
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Students Performance Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            if (_selectedClass != 'All')
              pw.Text('Class: $_selectedClass',
                  style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              2: pw.Alignment.center,
              3: pw.Alignment.center,
            },
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Students_Performance_Report.pdf',
    );
  }

  Future<_StudentReportBundle> _load() async {
    final studentsSnap = await schoolCollection('students')
        .where('status', isEqualTo: 'active')
        .get();
    final attendanceSnap = await schoolCollection('attendance').get();
    final resultsSnap = await schoolCollection('results').get();

    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        attendanceByStudent = {};
    for (var d in attendanceSnap.docs) {
      final sid = (d.data())['studentId']?.toString() ?? '';
      if (sid.isEmpty) continue;
      attendanceByStudent.putIfAbsent(sid, () => []).add(d);
    }

    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        resultsByStudent = {};
    for (var d in resultsSnap.docs) {
      final sid = (d.data())['studentId']?.toString() ?? '';
      if (sid.isEmpty) continue;
      resultsByStudent.putIfAbsent(sid, () => []).add(d);
    }

    List<_StudentPerformanceRow> rows = [];
    for (var doc in studentsSnap.docs) {
      final data = doc.data();
      final attendanceDocs = attendanceByStudent[doc.id] ?? [];
      final resultDocs = resultsByStudent[doc.id] ?? [];

      int present = 0;
      for (var a in attendanceDocs) {
        if ((a.data())['status']?.toString() == 'Present') present++;
      }
      final attendancePercent = attendanceDocs.isNotEmpty
          ? (present / attendanceDocs.length) * 100
          : null;

      double? avgResultPercent;
      if (resultDocs.isNotEmpty) {
        double sum = 0;
        for (var r in resultDocs) {
          sum +=
              double.tryParse((r.data())['percentage']?.toString() ?? '0') ?? 0;
        }
        avgResultPercent = sum / resultDocs.length;
      }

      rows.add(_StudentPerformanceRow(
        studentId: doc.id,
        name: (data['name'] ?? 'N/A').toString(),
        className: (data['class'] ?? 'N/A').toString(),
        section: (data['section'] ?? '').toString().trim(),
        data: data,
        attendancePercent: attendancePercent,
        avgResultPercent: avgResultPercent,
      ));
    }

    rows.sort((a, b) => a.name.compareTo(b.name));

    final classes = rows.map((r) => r.className).toSet().toList()..sort();

    return _StudentReportBundle(rows: rows, classes: classes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Students Performance"),
        backgroundColor: Colors.teal[800],
        actions: [
          FutureBuilder<_StudentReportBundle>(
            future: _future,
            builder: (context, snapshot) {
              final bundle = snapshot.data;
              final canExport =
                  snapshot.connectionState == ConnectionState.done &&
                      bundle != null;
              return IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: "Preview / Print PDF",
                onPressed:
                    canExport ? () => _exportPdf(_filterRows(bundle)) : null,
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<_StudentReportBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final bundle = snapshot.data!;

          var filtered = _filterRows(bundle);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search student name...",
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedClass,
                          items: ['All', ...bundle.classes]
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedClass = v ?? 'All'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text("No students found.",
                            style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final r = filtered[index];
                            return _studentTile(context, r);
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

  /// Simple text-only remark for the PDF table (kept independent of
  /// PerformanceRemark's icon/color widget fields, which don't translate
  /// to a printed table).
  String _remarkText(double? attendance, double? result) {
    if (attendance == null && result == null) return 'No Data';
    final scores = <double>[
      if (attendance != null) attendance,
      if (result != null) result,
    ];
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    if (avg >= 85) return 'Excellent';
    if (avg >= 70) return 'Good';
    if (avg >= 50) return 'Average';
    return 'Needs Attention';
  }

  /// Builds a single-page detail PDF for one student and opens the native
  /// preview/print sheet.
  Future<void> _exportSinglePdf(_StudentPerformanceRow r) async {
    final doc = pw.Document();
    final classLabel =
        r.section.isNotEmpty ? '${r.className} - ${r.section}' : r.className;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Student Performance Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            pw.Text(r.name,
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Class: $classLabel',
                style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: const ['Metric', 'Value'],
              data: [
                [
                  'Attendance %',
                  r.attendancePercent != null
                      ? '${r.attendancePercent!.toStringAsFixed(0)}%'
                      : 'N/A',
                ],
                [
                  'Result Avg %',
                  r.avgResultPercent != null
                      ? '${r.avgResultPercent!.toStringAsFixed(0)}%'
                      : 'N/A',
                ],
                [
                  'Remark',
                  _remarkText(r.attendancePercent, r.avgResultPercent)
                ],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
                color: PdfColors.white,
              ),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.teal800),
              cellStyle: const pw.TextStyle(fontSize: 11),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Student_Performance_${r.name.replaceAll(' ', '_')}.pdf',
    );
  }

  Widget _studentTile(BuildContext context, _StudentPerformanceRow r) {
    final remark = PerformanceRemark.overall(
      r.attendancePercent ?? 0,
      r.avgResultPercent ?? 0,
      hasAttendance: r.attendancePercent != null,
      hasResults: r.avgResultPercent != null,
    );
    final imageUrl = (r.data['imageUrl'] ?? '').toString();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade100,
          backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
          child: imageUrl.isEmpty
              ? const Icon(Icons.person, color: Colors.indigo)
              : null,
        ),
        title:
            Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          r.section.isNotEmpty
              ? "Class: ${r.className} - ${r.section}"
              : "Class: ${r.className}",
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
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
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: remark.color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  r.avgResultPercent != null
                      ? "${r.avgResultPercent!.toStringAsFixed(0)}% avg result"
                      : "No result",
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, size: 20),
              color: Colors.teal.shade800,
              tooltip: "Export PDF for ${r.name}",
              onPressed: () => _exportSinglePdf(r),
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ParentPerformancePage(
                studentId: r.studentId,
                studentName: r.name,
                studentData: r.data,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StudentPerformanceRow {
  final String studentId;
  final String name;
  final String className;
  final String section;
  final Map<String, dynamic> data;
  final double? attendancePercent;
  final double? avgResultPercent;

  _StudentPerformanceRow({
    required this.studentId,
    required this.name,
    required this.className,
    required this.section,
    required this.data,
    required this.attendancePercent,
    required this.avgResultPercent,
  });
}

class _StudentReportBundle {
  final List<_StudentPerformanceRow> rows;
  final List<String> classes;

  _StudentReportBundle({required this.rows, required this.classes});
}
