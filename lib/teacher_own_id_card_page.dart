import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'package:printing/printing.dart' show networkImage;

// Admin's TeacherIdCardPage lists ALL staff and lets you search/pick any
// teacher. Here there's no search/list — the logged-in teacher's own
// staffData (already available from TeacherDashboard) is passed in directly,
// so only their own card can ever be generated.
class TeacherOwnIdCardPage extends StatefulWidget {
  final Map<String, dynamic> staffData;

  const TeacherOwnIdCardPage({super.key, required this.staffData});

  @override
  State<TeacherOwnIdCardPage> createState() => _TeacherOwnIdCardPageState();
}

class _TeacherOwnIdCardPageState extends State<TeacherOwnIdCardPage> {
  bool isLoading = false;

  Future<void> _generateTeacherCardPdf() async {
    setState(() => isLoading = true);
    try {
      final staffData = widget.staffData;
      final pdf = pw.Document();

      pw.ImageProvider? netImage;
      String imgUrl = staffData['imageUrl'] ?? staffData['image'] ?? '';
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

      String teacherName = staffData['name'] ?? staffData['staffName'] ?? 'N/A';
      String designation =
          staffData['designation'] ?? staffData['role'] ?? 'Teacher';
      String contact = staffData['contact'] ?? staffData['phone'] ?? 'N/A';
      String category = staffData['category'] ?? 'Teaching';

      String qrData =
          "Name: $teacherName\nDesignation: $designation\nPhone: $contact";

      pdf.addPage(
        pw.Page(
          pageFormat: idCardFormat,
          margin: const pw.EdgeInsets.all(4),
          build: (context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(
                border:
                    pw.Border.all(color: PdfColors.deepPurple800, width: 1.5),
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
                      color: PdfColors.deepPurple800,
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
                            pw.Text("STAFF IDENTITY CARD",
                                style: pw.TextStyle(
                                    fontSize: 4.5,
                                    color: PdfColor(1, 1, 1, 0.8))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 5),

                  // Middle Body
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // Staff Photo Box
                        pw.Container(
                          width: 42,
                          height: 52,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                                color: PdfColors.deepPurple800, width: 1.2),
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
                                teacherName,
                                style: pw.TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.deepPurple900),
                              ),
                              pw.SizedBox(height: 2),
                              _buildRow("Desig", designation),
                              _buildRow("Category", category),
                              _buildRow("Phone", contact),
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
            width: 35,
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
    final staffData = widget.staffData;
    String name = staffData['name'] ?? staffData['staffName'] ?? 'N/A';
    String designation =
        staffData['designation'] ?? staffData['role'] ?? 'Teacher';
    String contact = staffData['contact'] ?? staffData['phone'] ?? 'N/A';
    String imgUrl = staffData['imageUrl'] ?? staffData['image'] ?? '';

    return Scaffold(
      appBar: AppBar(
          title: const Text("My ID Card"),
          backgroundColor: Colors.deepPurple[800]),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage:
                          imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
                      child: imgUrl.isEmpty
                          ? const Icon(Icons.person, size: 32)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text("Designation: $designation"),
                          Text("Contact: $contact"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.badge),
                label:
                    Text(isLoading ? "Generating..." : "Generate My ID Card"),
                onPressed: isLoading ? null : _generateTeacherCardPdf,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
