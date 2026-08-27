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
// ExperienceCertificatePage
// ----------------------------------------------------------------------------
// Same pattern as CharacterCertificatePage, but for staff instead of
// students: search a staff member by name, fill in a few
// certificate-specific fields (Joining Date, Leaving Date, Ref No,
// Remarks), and generate a full A4 Experience Certificate PDF with the
// school's logo/name/address from Settings.
// ============================================================================

class ExperienceCertificatePage extends StatefulWidget {
  const ExperienceCertificatePage({super.key});

  @override
  State<ExperienceCertificatePage> createState() =>
      _ExperienceCertificatePageState();
}

class _ExperienceCertificatePageState
    extends State<ExperienceCertificatePage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _loadingStaff = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allStaff = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchResults = [];

  Map<String, dynamic>? _selectedStaff;

  final TextEditingController _refNoController = TextEditingController();
  final TextEditingController _joiningDateController = TextEditingController();
  final TextEditingController _leavingDateController = TextEditingController();
  final TextEditingController _remarksController =
      TextEditingController(text: "Satisfactory");
  final TextEditingController _issueDateController = TextEditingController();

  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _issueDateController.text = _formatDate(DateTime.now());
    _leavingDateController.text = _formatDate(DateTime.now());
    _loadAllStaff();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _refNoController.dispose();
    _joiningDateController.dispose();
    _leavingDateController.dispose();
    _remarksController.dispose();
    _issueDateController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}";

  Future<void> _loadAllStaff() async {
    setState(() => _loadingStaff = true);
    try {
      final snap = await schoolCollection('staff').get();
      if (mounted) setState(() => _allStaff = snap.docs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Failed to load staff: $e"),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loadingStaff = false);
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
        _searchResults = _allStaff
            .where((doc) => (doc.data()['name']?.toString() ?? "")
                .toLowerCase()
                .contains(q))
            .take(20)
            .toList();
      });
    });
  }

  void _selectStaff(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    setState(() {
      _selectedStaff = data;
      _searchResults = [];
      _searchController.text = data['name']?.toString() ?? "";
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedStaff = null;
      _searchController.clear();
      _refNoController.clear();
      _joiningDateController.clear();
    });
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => controller.text = _formatDate(picked));
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
    if (_selectedStaff == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select a staff member first"),
          backgroundColor: Colors.red));
      return;
    }
    setState(() => _generating = true);
    try {
      // 1) School logo (Settings > School Logo, or default)
      Uint8List? logoBytes;
      try {
        logoBytes = await getSchoolLogoBytes();
      } catch (_) {
        logoBytes = null;
      }
      final pw.MemoryImage? logoImage =
          logoBytes != null ? pw.MemoryImage(logoBytes) : null;

      // 2) School Name / Address (settings/global doc)
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

      // 3) Staff photo (if imageUrl is available)
      pw.MemoryImage? staffPhoto;
      final String imageUrl =
          _selectedStaff?['imageUrl']?.toString() ??
              _selectedStaff?['image']?.toString() ??
              "";
      if (imageUrl.isNotEmpty) {
        try {
          final resp = await http
              .get(Uri.parse(imageUrl))
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            staffPhoto = pw.MemoryImage(resp.bodyBytes);
          }
        } catch (_) {
          staffPhoto = null;
        }
      }

      final data = _selectedStaff!;
      final String name = data['name']?.toString() ?? "";
      final String designation = (data['designation'] ?? data['role'])
              ?.toString() ??
          "";
      final bool isFemale = (data['gender']?.toString() ?? "") == "Female";
      final String prefix = isFemale ? "Ms." : "Mr.";
      final String pronoun = isFemale ? "her" : "his";

      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.indigo900, width: 2.2)),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(22),
              decoration: pw.BoxDecoration(
                  border:
                      pw.Border.all(color: PdfColors.indigo900, width: 0.8)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header: logo - school name/address/title - staff photo
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
                            pw.Text("EXPERIENCE CERTIFICATE",
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
                        child: staffPhoto != null
                            ? pw.Image(staffPhoto, fit: pw.BoxFit.cover)
                            : pw.Text("Photo",
                                style: const pw.TextStyle(
                                    fontSize: 9, color: PdfColors.grey600)),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 14),
                  pw.Divider(color: PdfColors.indigo900, thickness: 1),
                  pw.SizedBox(height: 10),

                  // Ref No
                  pw.RichText(
                      text: pw.TextSpan(children: [
                    pw.TextSpan(
                        text: "Ref. No:",
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    _filled(_refNoController.text),
                  ])),
                  pw.SizedBox(height: 20),

                  // Certificate body paragraph
                  pw.RichText(
                    text: pw.TextSpan(
                      style: const pw.TextStyle(fontSize: 12.5, lineSpacing: 4),
                      children: [
                        const pw.TextSpan(text: "This is to certify that "),
                        pw.TextSpan(
                            text: "$prefix ",
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        _filled(name),
                        const pw.TextSpan(
                            text: " served this Institute as "),
                        _filled(designation),
                        const pw.TextSpan(text: " from "),
                        _filled(_joiningDateController.text),
                        const pw.TextSpan(text: " to "),
                        _filled(_leavingDateController.text),
                        pw.TextSpan(
                            text:
                                ". During $pronoun stay in this Institute, "
                                "$pronoun conduct and professional performance "
                                "remained "),
                        _filled(_remarksController.text.trim().isEmpty
                            ? "Satisfactory"
                            : _remarksController.text),
                        pw.TextSpan(
                            text:
                                ". We found $pronoun hardworking, sincere and "
                                "dedicated towards $pronoun duties. We wish "
                                "$pronoun success in all future endeavors."),
                      ],
                    ),
                  ),

                  pw.Spacer(),

                  // Signatures
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _signatureBlock("Admin / HR"),
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
        await _showPdfActionSheet(bytes, "experience_certificate_$name.pdf",
            "Experience Certificate for $name");
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

  // Preview and Send both from one bottom sheet
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
                await showPdfPreviewPage(context,
                    title: "Experience Certificate Preview",
                    build: (format) async => pdfBytes);
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
        title: const Text("Experience Certificate Generator"),
        backgroundColor: Colors.indigo[800],
      ),
      body: _loadingStaff
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search field
                  TextField(
                    controller: _searchController,
                    enabled: _selectedStaff == null,
                    decoration: InputDecoration(
                      labelText: "Enter the staff member's name",
                      hintText: "e.g. Muhammad Ali",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _selectedStaff != null
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: _clearSelection,
                              tooltip: "Change staff member",
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
                          final img = (d['imageUrl'] ?? d['image'] ?? '')
                              .toString();
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
                                (d['designation'] ?? d['role'] ?? '-')
                                    .toString()),
                            onTap: () => _selectStaff(doc),
                          );
                        },
                      ),
                    ),

                  // Selected staff summary card
                  if (_selectedStaff != null) ...[
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
                              backgroundImage: (_selectedStaff!['imageUrl']
                                              ?.toString() ??
                                          _selectedStaff!['image']
                                              ?.toString() ??
                                          "")
                                      .isNotEmpty
                                  ? NetworkImage((_selectedStaff!['imageUrl'] ??
                                          _selectedStaff!['image'])
                                      .toString())
                                  : null,
                              child: (_selectedStaff!['imageUrl']
                                                  ?.toString() ??
                                              _selectedStaff!['image']
                                                  ?.toString() ??
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
                                      _selectedStaff!['name']?.toString() ??
                                          "",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  Text(
                                      "Designation: ${_selectedStaff!['designation'] ?? _selectedStaff!['role'] ?? '-'}"),
                                  Text(
                                      "Contact: ${_selectedStaff!['contact'] ?? '-'}"),
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
                      controller: _joiningDateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: "Joining Date",
                          suffixIcon: Icon(Icons.calendar_today)),
                      onTap: () => _pickDate(_joiningDateController),
                    ),
                    TextField(
                      controller: _leavingDateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: "Leaving Date",
                          suffixIcon: Icon(Icons.calendar_today)),
                      onTap: () => _pickDate(_leavingDateController),
                    ),
                    TextField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                            labelText: "Conduct / Performance Remarks",
                            hintText: "Satisfactory")),
                    TextField(
                      controller: _issueDateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: "Issued Date",
                          suffixIcon: Icon(Icons.calendar_today)),
                      onTap: () => _pickDate(_issueDateController),
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
