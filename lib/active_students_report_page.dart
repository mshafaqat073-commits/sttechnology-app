import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class ActiveStudentsReportPage extends StatelessWidget {
  const ActiveStudentsReportPage({super.key});

  // Strict Class Sorting Order Function
  int _compareClasses(String a, String b) {
    List<String> order = [
      'playgroup',
      'nursery',
      'prep',
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      '1st year',
      '11th',
      '2nd year',
      '12th'
    ];

    String cleanA = a.trim().toLowerCase();
    String cleanB = b.trim().toLowerCase();

    int indexA = order.indexOf(cleanA);
    int indexB = order.indexOf(cleanB);

    if (indexA != -1 && indexB != -1) {
      return indexA.compareTo(indexB);
    } else if (indexA != -1) {
      return -1; // a comes first
    } else if (indexB != -1) {
      return 1; // b comes first
    } else {
      return cleanA.compareTo(cleanB); // Remaining classes in alphabetical order
    }
  }

  // Groups a class's students by their Section
  Map<String, List<Map<String, dynamic>>> _groupBySection(
      List<Map<String, dynamic>> students) {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var student in students) {
      String section = (student['section'] ?? '').toString().trim();
      String key = section.isEmpty ? 'No Section' : section;
      grouped.putIfAbsent(key, () => []).add(student);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Active Students List"),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Download/Print PDF",
            onPressed: () => _generateAndPrintPdf(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('students')
            .where('status', isEqualTo: 'active')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No active student found.",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
              ),
            );
          }

          var docs = snapshot.data!.docs;

          // Process student list
          List<Map<String, dynamic>> studentList = [];
          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            studentList.add({
              'name': data['name'] ?? 'N/A',
              'fName': data['fName'] ?? 'N/A',
              'class': data['class'] ?? 'Unassigned',
              'section': (data['section'] ?? '').toString().trim(),
              'phone': data['contactNo'] ?? data['phone'] ?? 'N/A',
              'status': data['status'] ?? 'N/A',
              'rawData': data,
            });
          }

          // Grouping students by Class
          Map<String, List<Map<String, dynamic>>> groupedByClass = {};
          for (var student in studentList) {
            String className = student['class'];
            if (!groupedByClass.containsKey(className)) {
              groupedByClass[className] = [];
            }
            groupedByClass[className]!.add(student);
          }

          // Alphabetical sorting of students has been removed here so the original order is kept

          // Sort classes according to the custom order (`_compareClasses`)
          var sortedClasses = groupedByClass.keys.toList()
            ..sort((a, b) => _compareClasses(a, b));

          return Column(
            children: [
              // Total Active Students Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  border: Border.all(color: Colors.teal.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total Active Students:",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal),
                    ),
                    Text(
                      "${studentList.length}",
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal),
                    ),
                  ],
                ),
              ),

              // Class-wise ListView Builder
              Expanded(
                child: ListView.builder(
                  itemCount: sortedClasses.length,
                  itemBuilder: (context, classIndex) {
                    String className = sortedClasses[classIndex];
                    List<Map<String, dynamic>> studentsInClass =
                        groupedByClass[className]!;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      elevation: 2,
                      child: ExpansionTile(
                        initiallyExpanded: true,
                        title: Text(
                          "Class: $className",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.teal[800],
                          ),
                        ),
                        subtitle:
                            Text("Total Students: ${studentsInClass.length}"),
                        children: () {
                          var bySection = _groupBySection(studentsInClass);
                          var sortedSections = bySection.keys.toList()..sort();
                          List<Widget> sectionWidgets = [];
                          for (var section in sortedSections) {
                            var studentsInSection = bySection[section]!;
                            sectionWidgets.add(
                              Container(
                                width: double.infinity,
                                color: Colors.teal.shade50,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                child: Text(
                                  "Section: $section  (${studentsInSection.length})",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.teal[700],
                                  ),
                                ),
                              ),
                            );
                            sectionWidgets.addAll(
                              studentsInSection.map((data) {
                                String name = data['name'];
                                String fName = data['fName'];
                                String phone = data['phone'];
                                int studentIndex =
                                    studentsInSection.indexOf(data) + 1;

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.teal.shade100,
                                    child: Text(
                                      "$studentIndex",
                                      style: TextStyle(
                                          color: Colors.teal.shade800,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text("Father: $fName"),
                                  trailing: Text(
                                    phone,
                                    style: const TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  onTap: () {
                                    _showStudentDetails(
                                        context, data['rawData']);
                                  },
                                );
                              }),
                            );
                          }
                          return sectionWidgets;
                        }(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Student Detail Dialog
  void _showStudentDetails(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(data['name'] ?? 'Student Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Father Name: ${data['fName'] ?? 'N/A'}"),
            const SizedBox(height: 6),
            Text("Class: ${data['class'] ?? 'N/A'}"),
            const SizedBox(height: 6),
            Text("Section: ${data['section'] ?? 'N/A'}"),
            const SizedBox(height: 6),
            Text("Contact No 1: ${data['contactNo'] ?? data['phone'] ?? 'N/A'}"),
            if ((data['contactNo2'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text("Contact No 2: ${data['contactNo2']}"),
            ],
            const SizedBox(height: 6),
            Text("Status: ${data['status'] ?? 'N/A'}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // PDF Generation Function with Proper Sorting
  Future<void> _generateAndPrintPdf(BuildContext context) async {
    final pdf = pw.Document();

    var snapshot = await schoolCollection('students')
        .where('status', isEqualTo: 'active')
        .get();

    if (snapshot.docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "No active student available to generate PDF!")),
        );
      }
      return;
    }

    var docs = snapshot.docs;
    List<Map<String, dynamic>> pdfList = [];

    for (var doc in docs) {
      var data = doc.data();
      pdfList.add({
        'name': data['name'] ?? 'N/A',
        'fName': data['fName'] ?? 'N/A',
        'class': data['class'] ?? 'Unassigned',
        'section': (data['section'] ?? '').toString().trim(),
        'phone': data['contactNo'] ?? data['phone'] ?? 'N/A',
        'phone2': (data['contactNo2'] ?? '').toString().trim().isEmpty
            ? '-'
            : data['contactNo2'].toString(),
      });
    }

    // Grouping for PDF
    Map<String, List<Map<String, dynamic>>> groupedByClass = {};
    for (var student in pdfList) {
      String className = student['class'];
      if (!groupedByClass.containsKey(className)) {
        groupedByClass[className] = [];
      }
      groupedByClass[className]!.add(student);
    }

    // Alphabetical sorting of students has been removed for the PDF too

    // Custom Sorting Classes for PDF
    var sortedClasses = groupedByClass.keys.toList()
      ..sort((a, b) => _compareClasses(a, b));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          List<pw.Widget> widgets = [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(currentSchoolDisplayName(),
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Active Students Class-wise Report",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text("Total Active Students: ${pdfList.length}",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
          ];

          for (var className in sortedClasses) {
            var students = groupedByClass[className]!;
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text("Class: $className",
                    style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal800)),
              ),
            );

            var bySection = _groupBySection(students);
            var sortedSections = bySection.keys.toList()..sort();

            for (var section in sortedSections) {
              var sectionStudents = bySection[section]!;
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, bottom: 4),
                  child: pw.Text("Section: $section",
                      style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal700)),
                ),
              );

              widgets.add(
                pw.Table.fromTextArray(
                  headers: [
                    'Sr.',
                    'Student Name',
                    'Father Name',
                    'Contact No 1',
                    'Contact No 2'
                  ],
                  data: List.generate(sectionStudents.length, (index) {
                    var item = sectionStudents[index];
                    return [
                      "${index + 1}",
                      item['name'],
                      item['fName'],
                      item['phone'],
                      item['phone2'],
                    ];
                  }),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.grey300),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellPadding: const pw.EdgeInsets.all(6),
                ),
              );
              widgets.add(pw.SizedBox(height: 8));
            }
            widgets.add(pw.SizedBox(height: 6));
          }

          return widgets;
        },
      ),
    );

    await showPdfPreviewPage(
      context,
      title: "Active Students Report Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
