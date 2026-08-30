import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class LetterheadPage extends StatefulWidget {
  const LetterheadPage({super.key});

  @override
  State<LetterheadPage> createState() => _LetterheadPageState();
}

class _LetterheadPageState extends State<LetterheadPage> {
  final TextEditingController _titleController =
      TextEditingController(text: "OFFICIAL NOTICE / CERTIFICATE");
  final TextEditingController _contentController = TextEditingController();

  // Added a new controller for the address
  final TextEditingController _addressController =
      TextEditingController(text: "Badliwala, Khushab");

  // Pre-filled with this school's own number from Settings > WhatsApp
  // Number (can also be edited manually) — if not set yet, a
  // placeholder is shown.
  late final TextEditingController _principalNoController =
      TextEditingController(
          text: currentSchoolContactNumber().isNotEmpty
              ? currentSchoolContactNumber()
              : "+92 3XXXXXXXXX");
  bool isLoading = false;

  Future<void> _generateLetterheadPdf() async {
    setState(() => isLoading = true);
    try {
      final pdf = pw.Document();

      // Load the School Logo (from Settings > School Logo, otherwise default)
      pw.MemoryImage? schoolLogo;
      try {
        schoolLogo = pw.MemoryImage(await getSchoolLogoBytes());
      } catch (_) {}

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // --- HEADER SECTION ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (schoolLogo != null)
                      pw.Image(schoolLogo, width: 50, height: 50),
                    if (schoolLogo == null) pw.Container(width: 50, height: 50),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          currentSchoolDisplayName().toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal900,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          _addressController
                              .text, // The address the user typed is shown here
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(width: 50),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(color: PdfColors.teal900, thickness: 2),
                pw.SizedBox(height: 15),

                // --- LETTER TITLE ---
                pw.Center(
                  child: pw.Text(
                    _titleController.text.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.teal800,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),

                // --- BODY CONTENT ---
                pw.Expanded(
                  child: pw.Text(
                    _contentController.text,
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.black,
                      lineSpacing: 1.5,
                    ),
                  ),
                ),

                // --- FOOTER SECTION ---
                pw.Divider(color: PdfColors.grey400, thickness: 1),
                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Address: ${_addressController.text}",
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey700)),
                        pw.Text(
                            "Principal Contact: ${_principalNoController.text}",
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Container(
                            width: 80, height: 0.5, color: PdfColors.black),
                        pw.SizedBox(height: 3),
                        pw.Text("Principal Signature",
                            style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey800)),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      await showPdfPreviewPage(context, title: "Letterhead Preview", build: (format) async => pdf.save());
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Auto Letterhead Generator"),
        backgroundColor: Colors.teal[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              "Create Official School Letters, Notices, or Certificates",
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: "Letter Title / Heading",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            // Address input field that takes input from the user
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: "School Address",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _principalNoController,
              decoration: const InputDecoration(
                labelText: "Principal Contact Number",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _contentController,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: "Write Letter Content Here...",
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.print),
              label: Text(
                  isLoading
                      ? "Generating PDF..."
                      : "Generate & Print Letterhead",
                  style: const TextStyle(fontSize: 16)),
              onPressed: isLoading ? null : _generateLetterheadPdf,
            ),
          ],
        ),
      ),
    );
  }
}
