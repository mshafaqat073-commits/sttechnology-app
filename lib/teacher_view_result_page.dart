import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class TeacherViewResultPage extends StatefulWidget {
  // When provided (e.g. by a teacher), only results belonging to these
  // class/section assignments are shown. Each entry looks like
  // {'class': '6', 'section': 'A'} — an empty section means the whole
  // class is allowed. Leave null/empty for unrestricted (admin) access.
  final List<Map<String, String>> allowedClasses;

  const TeacherViewResultPage({super.key, required this.allowedClasses});

  @override
  State<TeacherViewResultPage> createState() => _TeacherViewResultPageState();
}

class _TeacherViewResultPageState extends State<TeacherViewResultPage> {
  // Stream ek dafa bana lete hain — pehle build() ke andar seedha banta
  // tha, is liye kisi bhi setState (filter/dropdown change) par
  // Firestore se dobara connect ho jata tha.
  late final Stream<QuerySnapshot> _resultsStream =
      schoolCollection('results').snapshots();

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

  bool get _isRestricted => widget.allowedClasses.isNotEmpty;

  bool _isAllowedResult(Map<String, dynamic> data) {
    if (!_isRestricted) return true;
    String cls = (data['class'] ?? '').toString();
    String sec = (data['section'] ?? '').toString();
    return widget.allowedClasses.any((a) {
      final aClass = a['class'] ?? '';
      final aSection = a['section'] ?? '';
      if (aClass != cls) return false;
      if (aSection.isEmpty) return true; // whole class assigned, any section
      return aSection == sec;
    });
  }

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

  double _parseToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  String _calculateGrade(double percentage) {
    if (percentage >= 80) return 'A+';
    if (percentage >= 70) return 'A';
    if (percentage >= 60) return 'B';
    if (percentage >= 50) return 'C';
    if (percentage >= 40) return 'D';
    return 'F';
  }

