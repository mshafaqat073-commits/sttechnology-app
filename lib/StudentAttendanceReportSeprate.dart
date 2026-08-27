import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class StudentAttendanceReportSeprate extends StatefulWidget {
  const StudentAttendanceReportSeprate({super.key});

  @override
  State<StudentAttendanceReportSeprate> createState() =>
      _StudentAttendanceReportSeprateState();
}

class _StudentAttendanceReportSeprateState
    extends State<StudentAttendanceReportSeprate> {
  List<DocumentSnapshot> allStudents = [];
  List<DocumentSnapshot> filteredStudents = [];
  final TextEditingController _searchController = TextEditingController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
      var snapshot =
          await schoolCollection('students').get();
      setState(() {
        allStudents = snapshot.docs;
        filteredStudents = snapshot.docs;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Instant Live Search Logic
  void _filterStudents(String query) {
    String q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        filteredStudents = List.from(allStudents);
      } else {
        filteredStudents = allStudents.where((doc) {
          var data = doc.data() as Map<String, dynamic>? ?? {};
          String name = (data['name'] ?? data['studentName'] ?? '')
              .toString()
              .toLowerCase();
          String roll =
              (data['rollNo'] ?? data['roll'] ?? '').toString().toLowerCase();
          String className = (data['class'] ?? '').toString().toLowerCase();
          String sectionName =
              (data['section'] ?? '').toString().toLowerCase();

          return name.contains(q) ||
              roll.contains(q) ||
              className.contains(q) ||
              sectionName.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _generateStudentPdf(String studentId, String studentName,
      String className, String sectionName) async {
    var attendanceSnapshot = await schoolCollection('attendance')
        .where('studentId', isEqualTo: studentId)
        .get();

    var docs = attendanceSnapshot.docs;
    if (docs.isEmpty) {
      var all = await schoolCollection('attendance').get();
      docs = all.docs.where((d) {
        var data = d.data() as Map<String, dynamic>? ?? {};
        return data['studentId'] == studentId || data['id'] == studentId;
      }).toList();
    }

    int totalDays = docs.length;
    int presentCount = 0;
    int absentCount = 0;
    int leaveCount = 0;

    for (var doc in docs) {
      var data = doc.data() as Map<String, dynamic>? ?? {};
      String status = (data['status'] ?? 'Present').toString().toLowerCase();
      if (status.contains('present') || status == 'p') {
        presentCount++;
      } else if (status.contains('absent') || status == 'a') {
        absentCount++;
      } else {
        leaveCount++;
      }
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(currentSchoolDisplayName(),
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text("Student Attendance Report",
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text("Student Name: $studentName",
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text("Class: $className", style: const pw.TextStyle(fontSize: 12)),
          if (sectionName.isNotEmpty)
            pw.Text("Section: $sectionName",
                style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Text("Total: $totalDays",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text("Present: $presentCount",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green700)),
                pw.Text("Absent: $absentCount",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red700)),
                pw.Text("Leave: $leaveCount",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange700)),
              ],
            ),
          ),
          pw.SizedBox(height: 15),
          docs.isEmpty
              ? pw.Text("No attendance records found.",
                  style: const pw.TextStyle(fontSize: 12))
              : pw.Table.fromTextArray(
                  headers: ['Sr.', 'Date', 'Status'],
                  data: List.generate(docs.length, (i) {
                    var d = docs[i].data() as Map<String, dynamic>? ?? {};
                    return [
                      "${i + 1}",
                      d['date']?.toString() ?? 'N/A',
                      d['status']?.toString() ?? 'Present'
                    ];
                  }),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.grey300),
                ),
        ],
      ),
    );

    await showPdfPreviewPage(context, title: "Student Attendance Report Preview", build: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final Color color = Colors.blue.shade700;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StatefulBuilder(
              builder: (BuildContext context, StateSetter setStateModal) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text("Student Separate Attendance"),
                    backgroundColor: Colors.teal[800],
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            _filterStudents(value);
                            setStateModal(() {}); // Modal UI refresh instant
                          },
                          decoration: InputDecoration(
                            labelText:
                                "Search student by name, roll, or class...",
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _filterStudents('');
                                      setStateModal(() {});
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Expanded(
                          child: isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : filteredStudents.isEmpty
                                  ? const Center(
                                      child: Text("No student found"))
                                  : ListView.builder(
                                      itemCount: filteredStudents.length,
                                      itemBuilder: (context, index) {
                                        var doc = filteredStudents[index];
                                        var data = doc.data()
                                                as Map<String, dynamic>? ??
                                            {};
                                        String studentId = doc.id;
                                        String name = data['name'] ??
                                            data['studentName'] ??
                                            'N/A';
                                        String className =
                                            data['class'] ?? 'N/A';
                                        String sectionName =
                                            (data['section'] ?? '')
                                                .toString()
                                                .trim();

                                        return Card(
                                          margin:
                                              const EdgeInsets.only(bottom: 10),
                                          child: ListTile(
                                            title: Text(name,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            subtitle: Text(sectionName
                                                    .isNotEmpty
                                                ? "Class: $className - $sectionName"
                                                : "Class: $className"),
                                            trailing: const Icon(
                                                Icons.arrow_forward_ios,
                                                size: 16),
                                            onTap: () => _generateStudentPdf(
                                                studentId,
                                                name,
                                                className,
                                                sectionName),
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 55,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.person_search, color: color, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "Student Separate Attendance",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.blue),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
