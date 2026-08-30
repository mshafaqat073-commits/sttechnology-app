import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

// ============================================================
class StudentReportSearchPage extends StatefulWidget {
  const StudentReportSearchPage({super.key});

  @override
  State<StudentReportSearchPage> createState() =>
      _StudentReportSearchPageState();
}

class _StudentReportSearchPageState extends State<StudentReportSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Build the stream once and keep it, so it doesn't get recreated
  // (via setState) every time something is typed in the search box.
  late final Stream<QuerySnapshot> _studentsStream =
      schoolCollection('students').snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Search Student Reports"),
        backgroundColor: Colors.teal[800],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Type student name to search...",
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
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: _searchQuery.isEmpty
                ? const Center(
                    child: Text(
                      "Start typing a student's name to search",
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: _studentsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text("Error: ${snapshot.error}",
                              style: const TextStyle(color: Colors.red)),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text("No students found."));
                      }

                      final queryWords = _searchQuery
                          .split(RegExp(r'\s+'))
                          .where((w) => w.isNotEmpty)
                          .toList();

                      final filtered = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name =
                            (data['name'] ?? '').toString().toLowerCase();
                        return queryWords.every((word) => name.contains(word));
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text("No matching students.",
                              style: TextStyle(color: Colors.grey)),
                        );
                      }

                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final name = (data['name'] ?? 'N/A').toString();
                          final fName = (data['fName'] ?? '').toString();
                          final className = (data['class'] ?? '').toString();
                          final sectionName =
                              (data['section'] ?? '').toString();
                          final picUrl = (data['imageUrl'] ??
                                  data['studentPicUrl'] ??
                                  data['photoUrl'] ??
                                  '')
                              .toString();

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            elevation: 1,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.teal.shade100,
                                backgroundImage: picUrl.isNotEmpty
                                    ? NetworkImage(picUrl)
                                    : null,
                                child: picUrl.isEmpty
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : "?",
                                        style: TextStyle(
                                            color: Colors.teal.shade800,
                                            fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                [
                                  if (className.isNotEmpty)
                                    sectionName.isNotEmpty
                                        ? "Class: $className - $sectionName"
                                        : "Class: $className",
                                  if (fName.isNotEmpty) "Father: $fName",
                                ].join("  |  "),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => StudentFullReportPage(
                                      studentDocId: doc.id,
                                      studentName: name,
                                    ),
                                  ),
                                );
                              },
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
}

// ============================================================
// PAGE 2: Full result history for the selected student
// ============================================================
class StudentFullReportPage extends StatefulWidget {
  final String studentDocId;
  final String studentName;

  const StudentFullReportPage({
    super.key,
    required this.studentDocId,
    required this.studentName,
  });

  @override
  State<StudentFullReportPage> createState() => _StudentFullReportPageState();
}

class _StudentFullReportPageState extends State<StudentFullReportPage> {
  List<QueryDocumentSnapshot>? _resultDocs;
  bool _loading = true;
  bool _generatingPdf = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  double _parseToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
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

