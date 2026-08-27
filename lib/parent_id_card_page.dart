import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_branding.dart';
import 'school_context.dart';
import 'pdf_preview_helper.dart';
import 'package:printing/printing.dart' show networkImage;

// Read-only ID card view/download for one student. Same card layout as
// the admin's student_id_card_page.dart, just scoped to a single child
// (no search, no generator list).
class ParentIdCardPage extends StatefulWidget {
  final Map<String, dynamic> studentData;
  final String? studentId;

  const ParentIdCardPage(
      {super.key, required this.studentData, this.studentId});

  @override
  State<ParentIdCardPage> createState() => _ParentIdCardPageState();
}

class _ParentIdCardPageState extends State<ParentIdCardPage> {
  bool isLoading = false;

  Future<void> _generateAndOpenCard() async {
    setState(() => isLoading = true);
    try {
      final studentData = widget.studentData;
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

      String qrData = widget.studentId != null
          ? "AEPQR|${SchoolContext.schoolId}|${widget.studentId}\nName: $studentName\nClass: $studentClass\nFather: $fatherName\nPhone: $contactNo"
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
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
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
          title: "ID Card Preview", build: (format) async => pdf.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
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
    final data = widget.studentData;
    String name = data['name'] ?? data['studentName'] ?? 'N/A';
    String studentClass = data['class'] ?? 'N/A';
    String imgUrl = data['imageUrl'] ?? data['image'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Student ID Card"),
        backgroundColor: Colors.indigo[700],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundImage:
                      imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
                  child: imgUrl.isEmpty ? const Icon(Icons.person) : null,
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Class: $studentClass"),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 24)),
              icon: const Icon(Icons.badge),
              label: const Text("View / Download ID Card"),
              onPressed: isLoading ? null : _generateAndOpenCard,
            ),
            if (isLoading) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