  // Full Result Update Dialog
  void _showUpdateDialog(String docId, Map<String, dynamic> currentData) {
    final nameController =
        TextEditingController(text: currentData['name'] ?? '');
    final fNameController =
        TextEditingController(text: currentData['fName'] ?? '');
    final classController =
        TextEditingController(text: currentData['class'] ?? '');
    final sectionController =
        TextEditingController(text: currentData['section'] ?? '');
    final termController =
        TextEditingController(text: currentData['term'] ?? 'Final Term');
    final studentPicController = TextEditingController(
        text: currentData['imageUrl'] ?? currentData['studentPicUrl'] ?? '');

    final List<String> termOptions = [
      'First Term',
      'Mid Term',
      'Final Term',
      'Monthly Test',
      'Annual Exam'
    ];

    List<dynamic> existingSubjects = currentData['subjects'] ?? [];
    List<Map<String, TextEditingController>> subjectRows = [];

    for (var sub in existingSubjects) {
      subjectRows.add({
        'subject': TextEditingController(text: sub['subjectName'] ?? ''),
        'total':
            TextEditingController(text: sub['totalMarks']?.toString() ?? ''),
        'obtained':
            TextEditingController(text: sub['obtainedMarks']?.toString() ?? ''),
      });
    }

    if (subjectRows.isEmpty) {
      subjectRows.add({
        'subject': TextEditingController(),
        'total': TextEditingController(),
        'obtained': TextEditingController(),
      });
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Update Full Result"),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration:
                            const InputDecoration(labelText: "Student Name"),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: fNameController,
                        decoration:
                            const InputDecoration(labelText: "Father Name"),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: classController,
                        decoration: const InputDecoration(labelText: "Class"),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: sectionController,
                        decoration: const InputDecoration(labelText: "Section"),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: termOptions.contains(termController.text)
                            ? termController.text
                            : null,
                        decoration:
                            const InputDecoration(labelText: "Exam Term"),
                        hint: const Text("Select Exam Term"),
                        items: termOptions.map((String term) {
                          return DropdownMenuItem<String>(
                            value: term,
                            child: Text(term),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() {
                            if (newValue != null) {
                              termController.text = newValue;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: studentPicController,
                        decoration: const InputDecoration(
                            labelText:
                                "Student Picture URL (Cloudinary Secure URL)"),
                      ),
                      const SizedBox(height: 15),
                      const Divider(thickness: 2),
                      const Text("Subjects & Marks",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      ...List.generate(subjectRows.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: subjectRows[index]['subject'],
                                  decoration: const InputDecoration(
                                      labelText: "Subject", isDense: true),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: subjectRows[index]['total'],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: "Total", isDense: true),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: subjectRows[index]['obtained'],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: "Obtained", isDense: true),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red, size: 20),
                                onPressed: () {
                                  setDialogState(() {
                                    subjectRows.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text("Add Subject"),
                        onPressed: () {
                          setDialogState(() {
                            subjectRows.add({
                              'subject': TextEditingController(),
                              'total': TextEditingController(),
                              'obtained': TextEditingController(),
                            });
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700),
                  child: const Text("Save Changes",
                      style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    List<Map<String, dynamic>> updatedSubjects = [];
                    double totalMarksSum = 0;
                    double obtainedMarksSum = 0;

                    for (var row in subjectRows) {
                      String subName = row['subject']!.text.trim();
                      double total = _parseToDouble(row['total']!.text);
                      double obtained = _parseToDouble(row['obtained']!.text);

                      if (subName.isNotEmpty) {
                        updatedSubjects.add({
                          'subjectName': subName,
                          'totalMarks': total,
                          'obtainedMarks': obtained,
                        });
                        totalMarksSum += total;
                        obtainedMarksSum += obtained;
                      }
                    }

                    double percentage = totalMarksSum > 0
                        ? (obtainedMarksSum / totalMarksSum) * 100
                        : 0;

                    await schoolCollection('results').doc(docId).update({
                      'name': nameController.text.trim(),
                      'fName': fNameController.text.trim(),
                      'class': classController.text.trim(),
                      'section': sectionController.text.trim(),
                      'term': termController.text.trim(),
                      'imageUrl': studentPicController.text.trim(),
                      'studentPicUrl': studentPicController.text.trim(),
                      'subjects': updatedSubjects,
                      'grandTotal': totalMarksSum,
                      'grandObtained': obtainedMarksSum,
                      'percentage': percentage.toStringAsFixed(2),
                      'grade': _calculateGrade(percentage),
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("Result updated successfully!")),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(String docId, String studentName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Result"),
        content: Text(
            "Are you sure you want to delete the result for $studentName?"),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
            onPressed: () async {
              await schoolCollection('results').doc(docId).delete();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Result deleted successfully!")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // Generate & Print PDF Report Card with Attendance & Safe Image Loading
  Future<void> _generatePdfCard(
      Map<String, dynamic> data,
      List<Map<String, dynamic>> classStudents,
      int autoRollNo,
      double totalAttendance,
      double presentAttendance) async {
    final pdf = pw.Document();

    String name = data['name'] ?? 'N/A';
    String fName = data['fName'] ?? 'N/A';
    String className = data['class'] ?? 'N/A';
    String section = (data['section'] ?? '').toString();
    String termName = data['term'] ?? 'Exam Report';
    String rollNo = autoRollNo.toString();
    String picUrl = data['imageUrl'] ?? data['studentPicUrl'] ?? '';
    List<dynamic> subjects = data['subjects'] ?? [];

    // ---------------------------------------------------------------
    // FALLBACK: The 'results' document often doesn't carry an image
    // URL (it's only saved on the 'students'/admission record). If
    // it's missing here, look it up from the 'students' collection
    // using studentId (preferred) or name as a match.
    // ---------------------------------------------------------------
    if (picUrl.trim().isEmpty) {
      try {
        String studentId = (data['studentId'] ?? '').toString();
        Map<String, dynamic>? studentData;

        if (studentId.isNotEmpty) {
          // studentId actually stores the Firestore Document ID of the
          // student record, not a field value — so fetch by doc ID.
          DocumentSnapshot studentDoc =
              await schoolCollection('students').doc(studentId).get();

          if (studentDoc.exists) {
            studentData = studentDoc.data() as Map<String, dynamic>?;
            debugPrint("ℹ️ [PDF IMAGE] Found student doc by ID '$studentId'");
          } else {
            debugPrint(
                "⚠️ [PDF IMAGE] No 'students' doc exists with ID '$studentId'. "
                "Falling back to name search.");
          }
        }

        // Fallback: search by name field if doc-ID lookup didn't work
        if (studentData == null) {
          QuerySnapshot studentQuery = await schoolCollection('students')
              .where('name', isEqualTo: name)
              .limit(1)
              .get();
          if (studentQuery.docs.isNotEmpty) {
            studentData =
                studentQuery.docs.first.data() as Map<String, dynamic>;
            debugPrint("ℹ️ [PDF IMAGE] Found student doc by name '$name'");
          }
        }

        if (studentData != null) {
          picUrl = (studentData['imageUrl'] ??
                  studentData['studentPicUrl'] ??
                  studentData['photoUrl'] ??
                  '')
              .toString();
          debugPrint(
              "ℹ️ [PDF IMAGE] picUrl was empty on results doc, fetched from "
              "'students' collection instead: $picUrl");
        } else {
          debugPrint("⚠️ [PDF IMAGE] No matching student found in 'students' "
              "collection for name='$name', studentId='$studentId'");
        }
      } catch (e) {
        debugPrint("❌ [PDF IMAGE] Error while fetching fallback image from "
            "'students' collection: $e");
      }
    }

    double totalMarksSum = 0;
    double obtainedMarksSum = 0;

    for (var sub in subjects) {
      totalMarksSum += _parseToDouble(sub['totalMarks']);
      obtainedMarksSum += _parseToDouble(sub['obtainedMarks']);
    }

    double percentage =
        totalMarksSum > 0 ? (obtainedMarksSum / totalMarksSum) * 100 : 0;

    List<Map<String, dynamic>> rankedList = List.from(classStudents);
    rankedList.sort((a, b) {
      double pA = _parseToDouble(a['percentage']);
      double pB = _parseToDouble(b['percentage']);
      return pB.compareTo(pA);
    });

    int rank =
        rankedList.indexWhere((element) => element['docId'] == data['docId']) +
            1;
    if (rank <= 0) rank = 1;

    // "Promoted / Not Promoted" sirf Final Term ke result card mein
    // dikhna chahiye — First Term, Mid Term, ya Weekly Test mein nahi,
    // kyunke promotion ka faisla sirf final paper ke baad hota hai.
    bool isFinalTerm = termName.trim().toLowerCase() == 'final term';
    bool isPromoted = percentage >= 40.0;
    String promotionStatus =
        isPromoted ? "Promoted to Next Class" : "Not Promoted (Repeat Class)";
    String remarks = isPromoted
        ? "Good performance! Keep up the hard work."
        : "Needs significant improvement in studies.";

    String grade = _calculateGrade(percentage);

    pw.ImageProvider? schoolLogo;
    try {
      schoolLogo = pw.MemoryImage(await getSchoolLogoBytes());
    } catch (e) {
      debugPrint("⚠️ Could not load school logo: $e");
    }

    // ---------------------------------------------------------------
    // Safe & Reliable Image Loading using http.get and pw.MemoryImage
    // Debug logs added below so you can see EXACTLY why an image
    // does or doesn't load. Check your Flutter console/logcat output
    // after generating a PDF.
    // ---------------------------------------------------------------
    pw.ImageProvider? studentPic;
    final String cleanPicUrl = picUrl.trim();

    if (cleanPicUrl.isEmpty) {
      debugPrint("⚠️ [PDF IMAGE] picUrl is EMPTY for student '$name'. "
          "Check that 'imageUrl' or 'studentPicUrl' field is actually "
          "saved in Firestore for this document.");
    } else {
      debugPrint(
          "🔍 [PDF IMAGE] Fetching image for '$name' from: $cleanPicUrl");
      try {
        final uri = Uri.tryParse(cleanPicUrl);
        if (uri == null) {
          debugPrint(
              "❌ [PDF IMAGE] Invalid URL, could not parse: $cleanPicUrl");
        } else {
          final response =
              await http.get(uri).timeout(const Duration(seconds: 20));

          debugPrint("✅ [PDF IMAGE] Response status: ${response.statusCode}, "
              "bytes received: ${response.bodyBytes.length}, "
              "content-type: ${response.headers['content-type']}");

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            try {
              studentPic = pw.MemoryImage(response.bodyBytes);
              debugPrint(
                  "✅ [PDF IMAGE] MemoryImage created successfully for '$name'");
            } catch (decodeError) {
              debugPrint(
                  "❌ [PDF IMAGE] Downloaded bytes but failed to decode as image "
                  "(is the URL actually an image, not an HTML/redirect page?): $decodeError");
            }
          } else {
            debugPrint("❌ [PDF IMAGE] Failed - status ${response.statusCode}. "
                "Body preview: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}");
          }
        }
      } on http.ClientException catch (e) {
        debugPrint(
            "❌ [PDF IMAGE] ClientException (network/connection issue): $e");
      } catch (e) {
        debugPrint("❌ [PDF IMAGE] Unexpected error loading student image: $e");
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Row(
                      children: [
                        if (schoolLogo != null)
                          pw.Container(
                            width: 50,
                            height: 50,
                            child: pw.Image(schoolLogo),
                          ),
                        pw.SizedBox(width: 10),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(currentSchoolDisplayName(),
                                style: pw.TextStyle(
                                    fontSize: 20,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.Text("Student Academic Report Card ($termName)",
                                style: pw.TextStyle(
                                    fontSize: 12, color: PdfColors.teal800)),
                          ],
                        ),
                      ],
                    ),
                    if (studentPic != null)
                      pw.Container(
                        width: 55,
                        height: 55,
                        decoration: pw.BoxDecoration(
                          border:
                              pw.Border.all(color: PdfColors.teal, width: 1.5),
                        ),
                        child: pw.Image(studentPic, fit: pw.BoxFit.cover),
                      )
                    else
                      pw.Container(
                        width: 55,
                        height: 55,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                          border:
                              pw.Border.all(color: PdfColors.grey, width: 1),
                        ),
                        child: pw.Text("No Image",
                            style: const pw.TextStyle(fontSize: 8)),
                      ),
                  ],
                ),
                pw.SizedBox(height: 15),
                pw.Divider(thickness: 1.5, color: PdfColors.teal800),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Student Name: $name",
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text("Father Name: $fName"),
                        pw.SizedBox(height: 4),
                        pw.Text(
                            "Attendance: ${presentAttendance.toInt()} / ${totalAttendance.toInt()} Days"),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                            "Class: $className${section.isNotEmpty ? ' ($section)' : ''}",
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text("Roll No: $rollNo"),
                        pw.SizedBox(height: 4),
                        pw.Text("Class Position: #$rank",
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.teal900)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 15),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(3),
                    1: pw.FlexColumnWidth(1.5),
                    2: pw.FlexColumnWidth(1.5),
                    3: pw.FlexColumnWidth(2),
                    4: pw.FlexColumnWidth(1.2),
                  },
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.teal800),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Subject',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Total',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Obtained',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Percentage',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Grade',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                      ],
                    ),
                    ...subjects.map((sub) {
                      double subTotal = _parseToDouble(sub['totalMarks']);
                      double subObtained = _parseToDouble(sub['obtainedMarks']);
                      double subPer =
                          subTotal > 0 ? (subObtained / subTotal) * 100 : 0;
                      String subGrade = _calculateGrade(subPer);
                      bool isSubFailed = subPer < 40.0;

                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(sub['subjectName'] ?? '',
                                style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(subTotal.toStringAsFixed(0),
                                style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(subObtained.toStringAsFixed(0),
                                style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              "${subPer.toStringAsFixed(1)}%",
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: isSubFailed
                                    ? PdfColors.red700
                                    : PdfColors.black,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              subGrade,
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: isSubFailed
                                    ? PdfColors.red700
                                    : PdfColors.black,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Text("Total: ${totalMarksSum.toStringAsFixed(0)}",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          "Obtained: ${obtainedMarksSum.toStringAsFixed(0)}",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        "%: ${percentage.toStringAsFixed(2)}%",
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: percentage < 40.0
                              ? PdfColors.red700
                              : PdfColors.black,
                        ),
                      ),
                      pw.Text(
                        "Grade: $grade",
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: percentage < 40.0
                              ? PdfColors.red700
                              : PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                        color: isFinalTerm
                            ? (isPromoted
                                ? PdfColors.green700
                                : PdfColors.red700)
                            : (percentage >= 40.0
                                ? PdfColors.green700
                                : PdfColors.red700),
                        width: 1),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (isFinalTerm)
                        pw.Text("Status: $promotionStatus",
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: isPromoted
                                    ? PdfColors.green800
                                    : PdfColors.red800))
                      else
                        pw.Text(
                            "Result: ${percentage >= 40.0 ? 'Pass' : 'Fail'}",
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: percentage >= 40.0
                                    ? PdfColors.green800
                                    : PdfColors.red800)),
                      pw.SizedBox(height: 4),
                      pw.Text("Teacher Remarks: $remarks",
                          style: pw.TextStyle(fontStyle: pw.FontStyle.italic)),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(children: [
                      pw.Container(
                          width: 120, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text("Teacher Signature"),
                    ]),
                    pw.Column(children: [
                      pw.Container(
                          width: 120, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text("Principal Signature"),
                    ]),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    await showPdfPreviewPage(
      context,
      title: "Result Card Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRestricted
            ? "My Class Results (By Exam Term)"
            : "View Results (By Exam Term)"),
        backgroundColor: Colors.teal[800],
      ),
      body: SafeArea(child: StreamBuilder<QuerySnapshot>(
        stream: _resultsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("ERROR loading results:\n${snapshot.error}",
                  style: const TextStyle(color: Colors.red)),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No result records found.",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
            );
          }

          var docs = snapshot.data!.docs;

          Map<String, Map<String, List<Map<String, dynamic>>>>
              groupedByTermAndClass = {};

          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            data['docId'] = doc.id;

            if (!_isAllowedResult(data)) continue;

            String term = data['term'] ?? 'Final Term';
            String rawClass = data['class'] ?? '';
            String formattedClass = _formatClassName(rawClass);

            if (!groupedByTermAndClass.containsKey(term)) {
              groupedByTermAndClass[term] = {};
            }
            if (!groupedByTermAndClass.containsKey(term) ||
                !groupedByTermAndClass[term]!.containsKey(formattedClass)) {
              groupedByTermAndClass[term]![formattedClass] = [];
            }
            groupedByTermAndClass[term]![formattedClass]!.add(data);
          }

          List<String> sortedTerms = groupedByTermAndClass.keys.toList();

          if (sortedTerms.isEmpty) {
            return const Center(
              child: Text("Your class entry record was not found anywhere.",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
            );
          }

          return ListView.builder(
            itemCount: sortedTerms.length,
            itemBuilder: (context, termIndex) {
              String termName = sortedTerms[termIndex];
              Map<String, List<Map<String, dynamic>>> classesInTerm =
                  groupedByTermAndClass[termName]!;

              List<String> sortedClasses = classesInTerm.keys.toList();
              sortedClasses.sort(_compareClasses);

              int totalTermStudents = classesInTerm.values
                  .fold(0, (sum, list) => sum + list.length);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.shade800,
                    child: const Icon(Icons.assignment,
                        color: Colors.white, size: 20),
                  ),
                  title: Text(
                    termName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.teal[900],
                    ),
                  ),
                  subtitle: Text("Total Records: $totalTermStudents students"),
                  children: sortedClasses.map((className) {
                    List<Map<String, dynamic>> studentsInClass =
                        classesInTerm[className]!;

                    studentsInClass.sort((a, b) {
                      String secA =
                          (a['section'] ?? '').toString().toLowerCase();
                      String secB =
                          (b['section'] ?? '').toString().toLowerCase();
                      if (secA != secB) return secA.compareTo(secB);
                      String nameA = (a['name'] ?? '').toString().toLowerCase();
                      String nameB = (b['name'] ?? '').toString().toLowerCase();
                      return nameA.compareTo(nameB);
                    });

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 2.0),
                      child: Card(
                        elevation: 1,
                        color: Colors.teal.shade50.withValues(alpha: 0.5),
                        child: ExpansionTile(
                          title: Text(
                            "Class: $className",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.teal[800],
                            ),
                          ),
                          subtitle: Text(
                              "Students in Class: ${studentsInClass.length}"),
                          children:
                              List.generate(studentsInClass.length, (index) {
                            var data = studentsInClass[index];
                            String docId = data['docId'];
                            String name = data['name'] ?? 'N/A';
                            String fName = data['fName'] ?? 'N/A';
                            String section = (data['section'] ?? '').toString();
                            String studentId = data['studentId'] ?? '';
                            String picUrl =
                                data['imageUrl'] ?? data['studentPicUrl'] ?? '';
                            double percentage =
                                _parseToDouble(data['percentage']);
                            List<dynamic> subjects = data['subjects'] ?? [];

                            int autoRollNo = index + 1;

                            return FutureBuilder<QuerySnapshot>(
                              future: studentId.isNotEmpty
                                  ? schoolCollection('attendance')
                                      .where('studentId', isEqualTo: studentId)
                                      .get()
                                  : schoolCollection('attendance')
                                      .where('name', isEqualTo: name)
                                      .get(),
                              builder: (context, attSnapshot) {
                                double totalAttendance = 0;
                                double presentAttendance = 0;

                                if (attSnapshot.hasData &&
                                    attSnapshot.data!.docs.isNotEmpty) {
                                  for (var attDoc in attSnapshot.data!.docs) {
                                    var attData =
                                        attDoc.data() as Map<String, dynamic>?;
                                    if (attData != null) {
                                      totalAttendance += 1.0;
                                      String status = attData['status'] ?? '';
                                      if (status == 'Present') {
                                        presentAttendance += 1.0;
                                      }
                                    }
                                  }

                                  if (totalAttendance == 0) {
                                    var attData = attSnapshot.data!.docs.first
                                        .data() as Map<String, dynamic>?;
                                    if (attData != null) {
                                      totalAttendance = _parseToDouble(
                                          attData['totalAttendance'] ??
                                              attData['totalDays'] ??
                                              0);
                                      presentAttendance = _parseToDouble(
                                          attData['presentAttendance'] ??
                                              attData['presentDays'] ??
                                              0);
                                    }
                                  }
                                }

                                return ExpansionTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.teal.shade100,
                                    backgroundImage: picUrl.isNotEmpty
                                        ? NetworkImage(picUrl)
                                        : null,
                                    child: picUrl.isEmpty
                                        ? Text(
                                            "#$autoRollNo",
                                            style: TextStyle(
                                                color: Colors.teal.shade800,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11),
                                          )
                                        : null,
                                  ),
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                    "Roll No: $autoRollNo${section.isNotEmpty ? ' | Section: $section' : ''} | Father: $fName\nAttendance: ${presentAttendance.toInt()}/${totalAttendance.toInt()} | %: ${percentage.toStringAsFixed(1)}%",
                                    style: TextStyle(
                                      color: percentage < 40.0
                                          ? Colors.red
                                          : Colors.black87,
                                      fontWeight: percentage < 40.0
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.picture_as_pdf,
                                            color: Colors.teal),
                                        tooltip: "Download Report Card",
                                        onPressed: () => _generatePdfCard(
                                            data,
                                            studentsInClass,
                                            autoRollNo,
                                            totalAttendance,
                                            presentAttendance),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _showUpdateDialog(docId, data);
                                          } else if (value == 'delete') {
                                            _confirmDelete(docId, name);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text("Edit Result"),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text("Delete Result"),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0, vertical: 8.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text("Subject Breakdown:",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                          const SizedBox(height: 4),
                                          ...subjects.map((sub) {
                                            double sTotal = _parseToDouble(
                                                sub['totalMarks']);
                                            double sObtained = _parseToDouble(
                                                sub['obtainedMarks']);
                                            double sPer = sTotal > 0
                                                ? (sObtained / sTotal) * 100
                                                : 0;
                                            String sGrade =
                                                _calculateGrade(sPer);
                                            bool isFailed = sPer < 40.0;

                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 2.0),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                        sub['subjectName'] ??
                                                            '',
                                                        style: const TextStyle(
                                                            fontSize: 12)),
                                                  ),
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                        "Marks: ${sObtained.toStringAsFixed(0)}/${sTotal.toStringAsFixed(0)}",
                                                        style: const TextStyle(
                                                            fontSize: 12)),
                                                  ),
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      "Per: ${sPer.toStringAsFixed(1)}%",
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isFailed
                                                            ? Colors.red
                                                            : Colors.black,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      "Grade: $sGrade",
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isFailed
                                                            ? Colors.red
                                                            : Colors.black,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                          const Divider(),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      )),
    );
  }
}