  Future<void> _loadResults() async {
    try {
      var snapshot = await schoolCollection('results')
          .where('studentId', isEqualTo: widget.studentDocId)
          .get();

      var docs = snapshot.docs;

      if (docs.isEmpty) {
        var nameSnapshot = await schoolCollection('results')
            .where('name', isEqualTo: widget.studentName)
            .get();
        docs = nameSnapshot.docs;
      }

      if (mounted) {
        setState(() {
          _resultDocs = docs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ==========================================================
  // Generate ONE consolidated PDF report containing a summary
  // table of all exams/terms, overall stats, and student picture.
  // ==========================================================
  Future<void> _generateFullPdf() async {
    if (_resultDocs == null || _resultDocs!.isEmpty) return;

    setState(() => _generatingPdf = true);

    try {
      final pdf = pw.Document();

      pw.ImageProvider? schoolLogo;
      try {
        schoolLogo = pw.MemoryImage(await getSchoolLogoBytes());
      } catch (e) {
        debugPrint("⚠️ Could not load school logo: $e");
      }

      String picUrl = '';
      try {
        DocumentSnapshot studentDoc =
            await schoolCollection('students').doc(widget.studentDocId).get();
        if (studentDoc.exists) {
          var sd = studentDoc.data() as Map<String, dynamic>?;
          picUrl =
              (sd?['imageUrl'] ?? sd?['studentPicUrl'] ?? sd?['photoUrl'] ?? '')
                  .toString();
        }
        if (picUrl.trim().isEmpty) {
          var q = await schoolCollection('students')
              .where('name', isEqualTo: widget.studentName)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            var sd = q.docs.first.data();
            picUrl =
                (sd['imageUrl'] ?? sd['studentPicUrl'] ?? sd['photoUrl'] ?? '')
                    .toString();
          }
        }
        if (picUrl.trim().isEmpty) {
          var firstData = _resultDocs!.first.data() as Map<String, dynamic>;
          picUrl = (firstData['imageUrl'] ?? firstData['studentPicUrl'] ?? '')
              .toString();
        }
      } catch (e) {
        debugPrint("❌ [CONSOLIDATED PDF] Error resolving student picture: $e");
      }

      pw.ImageProvider? studentPic;
      final cleanPicUrl = picUrl.trim();
      if (cleanPicUrl.isNotEmpty) {
        try {
          final uri = Uri.tryParse(cleanPicUrl);
          if (uri != null) {
            final response =
                await http.get(uri).timeout(const Duration(seconds: 20));
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              studentPic = pw.MemoryImage(response.bodyBytes);
            }
          }
        } catch (e) {
          debugPrint("❌ [CONSOLIDATED PDF] Error loading student picture: $e");
        }
      }

      var latestData = _resultDocs!.first.data() as Map<String, dynamic>;
      String fName = (latestData['fName'] ?? 'N/A').toString();
      String className = (latestData['class'] ?? 'N/A').toString();
      String sectionName = (latestData['section'] ?? '').toString();

      double grandTotalMarks = 0;
      double grandObtainedMarks = 0;

      List<Map<String, dynamic>> summaryRows = [];

      for (var doc in _resultDocs!) {
        var data = doc.data() as Map<String, dynamic>;
        String term = (data['term'] ?? 'Exam').toString();
        List<dynamic> subjects = data['subjects'] ?? [];

        double termTotal = 0;
        double termObtained = 0;
        for (var sub in subjects) {
          termTotal += _parseToDouble(sub['totalMarks']);
          termObtained += _parseToDouble(sub['obtainedMarks']);
        }

        grandTotalMarks += termTotal;
        grandObtainedMarks += termObtained;

        double termPer = termTotal > 0 ? (termObtained / termTotal) * 100 : 0;
        String termGrade = _calculateGrade(termPer);

        summaryRows.add({
          'term': term,
          'total': termTotal,
          'obtained': termObtained,
          'percentage': termPer,
          'grade': termGrade,
        });
      }

      double overallPercentage = grandTotalMarks > 0
          ? (grandObtainedMarks / grandTotalMarks) * 100
          : 0;
      String overallGrade = _calculateGrade(overallPercentage);
      bool isPromoted = overallPercentage >= 40.0;
      String promotionStatus =
          isPromoted ? "Promoted to Next Class" : "Not Promoted";

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
                              pw.Text("Consolidated Academic Progress Report",
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
                            border: pw.Border.all(
                                color: PdfColors.teal, width: 1.5),
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
                          pw.Text("Student Name: ${widget.studentName}",
                              style:
                                  pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text("Father Name: $fName"),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text("Class: $className",
                              style:
                                  pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          if (sectionName.isNotEmpty)
                            pw.Text("Section: $sectionName",
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text("Examination Summary Table",
                      style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal800)),
                  pw.SizedBox(height: 8),
                  pw.Table(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey400, width: 0.5),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(3),
                      1: pw.FlexColumnWidth(2),
                      2: pw.FlexColumnWidth(2),
                      3: pw.FlexColumnWidth(2),
                      4: pw.FlexColumnWidth(1.5),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.teal800),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('Exam / Term',
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('Total Marks',
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
                      ...summaryRows.map((row) {
                        bool isFailed = row['percentage'] < 40.0;
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(row['term'],
                                  style: const pw.TextStyle(fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                  (row['total'] as double).toStringAsFixed(0),
                                  style: const pw.TextStyle(fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                  (row['obtained'] as double)
                                      .toStringAsFixed(0),
                                  style: const pw.TextStyle(fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                "${(row['percentage'] as double).toStringAsFixed(1)}%",
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: isFailed
                                      ? PdfColors.red700
                                      : PdfColors.black,
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                row['grade'],
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: isFailed
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
                  pw.SizedBox(height: 15),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("Grand Total",
                                style: pw.TextStyle(
                                    fontSize: 9, color: PdfColors.grey700)),
                            pw.SizedBox(height: 2),
                            pw.Text(
                                "${grandObtainedMarks.toStringAsFixed(0)} / ${grandTotalMarks.toStringAsFixed(0)}",
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 11)),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("Overall Percentage",
                                style: pw.TextStyle(
                                    fontSize: 9, color: PdfColors.grey700)),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              "${overallPercentage.toStringAsFixed(2)}%",
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                                color: overallPercentage < 40.0
                                    ? PdfColors.red700
                                    : PdfColors.black,
                              ),
                            ),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("Overall Grade",
                                style: pw.TextStyle(
                                    fontSize: 9, color: PdfColors.grey700)),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              overallGrade,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                                color: overallPercentage < 40.0
                                    ? PdfColors.red700
                                    : PdfColors.black,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 15),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                          color: isPromoted
                              ? PdfColors.green700
                              : PdfColors.red700,
                          width: 1),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Overall Status: $promotionStatus",
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: isPromoted
                                    ? PdfColors.green800
                                    : PdfColors.red800)),
                        pw.SizedBox(height: 4),
                        pw.Text(
                            isPromoted
                                ? "Remarks: Excellent overall academic progress maintained throughout the terms."
                                : "Remarks: Needs focused attention to improve overall performance.",
                            style: pw.TextStyle(
                                fontStyle: pw.FontStyle.italic, fontSize: 10)),
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
                        pw.Text("Teacher Signature",
                            style: const pw.TextStyle(fontSize: 10)),
                      ]),
                      pw.Column(children: [
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 5),
                        pw.Text("Principal Signature",
                            style: const pw.TextStyle(fontSize: 10)),
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
        title: "Report Preview",
        shareFileName: "student_report.pdf",
        build: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      debugPrint("❌ [CONSOLIDATED PDF] Error generating PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to generate PDF: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.studentName} - Full Report"),
        backgroundColor: Colors.teal[800],
        actions: [
          if (!_loading && _resultDocs != null && _resultDocs!.isNotEmpty)
            IconButton(
              icon: _generatingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf),
              tooltip: "Download Consolidated PDF Report",
              onPressed: _generatingPdf ? null : _generateFullPdf,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text("Error: $_errorMessage",
                      style: const TextStyle(color: Colors.red)),
                )
              : (_resultDocs == null || _resultDocs!.isEmpty)
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text(
                          "No result records found for this student.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  : _buildResultsList(_resultDocs!),
    );
  }

  Widget _buildResultsList(List<QueryDocumentSnapshot> docs) {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        String term = (data['term'] ?? 'Exam').toString();
        String className = (data['class'] ?? '').toString();
        String sectionName = (data['section'] ?? '').toString();
        List<dynamic> subjects = data['subjects'] ?? [];

        double totalMarksSum = 0;
        double obtainedMarksSum = 0;
        for (var sub in subjects) {
          totalMarksSum += _parseToDouble(sub['totalMarks']);
          obtainedMarksSum += _parseToDouble(sub['obtainedMarks']);
        }

        double percentage = totalMarksSum > 0
            ? (obtainedMarksSum / totalMarksSum) * 100
            : _parseToDouble(data['percentage']);

        String grade =
            (data['grade'] != null && data['grade'].toString().isNotEmpty)
                ? data['grade'].toString()
                : _calculateGrade(percentage);

        bool isPromoted = percentage >= 40.0;
        String remarks = isPromoted
            ? "Good performance! Keep up the hard work."
            : "Needs significant improvement in studies.";

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor:
                  percentage < 40 ? Colors.red.shade100 : Colors.teal.shade100,
              child: Text(
                grade,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: percentage < 40
                        ? Colors.red.shade800
                        : Colors.teal.shade800),
              ),
            ),
            title:
                Text(term, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              sectionName.isNotEmpty
                  ? "Class: $className - $sectionName  |  Percentage: ${percentage.toStringAsFixed(1)}%"
                  : "Class: $className  |  Percentage: ${percentage.toStringAsFixed(1)}%",
              style: TextStyle(
                color: percentage < 40 ? Colors.red : Colors.black87,
                fontWeight:
                    percentage < 40 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Subject Breakdown:",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...subjects.map((sub) {
                      double sTotal = _parseToDouble(sub['totalMarks']);
                      double sObtained = _parseToDouble(sub['obtainedMarks']);
                      double sPer = sTotal > 0 ? (sObtained / sTotal) * 100 : 0;
                      String sGrade = _calculateGrade(sPer);
                      bool isFailed = sPer < 40.0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(sub['subjectName'] ?? '',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                  "${sObtained.toStringAsFixed(0)}/${sTotal.toStringAsFixed(0)}",
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                "${sPer.toStringAsFixed(1)}%",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isFailed ? Colors.red : Colors.black,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                sGrade,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isFailed ? Colors.red : Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Text(
                      "Total: ${totalMarksSum.toStringAsFixed(0)}   |   Obtained: ${obtainedMarksSum.toStringAsFixed(0)}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPromoted
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isPromoted ? Colors.green : Colors.red,
                          width: 0.7,
                        ),
                      ),
                      child: Text(
                        "Remarks: $remarks",
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                          color: isPromoted
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
