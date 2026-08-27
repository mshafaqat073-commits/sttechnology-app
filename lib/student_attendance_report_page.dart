import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'performance_bar_chart.dart';

class StudentAttendanceReportPage extends StatefulWidget {
  const StudentAttendanceReportPage({super.key});

  @override
  State<StudentAttendanceReportPage> createState() =>
      _StudentAttendanceReportPageState();
}

class _StudentAttendanceReportPageState
    extends State<StudentAttendanceReportPage> {
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // Strict Custom Class Order
  static const List<String> _classOrder = [
    'Playgroup',
    'Nursery',
    'Prep',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
  ];

  static final Map<String, String> _classAliases = {
    'playgroup': 'Playgroup',
    'playgrp': 'Playgroup',
    'pg': 'Playgroup',
    'play': 'Playgroup',
    'nursery': 'Nursery',
    'nur': 'Nursery',
    'ns': 'Nursery',
    'prep': 'Prep',
    'kg': 'Prep',
    'kindergarten': 'Prep',
    'one': 'One',
    '1': 'One',
    '1st': 'One',
    'class1': 'One',
    'classone': 'One',
    'two': 'Two',
    '2': 'Two',
    '2nd': 'Two',
    'class2': 'Two',
    'classtwo': 'Two',
    'three': 'Three',
    '3': 'Three',
    '3rd': 'Three',
    'class3': 'Three',
    'classthree': 'Three',
    'four': 'Four',
    '4': 'Four',
    '4th': 'Four',
    'class4': 'Four',
    'classfour': 'Four',
    'five': 'Five',
    '5': 'Five',
    '5th': 'Five',
    'class5': 'Five',
    'classfive': 'Five',
    'six': 'Six',
    '6': 'Six',
    '6th': 'Six',
    'class6': 'Six',
    'classsix': 'Six',
    'seven': 'Seven',
    '7': 'Seven',
    '7th': 'Seven',
    'class7': 'Seven',
    'classseven': 'Seven',
    'eight': 'Eight',
    '8': 'Eight',
    '8th': 'Eight',
    'class8': 'Eight',
    'classeight': 'Eight',
    'nine': 'Nine',
    '9': 'Nine',
    '9th': 'Nine',
    'class9': 'Nine',
    'classnine': 'Nine',
    'ten': 'Ten',
    '10': 'Ten',
    '10th': 'Ten',
    'class10': 'Ten',
    'classten': 'Ten',
  };

  int _compareClasses(String a, String b) {
    int indexA = _classOrder
        .indexWhere((element) => element.toLowerCase() == a.toLowerCase());
    int indexB = _classOrder
        .indexWhere((element) => element.toLowerCase() == b.toLowerCase());

    if (indexA == -1) indexA = 999;
    if (indexB == -1) indexB = 999;

    if (indexA == 999 && indexB == 999) {
      return a.compareTo(b);
    }

    return indexA.compareTo(indexB);
  }

  String _formatClassName(String rawClass) {
    String trimmed = rawClass.trim();
    if (trimmed.isEmpty) return 'Unassigned';

    String clean = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (_classAliases.containsKey(clean)) {
      return _classAliases[clean]!;
    }

    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }

  // Ek class ke students ko unke Section ke hisaab se group karna
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
        title: const Text("Student Attendance Report"),
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
              border: Border.all(color: Colors.teal.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Date: $_selectedDate",
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal),
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
              stream: schoolCollection('attendance')
                  .where('date', isEqualTo: _selectedDate)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "ERROR loading attendance:\n${snapshot.error}",
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No record found.",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey),
                    ),
                  );
                }

                var docs = snapshot.data!.docs;

                // 🔍 TEMP DEBUG BANNER — shows raw Firestore data on screen.
                // Remove this Column/debugBanner wrapper once issue is fixed.
                String debugBanner =
                    "Found ${docs.length} attendance doc(s). Raw class values: ${docs.map((d) => (d.data() as Map<String, dynamic>)['class']?.toString() ?? 'NULL').join(', ')}";

                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.yellow.shade100,
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        debugBanner,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _processAttendanceDocs(docs),
                        builder: (context, processedSnapshot) {
                          if (processedSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          if (processedSnapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  "ERROR processing attendance:\n${processedSnapshot.error}",
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 14),
                                ),
                              ),
                            );
                          }

                          var studentList = processedSnapshot.data ?? [];

                          if (studentList.isEmpty) {
                            return const Center(
                              child: Text("No data found.",
                                  style: TextStyle(color: Colors.grey)),
                            );
                          }

                          int presentCount = 0;
                          int absentCount = 0;
                          int leaveCount = 0;

                          for (var item in studentList) {
                            String status = item['status'] ?? 'Present';
                            if (status == 'Present') {
                              presentCount++;
                            } else if (status == 'Absent') {
                              absentCount++;
                            } else if (status == 'Leave') {
                              leaveCount++;
                            }
                          }

                          Map<String, List<Map<String, dynamic>>>
                              groupedByClass = {};
                          for (var student in studentList) {
                            String rawClass = student['class'];
                            String formattedClass = _formatClassName(rawClass);
                            if (!groupedByClass.containsKey(formattedClass)) {
                              groupedByClass[formattedClass] = [];
                            }
                            groupedByClass[formattedClass]!.add(student);
                          }

                          // --- ROBUST SORTING (Roll Number + Name) ---
                          for (var className in groupedByClass.keys) {
                            groupedByClass[className]!.sort((a, b) {
                              var rollA =
                                  int.tryParse(a['rollNo'].toString()) ??
                                      999999;
                              var rollB =
                                  int.tryParse(b['rollNo'].toString()) ??
                                      999999;
                              if (rollA != rollB) {
                                return rollA.compareTo(rollB);
                              }
                              return (a['name'] as String)
                                  .toLowerCase()
                                  .compareTo(
                                      (b['name'] as String).toLowerCase());
                            });
                          }

                          List<String> sortedClasses =
                              groupedByClass.keys.toList();
                          sortedClasses.sort(_compareClasses);

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0),
                                child: Row(
                                  children: [
                                    _statCard("Present",
                                        presentCount.toString(), Colors.green),
                                    const SizedBox(width: 8),
                                    _statCard("Absent", absentCount.toString(),
                                        Colors.red),
                                    const SizedBox(width: 8),
                                    _statCard("Leave", leaveCount.toString(),
                                        Colors.orange),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    12, 10, 12, 0),
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
                                  itemCount: sortedClasses.length,
                                  itemBuilder: (context, classIndex) {
                                    String className =
                                        sortedClasses[classIndex];
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
                                        subtitle: Text(
                                            "Total Students: ${studentsInClass.length}"),
                                        children: () {
                                          var bySection =
                                              _groupBySection(studentsInClass);
                                          var sortedSections =
                                              bySection.keys.toList()..sort();
                                          List<Widget> sectionWidgets = [];
                                          for (var section in sortedSections) {
                                            var studentsInSection =
                                                bySection[section]!;
                                            sectionWidgets.add(
                                              Container(
                                                width: double.infinity,
                                                color: Colors.teal.shade50,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 6),
                                                child: Text(
                                                  "Section: $section  (${studentsInSection.length})",
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 13,
                                                    color: Colors.teal[700],
                                                  ),
                                                ),
                                              ),
                                            );
                                            sectionWidgets.addAll(
                                              List.generate(
                                                  studentsInSection.length,
                                                  (index) {
                                                var data =
                                                    studentsInSection[index];
                                                String name = data['name'];
                                                String fName = data['fName'];
                                                String status =
                                                    data['status'];
                                                String rollNo =
                                                    data['rollNo'].toString();

                                                Color statusColor =
                                                    Colors.green;
                                                if (status == 'Absent') {
                                                  statusColor = Colors.red;
                                                } else if (status ==
                                                    'Leave') {
                                                  statusColor =
                                                      Colors.orange;
                                                }

                                                return ListTile(
                                                  leading: CircleAvatar(
                                                    backgroundColor:
                                                        Colors.teal.shade100,
                                                    child: Text(
                                                      rollNo == 'N/A' ||
                                                              rollNo.isEmpty
                                                          ? "${index + 1}"
                                                          : rollNo,
                                                      style: TextStyle(
                                                          color: Colors
                                                              .teal.shade800,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 12),
                                                    ),
                                                  ),
                                                  title: Text(name,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold)),
                                                  subtitle: Text(
                                                      "Roll No: $rollNo | Father: $fName"),
                                                  trailing: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 5),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withValues(
                                                              alpha: 0.1),
                                                      border: Border.all(
                                                          color:
                                                              statusColor),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(5),
                                                    ),
                                                    child: Text(
                                                      status,
                                                      style: TextStyle(
                                                          color: statusColor,
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold),
                                                    ),
                                                  ),
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
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Processes raw attendance documents into a normalized student list.
  ///
  /// FIX: previously this only fetched from the `students` collection when
  /// the attendance doc's own `class`/`studentId` fields looked missing.
  /// Since some attendance docs were saved without a reliable class value,
  /// this now ALWAYS uses the linked student's data (when studentId is
  /// present) and treats the `students` collection as the authoritative
  /// source for class/name/father-name/roll number.
  ///
  /// IMPORTANT: instead of doing one `.doc(studentId).get()` call PER
  /// attendance record (which can silently fail under some Firestore
  /// security rule setups that allow collection queries but restrict
  /// direct get-by-id), we fetch the whole `students` collection ONCE
  /// with a normal query — the same pattern already confirmed working
  /// in ActiveStudentsReportPage — and look students up locally by ID.
  Future<List<Map<String, dynamic>>> _processAttendanceDocs(
      List<QueryDocumentSnapshot> docs) async {
    // Fetch all students once (same query style that already works).
    Map<String, Map<String, dynamic>> studentsById = {};
    try {
      var studentsSnapshot =
          await schoolCollection('students').get();
      for (var sDoc in studentsSnapshot.docs) {
        studentsById[sDoc.id] = sDoc.data();
      }
      debugPrint(
          "✅ Loaded ${studentsById.length} students from 'students' collection");
    } catch (e) {
      debugPrint("⚠️ Error loading 'students' collection: $e");
    }

    List<Map<String, dynamic>> studentList = [];

    for (var doc in docs) {
      var data = doc.data() as Map<String, dynamic>;

      // Attendance doc only ever has: class, date, status, studentId, timestamp.
      // name / fName / rollNo always come from the linked 'students' doc.
      String name = '';
      String fName = '';
      String className = data['class'] ?? data['className'] ?? 'Unassigned';
      String sectionName = (data['section'] ?? '').toString().trim();
      String status = data['status'] ?? 'Present';
      String studentId = data['studentId'] ??
          data['student_id'] ??
          data['studentID'] ??
          data['id'] ??
          '';
      String rollNo = '';

      if (studentId.isNotEmpty) {
        var sData = studentsById[studentId];
        if (sData != null) {
          name = sData['name']?.toString() ?? '';
          fName = sData['fName']?.toString() ?? '';
          rollNo = sData['rollNo']?.toString() ??
              sData['rollNumber']?.toString() ??
              '';

          // students collection is treated as the source of truth for class
          var studentsClass = sData['class'] ?? sData['className'];
          if (studentsClass != null &&
              studentsClass.toString().trim().isNotEmpty) {
            className = studentsClass.toString();
          }

          // students collection is treated as the source of truth for section
          var studentsSection = sData['section'];
          if (studentsSection != null &&
              studentsSection.toString().trim().isNotEmpty) {
            sectionName = studentsSection.toString().trim();
          }
        } else {
          debugPrint(
              "⚠️ Attendance doc ${doc.id}: no student found in 'students' for studentId=$studentId");
        }
      } else {
        debugPrint("⚠️ Attendance doc ${doc.id} has NO studentId field!");
      }

      studentList.add({
        'name': name.isEmpty ? 'N/A' : name,
        'fName': fName.isEmpty ? 'N/A' : fName,
        'class': className,
        'section': sectionName,
        'status': status,
        'rollNo': rollNo.isEmpty ? '999' : rollNo,
        'rawData': data,
      });
    }

    return studentList;
  }

  Widget _statCard(String title, String count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(title,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text(count,
                style: TextStyle(
                    color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAndPrintPdf(BuildContext context) async {
    var snapshot = await schoolCollection('attendance')
        .where('date', isEqualTo: _selectedDate)
        .get();

    if (snapshot.docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No record found on this date!")),
        );
      }
      return;
    }

    var pdfList = await _processAttendanceDocs(snapshot.docs);
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

    Map<String, List<Map<String, dynamic>>> groupedByClass = {};
    for (var student in pdfList) {
      String rawClass = student['class'];
      String formattedClass = _formatClassName(rawClass);
      if (!groupedByClass.containsKey(formattedClass)) {
        groupedByClass[formattedClass] = [];
      }
      groupedByClass[formattedClass]!.add(student);
    }

    for (var className in groupedByClass.keys) {
      groupedByClass[className]!.sort((a, b) {
        var rollA = int.tryParse(a['rollNo'].toString()) ?? 999999;
        var rollB = int.tryParse(b['rollNo'].toString()) ?? 999999;
        if (rollA != rollB) {
          return rollA.compareTo(rollB);
        }
        return (a['name'] as String)
            .toLowerCase()
            .compareTo((b['name'] as String).toLowerCase());
      });
    }

    List<String> sortedClasses = groupedByClass.keys.toList();
    sortedClasses.sort(_compareClasses);

    final pdf = pw.Document();

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
                  pw.Text("Class-wise Attendance Report",
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
                "Present: $pCount | Absent: $aCount | Leave: $lCount | Total: ${pdfList.length}",
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
                    'Roll No.',
                    'Student Name',
                    'Father Name',
                    'Status'
                  ],
                  data: List.generate(sectionStudents.length, (index) {
                    var item = sectionStudents[index];
                    return [
                      item['rollNo'].toString(),
                      item['name'],
                      item['fName'],
                      item['status'],
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
      title: "Student Attendance Report Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
