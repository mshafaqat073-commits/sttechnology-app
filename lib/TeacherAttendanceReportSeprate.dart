import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class TeacherAttendanceReportSeprate extends StatefulWidget {
  const TeacherAttendanceReportSeprate({super.key});

  @override
  State<TeacherAttendanceReportSeprate> createState() =>
      _TeacherAttendanceReportSeprateState();
}

class _TeacherAttendanceReportSeprateState
    extends State<TeacherAttendanceReportSeprate> {
  List<DocumentSnapshot> allTeachers = [];
  List<DocumentSnapshot> filteredTeachers = [];
  final TextEditingController _searchController = TextEditingController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTeachers();
  }

  Future<void> _fetchTeachers() async {
    try {
      var snapshot =
          await schoolCollection('teachers').get();
      if (snapshot.docs.isEmpty) {
        var staffSnap =
            await schoolCollection('staff').get();
        setState(() {
          allTeachers = staffSnap.docs;
          filteredTeachers = staffSnap.docs;
          isLoading = false;
        });
      } else {
        setState(() {
          allTeachers = snapshot.docs;
          filteredTeachers = snapshot.docs;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Instant Live Search Logic for Teachers
  void _filterTeachers(String query) {
    String q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        filteredTeachers = List.from(allTeachers);
      } else {
        filteredTeachers = allTeachers.where((doc) {
          var data = doc.data() as Map<String, dynamic>? ?? {};
          String name = (data['name'] ?? data['teacherName'] ?? '')
              .toString()
              .toLowerCase();
          String role = (data['role'] ?? data['designation'] ?? '')
              .toString()
              .toLowerCase();

          return name.contains(q) || role.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _generateTeacherPdf(
      String teacherId, String teacherName, String role) async {
    var attendanceSnapshot = await schoolCollection('teacher_attendance')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    var docs = attendanceSnapshot.docs;
    if (docs.isEmpty) {
      var all = await schoolCollection('teacher_attendance')
          .get();
      docs = all.docs.where((d) {
        var data = d.data() as Map<String, dynamic>? ?? {};
        return data['teacherId'] == teacherId || data['staffId'] == teacherId;
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
                pw.Text("Teacher Attendance Report",
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text("Teacher Name: $teacherName",
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text("Designation: $role",
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

    await showPdfPreviewPage(context, title: "Teacher Attendance Report Preview", build: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final Color color = Colors.deepPurple;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StatefulBuilder(
              builder: (BuildContext context, StateSetter setStateModal) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text("Teacher Separate Attendance"),
                    backgroundColor: Colors.teal[800],
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            _filterTeachers(value);
                            setStateModal(() {}); // Modal UI refresh instant
                          },
                          decoration: InputDecoration(
                            labelText: "Search teacher by name or role...",
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _filterTeachers('');
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
                              : filteredTeachers.isEmpty
                                  ? const Center(
                                      child: Text("No teacher found"))
                                  : ListView.builder(
                                      itemCount: filteredTeachers.length,
                                      itemBuilder: (context, index) {
                                        var doc = filteredTeachers[index];
                                        var data = doc.data()
                                                as Map<String, dynamic>? ??
                                            {};
                                        String teacherId = doc.id;
                                        String name = data['name'] ??
                                            data['teacherName'] ??
                                            'N/A';
                                        String role = data['role'] ??
                                            data['designation'] ??
                                            'Teacher';

                                        return Card(
                                          margin:
                                              const EdgeInsets.only(bottom: 10),
                                          child: ListTile(
                                            title: Text(name,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            subtitle: Text("Role: $role"),
                                            trailing: const Icon(
                                                Icons.arrow_forward_ios,
                                                size: 16),
                                            onTap: () => _generateTeacherPdf(
                                                teacherId, name, role),
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
            Icon(Icons.co_present, color: color, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "Teacher Separate Attendance",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.deepPurple),
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
