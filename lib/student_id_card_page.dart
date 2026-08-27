import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'package:printing/printing.dart' show networkImage;

class StudentIdCardPage extends StatefulWidget {
  const StudentIdCardPage({super.key});

  @override
  State<StudentIdCardPage> createState() => _StudentIdCardPageState();
}

class _StudentIdCardPageState extends State<StudentIdCardPage> {
  String searchQuery = "";
  bool isLoading = false;

  // Stream ek dafa bana lete hain — pehle ye seedha build() ke andar
  // banta tha, is liye search box mein har letter type karne par (jo
  // setState() call karta he) Firestore se dobara connect ho jata tha.
  late final Stream<QuerySnapshot> _studentsStream =
      schoolCollection('students').snapshots();

  Future<void> _generateStudentCardPdf(Map<String, dynamic> studentData,
      {String? studentId}) async {
    setState(() => isLoading = true);
    try {
      final pdf = pw.Document();

      pw.ImageProvider? netImage;
      String imgUrl = studentData['imageUrl'] ?? studentData['image'] ?? '';
      if (imgUrl.isNotEmpty) {
        netImage = await networkImage(imgUrl);
      }

      pw.MemoryImage? schoolLogo;
      try {
        schoolLogo = pw.MemoryImage(await getSchoolLogoBytes());
      } catch (_) {}

      // Horizontal ID Card Format (85.6mm width x 54mm height)
      const idCardFormat =
          PdfPageFormat(85.6 * PdfPageFormat.mm, 54 * PdfPageFormat.mm);

      String studentName =
          studentData['name'] ?? studentData['studentName'] ?? 'N/A';
      String studentClass = studentData['class'] ?? 'N/A';
      String fatherName =
          studentData['fName'] ?? studentData['fatherName'] ?? 'N/A';
      String contactNo =
          studentData['contactNo'] ?? studentData['phone'] ?? 'N/A';
      String formNo = studentData['formNo']?.toString() ?? '-';

      // Live Attendance scanner is prefix "AEPQR|schoolId|studentId" parse
      // karta he taake QR scan karte hi student turant pehchana ja sake.
      // Agar studentId maloom na ho (purana caller) to sirf purana
      // human-readable text hi rehta he — koi cheez toot'ti nahi.
      String qrData = studentId != null
          ? "AEPQR|${SchoolContext.schoolId}|$studentId\nName: $studentName\nClass: $studentClass\nFather: $fatherName\nPhone: $contactNo"
          : "Name: $studentName\nClass: $studentClass\nFather: $fatherName\nPhone: $contactNo";

      pdf.addPage(
        pw.Page(
          pageFormat: idCardFormat,
          margin: const pw.EdgeInsets.all(4),
          build: (context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.teal800, width: 1.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                children: [
                  // Top Header Banner
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 3, horizontal: 6),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.teal800,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.Row(
                      children: [
                        if (schoolLogo != null) ...[
                          pw.Image(schoolLogo, width: 14, height: 14),
                          pw.SizedBox(width: 4),
                        ],
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(currentSchoolDisplayName().toUpperCase(),
                                style: pw.TextStyle(
                                    fontSize: 7,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white)),
                            pw.Text("STUDENT IDENTITY CARD",
                                style: pw.TextStyle(
                                    fontSize: 4.5,
                                    color: PdfColor(1, 1, 1, 0.8))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 5),

                  // Middle Body (Photo | Details | QR Code)
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // Student Photo Box
                        pw.Container(
                          width: 42,
                          height: 52,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                                color: PdfColors.teal800, width: 1.2),
                            borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(4)),
                            image: netImage != null
                                ? pw.DecorationImage(
                                    image: netImage, fit: pw.BoxFit.cover)
                                : null,
                          ),
                          child: netImage == null
                              ? pw.Center(
                                  child: pw.Text("No Image",
                                      style: const pw.TextStyle(fontSize: 4.5)))
                              : null,
                        ),
                        pw.SizedBox(width: 6),

                        // Details Column
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text(
                                studentName,
                                style: pw.TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.teal900),
                              ),
                              pw.SizedBox(height: 2),
                              _buildRow("Father", fatherName),
                              _buildRow("Class", studentClass),
                              _buildRow("Form #", formNo),
                              _buildRow("Phone", contactNo),
                            ],
                          ),
                        ),

                        // QR Code
                        pw.Container(
                          padding: const pw.EdgeInsets.all(2),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                                color: PdfColors.grey400, width: 0.5),
                          ),
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: qrData,
                            width: 42,
                            height: 42,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Footer Section
                  pw.SizedBox(height: 2),
                  pw.Divider(color: PdfColors.grey400, thickness: 0.5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Issued: Jul 2026 | Exp: Jul 2027",
                          style: const pw.TextStyle(
                              fontSize: 4.5, color: PdfColors.grey700)),
                      pw.SizedBox(
                        width: 50,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Container(height: 0.5, color: PdfColors.grey700),
                            pw.SizedBox(height: 1),
                            pw.Text("Principal",
                                style: pw.TextStyle(
                                    fontSize: 4.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.grey700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );

      await showPdfPreviewPage(context,
          title: "ID Card Preview",
          shareFileName: "id_card.pdf",
          build: (format) async => pdf.save());
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  pw.Widget _buildRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 32,
            child: pw.Text(label,
                style: pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 5.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Student ID Card Generator"),
          backgroundColor: Colors.teal[800]),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: "Search Student by Name",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => searchQuery = value.trim().toLowerCase());
              },
            ),
            const SizedBox(height: 15),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _studentsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("No students found."));
                  }

                  var docs = snapshot.data!.docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    String name = (data['name'] ?? data['studentName'] ?? '')
                        .toString()
                        .toLowerCase();
                    return name.contains(searchQuery);
                  }).toList();

                  if (docs.isEmpty) {
                    return const Center(
                        child: Text("No matching student found."));
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var data = docs[index].data() as Map<String, dynamic>;
                      String name =
                          data['name'] ?? data['studentName'] ?? 'N/A';
                      String studentClass = data['class'] ?? 'N/A';
                      String imgUrl = data['imageUrl'] ?? data['image'] ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
                            child: imgUrl.isEmpty
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Class: $studentClass"),
                          trailing: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white),
                            icon: const Icon(Icons.badge, size: 16),
                            label: const Text("Generate ID"),
                            onPressed: isLoading
                                ? null
                                : () => _generateStudentCardPdf(data,
                                    studentId: docs[index].id),
                          ),
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
