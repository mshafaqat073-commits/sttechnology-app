import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

// ============================================================================
// CharacterCertificatePage
// ----------------------------------------------------------------------------
// As soon as you type a student's name (as-you-type), a list of matching
// students appears below — tap one and ALL of that student's details
// (name, father name, class, section, DOB, photo, etc.) are automatically
// filled in from the 'students' collection. Just fill in the 2-3
// certificate-specific fields (Ref No, Session, Remarks, Issue Date) and
// press "Generate Certificate" — the PDF will be generated and shared
// with the school's logo (from Settings > School Logo, otherwise
// default) and the School Name / Address set in Settings.
//
// NOTE: this file downloads the student's photo from the network
// (imageUrl) to place it in the PDF, which requires the `http` package.
// If it isn't already in pubspec.yaml, add this line under dependencies:
//
//   http: ^1.2.0
//
// If the http package isn't added, the certificate will still be
// generated — only the student's photo box will stay empty (blank),
// everything else will work.
// ============================================================================

class CharacterCertificatePage extends StatefulWidget {
  const CharacterCertificatePage({super.key});

  @override
  State<CharacterCertificatePage> createState() =>
      _CharacterCertificatePageState();
}

class _CharacterCertificatePageState extends State<CharacterCertificatePage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _loadingStudents = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allStudents = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchResults = [];

  Map<String, dynamic>? _selectedStudent;

  // These fields don't exist in the student record (they're used
  // while generating the certificate) — so the user can fill/edit
  // these themselves even after selecting a student.
  final TextEditingController _refNoController = TextEditingController();
  final TextEditingController _regdNoController = TextEditingController();
  final TextEditingController _sessionController = TextEditingController();
  final TextEditingController _remarksController =
      TextEditingController(text: "Satisfactory");
  final TextEditingController _issueDateController = TextEditingController();

  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _issueDateController.text = _formatDate(DateTime.now());
    _loadAllStudents();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _refNoController.dispose();
    _regdNoController.dispose();
    _sessionController.dispose();
    _remarksController.dispose();
    _issueDateController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}";

  // Load the whole student list once, so search is instant on every
  // keystroke without hitting Firestore again — and matches any word
  // anywhere in the name, not just as a prefix.
  Future<void> _loadAllStudents() async {
    setState(() => _loadingStudents = true);
    try {
      final snap = await schoolCollection('students').get();
      if (mounted) setState(() => _allStudents = snap.docs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Failed to load students: $e"),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      final q = query.trim().toLowerCase();
      if (q.isEmpty) {
        setState(() => _searchResults = []);
        return;
      }
      setState(() {
        _searchResults = _allStudents
            .where((doc) => (doc.data()['name']?.toString() ?? "")
                .toLowerCase()
                .contains(q))
            .take(20)
            .toList();
      });
    });
  }

  void _selectStudent(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    setState(() {
      _selectedStudent = data;
      _searchResults = [];
      _searchController.text = data['name']?.toString() ?? "";
      _refNoController.text = data['formNo']?.toString() ?? "";
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedStudent = null;
      _searchController.clear();
      _refNoController.clear();
      _regdNoController.clear();
      _sessionController.clear();
    });
  }

  Future<void> _pickIssueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _issueDateController.text = _formatDate(picked));
    }
  }

  // ---------------------------------------------------------------------
  // PDF Generation
  // ---------------------------------------------------------------------

  pw.Widget _signatureBlock(String label) {
    return pw.Column(
      children: [
        pw.Container(width: 110, height: 0.8, color: PdfColors.black),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  pw.TextSpan _filled(String value, {String suffix = ""}) => pw.TextSpan(
      text: "  ${value.isEmpty ? '__________' : value}$suffix  ",
      style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          decoration: pw.TextDecoration.underline,
          decorationColor: PdfColors.grey700));

  Future<void> _generateCertificate() async {
    if (_selectedStudent == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select a student first"),
          backgroundColor: Colors.red));
      return;
    }
    setState(() => _generating = true);
    try {
      // 1) School's logo (from Settings > School Logo, otherwise default)
      Uint8List? logoBytes;
      try {
        logoBytes = await getSchoolLogoBytes();
      } catch (_) {
        logoBytes = null;
      }
      final pw.MemoryImage? logoImage =
          logoBytes != null ? pw.MemoryImage(logoBytes) : null;

      // 2) School Name / Address (from the Settings page's settings/global doc)
      String schoolName = currentSchoolDisplayName();
      String schoolAddress = "";
      try {
        final settingsDoc =
            await schoolCollection('settings').doc('global').get();
        if (settingsDoc.exists) {
          final sd = settingsDoc.data() ?? {};
          schoolAddress = sd['address']?.toString() ?? "";
        }
      } catch (_) {}

      // 3) Student's photo (download it if imageUrl is available)
      pw.MemoryImage? studentPhoto;
      final String imageUrl = _selectedStudent?['imageUrl']?.toString() ?? "";
      if (imageUrl.isNotEmpty) {
        try {
          final resp = await http
              .get(Uri.parse(imageUrl))
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            studentPhoto = pw.MemoryImage(resp.bodyBytes);
          }
        } catch (_) {
          studentPhoto = null;
        }
      }

      final data = _selectedStudent!;
      final String name = data['name']?.toString() ?? "";
      final String fName = data['fName']?.toString() ?? "";
      final String className = data['class']?.toString() ?? "";
      final String section = data['section']?.toString() ?? "";
      final String dob = data['dob']?.toString() ?? "";
      final bool isFemale = (data['gender']?.toString() ?? "") == "Female";
      final String prefix = isFemale ? "Ms." : "Mr.";
      final String relation = isFemale ? "Daughter" : "Son";

      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.indigo900, width: 2.2)),
            child: pw.Container(
              padding: pw.EdgeInsets.all(22),
              decoration: pw.BoxDecoration(
                  border:
                      pw.Border.all(color: PdfColors.indigo900, width: 0.8)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header: logo - school name/address/title - student photo
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 70,
                        child: logoImage != null
                            ? pw.Image(logoImage)
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          children: [
                            pw.Text(schoolName.toUpperCase(),
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                    fontSize: 20,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.indigo900)),
                            if (schoolAddress.isNotEmpty) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(schoolAddress,
                                  textAlign: pw.TextAlign.center,
                                  style: const pw.TextStyle(fontSize: 11)),
                            ],
                            pw.SizedBox(height: 10),
                            pw.Text("CHARACTER CERTIFICATE",
                                style: pw.TextStyle(
                                    fontSize: 18,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.red800)),
                          ],
                        ),
                      ),
                      pw.Container(
                        width: 70,
                        height: 82,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey600)),
                        child: studentPhoto != null
                            ? pw.Image(studentPhoto, fit: pw.BoxFit.cover)
                            : pw.Text("Photo",
                                style: const pw.TextStyle(
                                    fontSize: 9, color: PdfColors.grey600)),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 14),
                  pw.Divider(color: PdfColors.indigo900, thickness: 1),
                  pw.SizedBox(height: 10),

                  // Ref / Roll / Regd numbers
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.RichText(
                          text: pw.TextSpan(children: [
                        pw.TextSpan(
                            text: "Ref. No:",
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        _filled(_refNoController.text),
                      ])),
                      pw.RichText(
                          text: pw.TextSpan(children: [
                        pw.TextSpan(
                            text: "Class Roll No:",
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        _filled(_regdNoController.text),
                      ])),
                    ],
                  ),
                  pw.SizedBox(height: 20),

                  // Certificate body paragraph
                  pw.RichText(
                    text: pw.TextSpan(
                      style: pw.TextStyle(fontSize: 12.5, lineSpacing: 4),
                      children: [
                        const pw.TextSpan(text: "This is to certify that "),
                        pw.TextSpan(
                            text: "$prefix ",
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        _filled(name),
                        pw.TextSpan(text: ", $relation of "),
                        _filled(fName),
                        const pw.TextSpan(
                            text: ", is/was a bonafide student of this "
                                "Institute, studying in Class "),
                        _filled(
                            "$className${section.isNotEmpty ? ' - $section' : ''}"),
                        if (_sessionController.text.trim().isNotEmpty) ...[
                          const pw.TextSpan(
                              text: " during the academic session "),
                          _filled(_sessionController.text),
                        ],
                        const pw.TextSpan(
                            text: ". His/Her date of birth according to school "
                                "record is "),
                        _filled(dob),
                        const pw.TextSpan(
                            text:
                                ". During his/her stay in this Institute, his/her "
                                "moral character and conduct remained "),
                        _filled(_remarksController.text.trim().isEmpty
                            ? "Satisfactory"
                            : _remarksController.text),
                        const pw.TextSpan(
                            text: ". I know nothing against his/her moral "
                                "character. I wish him/her success in every "
                                "walk of life."),
                      ],
                    ),
                  ),

                  pw.Spacer(),

                  // Signatures
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _signatureBlock("Class Teacher"),
                      _signatureBlock("Checked By"),
                      _signatureBlock("Principal"),
                    ],
                  ),
                  pw.SizedBox(height: 14),
                  pw.Text("Issued Date: ${_issueDateController.text}",
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ));

      final bytes = await pdf.save();
      if (mounted) {
        await _showPdfActionSheet(bytes, "character_certificate_$name.pdf",
            "Character Certificate for $name");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error generating certificate: $e"),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // Both Preview and Send options in one place
  Future<void> _showPdfActionSheet(
      Uint8List pdfBytes, String fileName, String shareText) async {
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
                await showPdfPreviewPage(context, title: "Character Certificate Preview", build: (format) async => pdfBytes);
              },
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text("Send"),
              onTap: () async {
                Navigator.pop(context);
                await Printing.sharePdf(
                    bytes: pdfBytes, filename: fileName, subject: shareText);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Character Certificate Generator"),
        backgroundColor: Colors.indigo[800],
      ),
      body: _loadingStudents
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search field
                  TextField(
                    controller: _searchController,
                    enabled: _selectedStudent == null,
                    decoration: InputDecoration(
                      labelText: "Enter the student's name",
                      hintText: "e.g. Ali Raza",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _selectedStudent != null
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: _clearSelection,
                              tooltip: "Change student",
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _onSearchChanged,
                  ),

                  // Live search results
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = _searchResults[index];
                          final d = doc.data();
                          final img = d['imageUrl']?.toString() ?? "";
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.indigo.shade50,
                              backgroundImage:
                                  img.isNotEmpty ? NetworkImage(img) : null,
                              child: img.isEmpty
                                  ? const Icon(Icons.person,
                                      color: Colors.indigo)
                                  : null,
                            ),
                            title: Text(d['name']?.toString() ?? ""),
                            subtitle: Text(
                                "Class: ${d['class'] ?? '-'}  |  Section: ${d['section'] ?? '-'}"),
                            onTap: () => _selectStudent(doc),
                          );
                        },
                      ),
                    ),

                  // Selected student summary card
                  if (_selectedStudent != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.indigo.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.indigo.shade100,
                              backgroundImage: (_selectedStudent!['imageUrl']
                                              ?.toString() ??
                                          "")
                                      .isNotEmpty
                                  ? NetworkImage(
                                      _selectedStudent!['imageUrl'].toString())
                                  : null,
                              child:
                                  (_selectedStudent!['imageUrl']?.toString() ??
                                              "")
                                          .isEmpty
                                      ? const Icon(Icons.person,
                                          color: Colors.indigo, size: 28)
                                      : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      _selectedStudent!['name']?.toString() ??
                                          "",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  Text(
                                      "Father: ${_selectedStudent!['fName'] ?? '-'}"),
                                  Text(
                                      "Class: ${_selectedStudent!['class'] ?? '-'}  |  Section: ${_selectedStudent!['section'] ?? '-'}"),
                                  Text(
                                      "DOB: ${_selectedStudent!['dob'] ?? '-'}"),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("Certificate Details",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _refNoController,
                        decoration:
                            const InputDecoration(labelText: "Ref. No")),
                    TextField(
                        controller: _regdNoController,
                        decoration: const InputDecoration(
                            labelText: "Class Roll No / Regd No")),
                    TextField(
                        controller: _sessionController,
                        decoration: const InputDecoration(
                            labelText: "Academic Session (e.g. 2025-2026)")),
                    TextField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                            labelText: "Moral Character Remarks",
                            hintText: "Satisfactory")),
                    TextField(
                      controller: _issueDateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: "Issued Date",
                          suffixIcon: Icon(Icons.calendar_today)),
                      onTap: _pickIssueDate,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _generating ? null : _generateCertificate,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo[800]),
                        icon: _generating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.picture_as_pdf,
                                color: Colors.white),
                        label: Text(
                            _generating
                                ? "Generating..."
                                : "Generate Certificate",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
