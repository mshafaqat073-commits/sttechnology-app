import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart'
    as http; // Network image load karne ke liye zaroori hai
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class SLCGenerator extends StatefulWidget {
  const SLCGenerator({super.key});
  @override
  State<SLCGenerator> createState() => _SLCGeneratorState();
}

class _SLCGeneratorState extends State<SLCGenerator> {
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String> _getNextGrNumber() async {
    try {
      var snapshot = await schoolCollection('SLC').get();
      if (snapshot.docs.isEmpty) return "AEP1000";
      int maxNumber = 1000;
      for (var doc in snapshot.docs) {
        var grValue = doc.get('grNumber');
        if (grValue != null) {
          String gr = grValue.toString();
          int currentNum =
              int.tryParse(gr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1000;
          if (currentNum > maxNumber) {
            maxNumber = currentNum;
          }
        }
      }
      return "AEP${maxNumber + 1}";
    } catch (e) {
      debugPrint("Error generating GR: $e");
      return "AEP1000";
    }
  }

  Future<void> _generateSLC(DocumentSnapshot doc) async {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    String newGrNumber = await _getNextGrNumber();

    // Database saving logic (ensuring correct grNumber)
    await schoolCollection('SLC').doc(doc.id).set({
      ...data,
      'grNumber': newGrNumber,
      'date': FieldValue.serverTimestamp(),
    });

    await schoolCollection('students').doc(doc.id).update({
      'status': 'left',
    });

    // Student Picture load karne ki koshish agar database mein mojood ho (imageUrl ya photo field)
    pw.ImageProvider? studentImage;
    String? imgUrl = data['imageUrl'] ?? data['photo'] ?? data['image'];
    if (imgUrl != null && imgUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(imgUrl));
        if (response.statusCode == 200) {
          studentImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint("Error loading student image for PDF: $e");
      }
    }

    // Settings me jo school name set kiya gaya hai wahi PDF par aaye —
    // pehle ye yahan hardcoded "AEP SCHOOL SYSTEM" tha, is liye Settings
    // se naam badalne ka SLC par koi asar nahi hota tha.
    final String schoolName = currentSchoolDisplayName();

    // PDF Design
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 4)),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey, width: 1)),
              child: pw.Column(children: [
                // Header with optional Student Picture
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left spacer or small info if needed
                    pw.SizedBox(width: 60, height: 60),
                    pw.Column(
                      children: [
                        pw.Text(schoolName.toUpperCase(),
                            style: pw.TextStyle(
                                fontSize: 26, fontWeight: pw.FontWeight.bold)),
                        pw.Text("Conceptual Study",
                            style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    // Student Picture Box
                    ContainerOrPlaceholder(studentImage),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Center(
                    child: pw.Text("SCHOOL LEAVING CERTIFICATE",
                        style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            decoration: pw.TextDecoration.underline))),
                pw.SizedBox(height: 20),
                pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("GR NUMBER: $newGrNumber",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(border: pw.Border.all()),
                          child: pw.Text("REGISTRATION NO: 3537/G-I")),
                    ]),
                pw.SizedBox(height: 30),

                // Arrange Data in Table Format for perfect alignment
                pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(2)
                  },
                  children: [
                    pw.TableRow(children: [
                      pw.Text("Student Name:"),
                      pw.Text("${data['name'] ?? ''}",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold))
                    ]),
                    pw.TableRow(children: [
                      pw.SizedBox(height: 10),
                      pw.SizedBox(height: 10)
                    ]),
                    pw.TableRow(children: [
                      pw.Text("Son/Daughter of:"),
                      pw.Text("${data['fName'] ?? ''}",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold))
                    ]),
                    pw.TableRow(children: [
                      pw.SizedBox(height: 10),
                      pw.SizedBox(height: 10)
                    ]),
                    pw.TableRow(children: [
                      pw.Text("Date of Birth:"),
                      pw.Text("${data['dob'] ?? ''}")
                    ]),
                    pw.TableRow(children: [
                      pw.SizedBox(height: 10),
                      pw.SizedBox(height: 10)
                    ]),
                    pw.TableRow(children: [
                      pw.Text("Class Cleared:"),
                      pw.Text("${data['class'] ?? ''}")
                    ]),
                    pw.TableRow(children: [
                      pw.SizedBox(height: 10),
                      pw.SizedBox(height: 10)
                    ]),
                    pw.TableRow(children: [
                      pw.Text("Character:"),
                      pw.Text("Very Good")
                    ]),
                  ],
                ),

                pw.SizedBox(height: 50),
                pw.Text(
                    "This is to certify that the above student has left the $schoolName and bears a good character. We wish the student ever success in their future education and career",
                    style: const pw.TextStyle(fontSize: 12)),

                pw.Spacer(),

                pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Principal Signature\n____________"),
                      pw.Text(
                          "Date: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}\n____________"),
                    ]),
                pw.SizedBox(height: 20),
                if (currentSchoolContactNumber().isNotEmpty)
                  pw.Center(
                      child: pw.Text(
                          "Near qazi shop badliwala KHB (${currentSchoolContactNumber()})",
                          style: const pw.TextStyle(fontSize: 10))),
              ]),
            ),
          );
        },
      ),
    );

    await showPdfPreviewPage(context, title: "School Leaving Certificate Preview", build: (format) async => pdf.save());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("SLC Generated!")));
    }
  }

  // Helper widget for PDF image container
  pw.Widget ContainerOrPlaceholder(pw.ImageProvider? image) {
    if (image != null) {
      return pw.Container(
        width: 60,
        height: 70,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1),
        ),
        child: pw.Image(image, fit: pw.BoxFit.cover),
      );
    } else {
      return pw.Container(
        width: 60,
        height: 70,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey, width: 1),
        ),
        child: pw.Center(
            child: pw.Text("Photo", style: const pw.TextStyle(fontSize: 8))),
      );
    }
  }

  void _showHistoryOptions(DocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("History Options"),
        content: const Text(
            "Do you want to restore this or permanently delete it?"),
        actions: [
          TextButton(
            onPressed: () async {
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              // Duplicate se bachne ke liye .add ki bajaye .doc(doc.id).set() use kiya hai
              await schoolCollection('students')
                  .doc(doc.id)
                  .set({
                ...data,
                'status': 'active', // wapas active status kar diya
              });
              await doc.reference.delete(); // SLC se hata diya
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Student Successfully Restored!")));
              }
            },
            child: const Text("Restore"),
          ),
          TextButton(
            onPressed: () async {
              await doc.reference.delete();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Permanently Deleted!")));
              }
            },
            child: const Text("Delete Permanently",
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SLC Generator")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Real-time Search Field
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: "Search Student by Name (Real-time)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 15),

            // Active Students Live List based on search query
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Active Students Search Results:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(height: 5),

            SizedBox(
              height: 200,
              child: StreamBuilder<QuerySnapshot>(
                stream: schoolCollection('students')
                    .where('status', isEqualTo: 'active')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var allDocs = snapshot.data!.docs;

                  // Word-by-word local filtering
                  var filteredDocs = allDocs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    var name = (data['name'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery);
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return const Center(
                        child: Text("No active student found."));
                  }

                  return ListView.builder(
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      var data =
                          filteredDocs[index].data() as Map<String, dynamic>;
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                              child: Text(data['name'] != null &&
                                      data['name'].isNotEmpty
                                  ? data['name'][0]
                                  : '?')),
                          title: Text(data['name'] ?? 'No Name',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              "Class: ${data['class'] ?? 'N/A'} | F/Name: ${data['fName'] ?? 'N/A'}"),
                          trailing: const Icon(Icons.picture_as_pdf,
                              color: Colors.deepOrange),
                          onTap: () => _generateSLC(filteredDocs[index]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const Divider(thickness: 2),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("History Records (Long Press to Restore/Delete)",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(height: 5),

            // History Records Stream
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: schoolCollection('SLC')
                    .orderBy('date', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("No history found."));
                  }

                  return ListView.builder(
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, i) {
                      var doc = snapshot.data!.docs[i];
                      var data = doc.data() as Map<String, dynamic>;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading:
                              const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(data['name'] ?? 'No Name'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("GR: ${data['grNumber'] ?? 'N/A'}"),
                              Text(
                                  "Father: ${data['fName'] ?? 'N/A'} | Form: ${data['formNo'] ?? 'N/A'}"),
                            ],
                          ),
                          isThreeLine: true,
                          onLongPress: () => _showHistoryOptions(doc),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
