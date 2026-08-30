import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'student_detail_page.dart';
import 'package:flutter/foundation.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class ClassDetailPage extends StatefulWidget {
  final String className;
  const ClassDetailPage({super.key, required this.className});

  @override
  State<ClassDetailPage> createState() => _ClassDetailPageState();
}

class _ClassDetailPageState extends State<ClassDetailPage> {
  String get className => widget.className;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Fixed academic order (Playgroup through Ten)[cite: 1]
  static const List<String> _baseClassesOrder = [
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
    'Ten'
  ];

  // Class sorting function: keeps New/Custom classes at the top (-1), rest in fixed order[cite: 1]
  int _compareClasses(String? classA, String? classB) {
    String a = classA ?? '';
    String b = classB ?? '';

    final int ai = _baseClassesOrder.indexOf(a);
    final int bi = _baseClassesOrder.indexOf(b);

    if (ai == -1 && bi == -1) return a.compareTo(b);
    if (ai == -1) return -1; // Nayi class sabse upar[cite: 1]
    if (bi == -1) return 1;

    return ai.compareTo(bi);
  }

  // Delete function[cite: 2]
  void _showDeleteDialog(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Student"),
        content: const Text(
            "Are you sure? This will remove the student and their specific fee records."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              try {
                await schoolCollection('students')
                    .doc(docId)
                    .delete();
                await schoolCollection('fee_structures')
                    .doc(docId)
                    .delete();

                var historyQuery = await schoolCollection('fee_history')
                    .where('studentId', isEqualTo: docId)
                    .get();

                for (var doc in historyQuery.docs) {
                  await doc.reference.delete();
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Student and his records deleted!")),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error deleting: $e")),
                );
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // PDF Generation with proper class sorting[cite: 2]
  Future<void> _generateStudentsListPdf(
    BuildContext context,
    List<QueryDocumentSnapshot> docs,
    String title,
  ) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No students found for print."),
        ),
      );
      return;
    }

    docs.sort((a, b) {
      final dataA = a.data() as Map<String, dynamic>;
      final dataB = b.data() as Map<String, dynamic>;

      final classCompare = _compareClasses(
        dataA['class'],
        dataB['class'],
      );

      if (classCompare != 0) return classCompare;

      return (dataA['name'] ?? '').compareTo(
        dataB['name'] ?? '',
      );
    });

    final pdf = pw.Document();

    final List<List<String>> rows = List.generate(
      docs.length,
      (i) {
        final data = docs[i].data() as Map<String, dynamic>;

        return [
          '${i + 1}',
          data['name']?.toString() ?? '',
          data['fName']?.toString() ?? '',
          data['class']?.toString() ?? '',
          data['section']?.toString() ?? '',
          data['contactNo']?.toString() ?? '',
        ];
      },
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              currentSchoolDisplayName(),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              title,
              style: const pw.TextStyle(
                fontSize: 13,
              ),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.Table.fromTextArray(
            headers: [
              '#',
              'Name',
              'Father Name',
              'Class',
              'Section',
              'Contact',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
            cellStyle: const pw.TextStyle(
              fontSize: 9,
            ),
            border: pw.TableBorder.all(
              color: PdfColors.black,
              width: 0.5,
            ),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.5),
            },
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            "Total Students: ${docs.length}",
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    // Save the PDF in memory
    final pdfBytes = await pdf.save();

    if (!context.mounted) return;

    // =========================
    // WEB
    // =========================
    if (kIsWeb) {
      await showPdfPreviewPage(
        context,
        title: title,
        build: (PdfPageFormat format) async => pdfBytes,
      );

      return;
    }

    // =========================
    // ANDROID / IOS
    // =========================
    final output = await getTemporaryDirectory();

    final file = File(
      "${output.path}/students_${title.replaceAll(' ', '_')}.pdf",
    );

    await file.writeAsBytes(pdfBytes);

    if (!context.mounted) return;

    await _showPdfActionSheet(
      context,
      file,
      title,
    );
  }

  // Preview and Send both options in one place
  Future<void> _showPdfActionSheet(
      BuildContext context, File file, String shareText) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text("Preview"),
              onTap: () async {
                Navigator.pop(context);
                await showPdfPreviewPage(
                  context,
                  title: shareText,
                  shareFileName: "${shareText.replaceAll(' ', '_')}.pdf",
                  build: (format) async => file.readAsBytes(),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text("Send"),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await Share.shareXFiles([XFile(file.path)],
                      text: shareText);
                } catch (e) {
                  // On Windows (especially when not packaged as MSIX),
                  // share_plus's native "Share" sheet isn't available
                  // and this can fail — tell the user where the file
                  // was saved so they can attach it manually.
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          "Direct Send is not supported on this device. "
                          "File saved at:\n${file.path}"),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 6),
                    ));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentTile(BuildContext context, QueryDocumentSnapshot doc,
      Map<String, dynamic> data) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: data['imageUrl'] != null && data['imageUrl'] != ""
              ? NetworkImage(data['imageUrl'])
              : null,
          child: data['imageUrl'] == "" || data['imageUrl'] == null
              ? const Icon(Icons.person)
              : null,
        ),
        title: Text(
          data['name'] ?? "No Name",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                "Father: ${data['fName'] ?? 'N/A'} | Class: ${data['class'] ?? 'N/A'}"),
            Text(
              "Family ID: ${data['familyId'] ?? 'N/A'}",
              style: TextStyle(
                color: Colors.teal[800],
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(data['gender'] ?? "", style: const TextStyle(fontSize: 12)),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  StudentDetailPage(docId: doc.id, data: data),
            ),
          );
        },
        onLongPress: () => _showDeleteDialog(context, doc.id),
      ),
    );
  }

  // Search bar — only shown at the top of the "All Students" page,
  // so any student can be searched by name, father name, class,
  // section, contact number, or family ID.
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: "Search students by name, father name, class...",
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
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Query query = schoolCollection('students')
        .where('status', isEqualTo: 'active');

    if (className != 'All') {
      query = query.where('class', isEqualTo: className);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            className == 'All' ? "All Active Students" : "Class: $className"),
        backgroundColor: Colors.teal[800],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No active students found."));
          }

          // Filter using the search bar (matches if the query is found
          // in any of: name, father name, class, section, contact number,
          // or family ID — show the student if it matches).
          if (_searchQuery.trim().isNotEmpty) {
            final searchTerm = _searchQuery.trim().toLowerCase();
            docs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final fields = [
                data['name'],
                data['fName'],
                data['class'],
                data['section'],
                data['contactNo'],
                data['familyId'],
                data['rollNo'],
              ];
              return fields.any((f) =>
                  f != null &&
                  f.toString().toLowerCase().contains(searchTerm));
            }).toList();
          }

          // Sorting by class and then by name
          docs.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;

            int classCompare = _compareClasses(dataA['class'], dataB['class']);
            if (classCompare != 0) return classCompare;

            return (dataA['name'] ?? '').compareTo(dataB['name'] ?? '');
          });

          if (docs.isEmpty) {
            return Column(
              children: [
                _buildSearchBar(),
                const Expanded(
                  child: Center(
                    child: Text("No students match your search."),
                  ),
                ),
              ],
            );
          }

          int total = docs.length;
          int boys = docs
              .where(
                  (d) => (d.data() as Map<String, dynamic>)['gender'] == 'Male')
              .length;
          int girls = docs
              .where((d) =>
                  (d.data() as Map<String, dynamic>)['gender'] == 'Female')
              .length;

          Map<String, List<QueryDocumentSnapshot>> groupedData = {};

          if (className == 'All') {
            for (var doc in docs) {
              var data = doc.data() as Map<String, dynamic>;
              String cls = data['class']?.toString() ?? '';
              if (cls.isEmpty || cls == 'Not Selected') {
                cls = 'Unassigned Class';
              }
              groupedData.putIfAbsent(cls, () => []).add(doc);
            }
          } else {
            for (var doc in docs) {
              var data = doc.data() as Map<String, dynamic>;
              String sec = data['section']?.toString() ?? '';
              if (sec.isEmpty || sec == 'Not Selected') sec = 'No Section';
              groupedData.putIfAbsent(sec, () => []).add(doc);
            }
          }

          bool hasGroups = groupedData.isNotEmpty;

          return Column(
            children: [
              if (className == 'All') _buildSearchBar(),
              Container(
                padding: const EdgeInsets.all(15),
                color: Colors.teal[100],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text("Total: $total",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("Boys: $boys",
                        style: const TextStyle(
                            color: Colors.blue, fontWeight: FontWeight.bold)),
                    Text("Girls: $girls",
                        style: const TextStyle(
                            color: Colors.pink, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      tooltip: "Print / Share PDF",
                      onPressed: () => _generateStudentsListPdf(
                        context,
                        docs,
                        className == 'All'
                            ? "All Active Students"
                            : "Class: $className",
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: hasGroups
                    ? ListView(
                        children: groupedData.entries.map((entry) {
                          String groupName = entry.key;
                          List<QueryDocumentSnapshot> groupDocs = entry.value;
                          return ExpansionTile(
                            initiallyExpanded: className != 'All',
                            title: Text(
                              className == 'All'
                                  ? "Class: $groupName"
                                  : "Section: $groupName",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal),
                            ),
                            subtitle: Text("${groupDocs.length} student(s)"),
                            children: groupDocs.map((doc) {
                              var data = doc.data() as Map<String, dynamic>;
                              return _buildStudentTile(context, doc, data);
                            }).toList(),
                          );
                        }).toList(),
                      )
                    : ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          var doc = docs[index];
                          var data = doc.data() as Map<String, dynamic>;
                          return _buildStudentTile(context, doc, data);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
