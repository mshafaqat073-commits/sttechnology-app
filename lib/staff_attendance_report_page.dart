import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'performance_bar_chart.dart';

class TeacherAttendanceReportPage extends StatefulWidget {
  const TeacherAttendanceReportPage({super.key});

  @override
  State<TeacherAttendanceReportPage> createState() =>
      _TeacherAttendanceReportPageState();
}

class _TeacherAttendanceReportPageState
    extends State<TeacherAttendanceReportPage> {
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Teacher Attendance Report"),
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
                  "Date: $_selectedDate",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800]),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700),
                  icon: const Icon(Icons.calendar_today,
                      color: Colors.white, size: 18),
                  label: const Text("Change Date",
                      style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2030),
                    );
                    if (pickedDate != null) {
                      setState(() {
                        _selectedDate =
                            DateFormat('yyyy-MM-dd').format(pickedDate);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: schoolCollection('teacher_attendance')
                  .where('date', isEqualTo: _selectedDate)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No teacher attendance record found for this date.",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey),
                    ),
                  );
                }

                var docs = snapshot.data!.docs;

                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _enrichTeacherAttendanceData(docs),
                  builder: (context, enrichedSnapshot) {
                    if (enrichedSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    var teacherList = enrichedSnapshot.data ?? [];

                    if (teacherList.isEmpty) {
                      return const Center(
                        child: Text("No data found.",
                            style: TextStyle(color: Colors.grey)),
                      );
                    }

                    int presentCount = 0;
                    int absentCount = 0;
                    int leaveCount = 0;

                    for (var item in teacherList) {
                      String status = item['status'] ?? 'Present';
                      if (status == 'Present') {
                        presentCount++;
                      } else if (status == 'Absent') {
                        absentCount++;
                      } else if (status == 'Leave') {
                        leaveCount++;
                      }
                    }

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Row(
                            children: [
                              _statCard("Present", presentCount.toString(),
                                  Colors.green),
                              const SizedBox(width: 8),
                              _statCard(
                                  "Absent", absentCount.toString(), Colors.red),
                              const SizedBox(width: 8),
                              _statCard("Leave", leaveCount.toString(),
                                  Colors.orange),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: PerformanceBarChart(
                            height: 130,
                            bars: [
                              PerformanceBarData(
                                  label: "Present",
                                  value: presentCount.toDouble(),
                                  color: Colors.green),
                              PerformanceBarData(
                                  label: "Absent",
                                  value: absentCount.toDouble(),
                                  color: Colors.red),
                              PerformanceBarData(
                                  label: "Leave",
                                  value: leaveCount.toDouble(),
                                  color: Colors.orange),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ListView.builder(
                            itemCount: teacherList.length,
                            itemBuilder: (context, index) {
                              var data = teacherList[index];
                              String name = data['name'] ?? 'N/A';
                              String role = data['role'] ?? 'Teacher';
                              String status = data['status'] ?? 'Present';

                              Color statusColor = Colors.green;
                              if (status == 'Absent') {
                                statusColor = Colors.red;
                              } else if (status == 'Leave') {
                                statusColor = Colors.orange;
                              }

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                elevation: 2,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.teal.shade100,
                                    child: Text(name.isNotEmpty ? name[0] : 'T',
                                        style: TextStyle(
                                            color: Colors.teal[900],
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text("Role/Designation: $role"),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      border: Border.all(color: statusColor),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
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

  // Improved function to securely fetch name from staff/teachers collection
  Future<List<Map<String, dynamic>>> _enrichTeacherAttendanceData(
      List<QueryDocumentSnapshot> docs) async {
    List<Map<String, dynamic>> enrichedList = [];

    for (var doc in docs) {
      var data = doc.data() as Map<String, dynamic>;

      // First check if the name is already saved inside the attendance document
      String name =
          data['teacherName'] ?? data['name'] ?? data['staffName'] ?? '';
      String role = data['role'] ?? data['designation'] ?? 'Teacher';
      String status = data['status'] ?? 'Present';

      // Check different possible ID field names
      String teacherId =
          data['teacherId'] ?? data['staffId'] ?? data['id'] ?? '';

      // If the name isn't in attendance, search the staff/teachers collection
      if ((name.isEmpty || name == 'N/A') && teacherId.isNotEmpty) {
        try {
          // First check the 'teachers' collection
          var teacherDoc = await schoolCollection('staff')
              .doc(teacherId)
              .get();

          if (teacherDoc.exists && teacherDoc.data() != null) {
            var teacherData = teacherDoc.data() as Map<String, dynamic>;
            name = teacherData['name'] ??
                teacherData['teacherName'] ??
                teacherData['staffName'] ??
                teacherData['fullName'] ??
                'N/A';
            role = teacherData['role'] ?? teacherData['designation'] ?? role;
          } else {
            // If not found in 'teachers', check the 'staff' collection
            var staffDoc = await schoolCollection('staff')
                .doc(teacherId)
                .get();

            if (staffDoc.exists && staffDoc.data() != null) {
              var staffData = staffDoc.data() as Map<String, dynamic>;
              name = staffData['name'] ??
                  staffData['staffName'] ??
                  staffData['teacherName'] ??
                  staffData['fullName'] ??
                  'N/A';
              role = staffData['role'] ?? staffData['designation'] ?? role;
            }
          }
        } catch (e) {
          debugPrint("Error fetching teacher/staff name: $e");
        }
      }

      if (name.isEmpty) name = 'N/A';

      enrichedList.add({
        'name': name,
        'role': role,
        'status': status,
      });
    }

    return enrichedList;
  }

  Widget _statCard(String title, String count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(title,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 5),
            Text(count,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAndPrintPdf(BuildContext context) async {
    var snapshot = await schoolCollection('teacher_attendance')
        .where('date', isEqualTo: _selectedDate)
        .get();

    if (snapshot.docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "No teacher record available to generate for this date!")),
        );
      }
      return;
    }

    var pdfList = await _enrichTeacherAttendanceData(snapshot.docs);
    int pCount = 0, aCount = 0, lCount = 0;

    for (var item in pdfList) {
      String status = item['status'] ?? 'Present';
      if (status == 'Present') {
        pCount++;
      } else if (status == 'Absent') {
        aCount++;
      } else if (status == 'Leave') {
        lCount++;
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
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
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text("Date: $_selectedDate",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text(
                "Present: $pCount | Absent: $aCount | Leave: $lCount | Total Teachers: ${pdfList.length}",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Sr.', 'Teacher Name', 'Designation / Role', 'Status'],
              data: List.generate(pdfList.length, (index) {
                var item = pdfList[index];
                return [
                  "${index + 1}",
                  item['name'],
                  item['role'],
                  item['status'],
                ];
              }),
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

    await showPdfPreviewPage(
      context,
      title: "Staff Attendance Report Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
