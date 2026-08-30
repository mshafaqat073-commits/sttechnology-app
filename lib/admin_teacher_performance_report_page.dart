import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'school_context.dart';
import 'performance_bar_chart.dart';
import 'teacher_performance_page.dart';

/// Admin > Reports > "Teachers Performance" — each staff member's own
/// attendance % + their assigned class(es)' result avg % + a remark, all
/// in one list. Tapping opens the same detail page that also opens from
/// the Teacher Dashboard's "My Performance" — no duplicate detail page
/// was created.
///
/// Data comes from existing collections/fields:
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

    // class|section -> result docs, so each staff member's assigned
    // class(es) can be matched quickly.
    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        resultsByClassSection = {};
    for (var d in resultsSnap.docs) {
      final data = d.data();
      final cls = (data['class'] ?? '').toString();
      final sec = (data['section'] ?? '').toString().trim();
      resultsByClassSection.putIfAbsent('$cls|$sec', () => []).add(d);
      // Also a section-less bucket, in case the teacher's assigned section is empty
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

  String _classLabelOf(_StaffPerformanceRow r) {
    return r.assignedClasses.isEmpty
        ? "No class assigned"
        : r.assignedClasses
            .map((a) => (a['section'] ?? '').isNotEmpty
                ? "${a['class']} - ${a['section']}"
                : (a['class'] ?? ''))
            .join(", ");
  }

  /// Simple text-only remark for the PDF (kept independent of
  /// PerformanceRemark's icon/color widget fields, which don't translate
  /// to a printed page).
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

  /// Builds a table PDF for the currently filtered list of staff and opens
  /// the native preview/print sheet.
  Future<void> _exportPdf(List<_StaffPerformanceRow> rows) async {
    final doc = pw.Document();

    final headers = [
      'Name',
      'Designation',
      'Assigned Class(es)',
      'Attendance %',
      'Result %',
      'Remark',
    ];

    final data = rows.map((r) {
      return [
        r.name,
        r.designation,
        _classLabelOf(r),
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
              'Teachers Performance Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
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
            headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              3: pw.Alignment.center,
              4: pw.Alignment.center,
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
      name: 'Teachers_Performance_Report.pdf',
    );
  }

  /// Builds a single-page detail PDF for one teacher/staff member and
  /// opens the native preview/print sheet.
  Future<void> _exportSinglePdf(_StaffPerformanceRow r) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Teacher Performance Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            pw.Text(r.name,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Designation: ${r.designation}',
                style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 4),
            pw.Text('Assigned Class(es): ${_classLabelOf(r)}',
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
                  'Class Result Avg %',
                  r.avgResultPercent != null
                      ? '${r.avgResultPercent!.toStringAsFixed(0)}%'
                      : 'N/A',
                ],
                ['Remark', _remarkText(r.attendancePercent, r.avgResultPercent)],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple800),
              cellStyle: const pw.TextStyle(fontSize: 11),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Teacher_Performance_${r.name.replaceAll(' ', '_')}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Teachers Performance"),
        backgroundColor: Colors.teal[800],
        actions: [
          FutureBuilder<List<_StaffPerformanceRow>>(
            future: _future,
            builder: (context, snapshot) {
              final rows = snapshot.data;
              final canExport = snapshot.connectionState == ConnectionState.done &&
                  rows != null;
              return IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: "Preview / Print PDF (All)",
                onPressed: canExport
                    ? () {
                        final filtered = _searchQuery.isEmpty
                            ? rows
                            : rows
                                .where((r) =>
                                    r.name.toLowerCase().contains(_searchQuery))
                                .toList();
                        _exportPdf(filtered);
                      }
                    : null,
              );
            },
          ),
        ],
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
    final classLabel = _classLabelOf(r);

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
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, size: 20),
              color: Colors.deepPurple.shade700,
              tooltip: "Export PDF for ${r.name}",
              onPressed: () => _exportSinglePdf(r),
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
