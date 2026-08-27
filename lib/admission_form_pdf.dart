import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

/// Shared admission-form PDF builder.
///
/// This is the SAME layout that was originally only inside
/// admission_page.dart's `_generateAdmissionPDF`. It's been pulled out
/// here so that:
///   1. admission_page.dart can keep generating the form right after a
///      new admission is submitted (unchanged behaviour), and
///   2. student_detail_page.dart (and anywhere else) can regenerate the
///      exact same PDF later, from the student's saved Firestore data —
///      so a saved student's admission form can always be re-opened,
///      previewed and printed/shared again.
///
/// [studentData] should be the student's Firestore document map (the
/// same keys that get saved by admission_page's `_addStudent`: name,
/// sCNIC, fName, fCNIC, pAddress, dob, age, district, religion, gender,
/// contactNo, contactNo2, preSchool, class, section, addFee, date).

pw.TableRow _buildPdfRow(String label, String value) {
  return pw.TableRow(children: [
    pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(label,
            style:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
    pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(value, style: const pw.TextStyle(fontSize: 10))),
  ]);
}

String _s(Map<String, dynamic> data, String key, [String fallback = 'N/A']) {
  final v = data[key];
  if (v == null) return fallback;
  final str = v.toString().trim();
  return str.isEmpty ? fallback : str;
}

/// Builds the admission-form PDF bytes from a student's saved data map.
Future<Uint8List> buildAdmissionFormPdfBytes(
    Map<String, dynamic> studentData) async {
  Uint8List? logoBytes;
  try {
    logoBytes = await getSchoolLogoBytes();
  } catch (e) {
    logoBytes = null;
  }
  final pw.MemoryImage? logoImage =
      logoBytes != null ? pw.MemoryImage(logoBytes) : null;

  final name = _s(studentData, 'name', '');
  final dob = _s(studentData, 'dob', '');
  final age = _s(studentData, 'age', '');
  final dateOfAdmission = _s(studentData, 'date', '');
  final addFee = _s(studentData, 'addFee', '');
  final studentClass = _s(studentData, 'class', 'N/A');
  final section = _s(studentData, 'section', 'N/A');

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return pw.Container(
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 2)),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoImage != null)
                      pw.Container(
                        margin: const pw.EdgeInsets.only(right: 12),
                        width: 55,
                        height: 55,
                        child: pw.Image(logoImage),
                      ),
                    pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(currentSchoolDisplayName(),
                            style: pw.TextStyle(
                                fontSize: 22, fontWeight: pw.FontWeight.bold)),
                        pw.Text("(Admission form)",
                            style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black),
                    children: [
                      _buildPdfRow("Name of candidate", name),
                      _buildPdfRow(
                          "Student C.N.I.C.", _s(studentData, 'sCNIC', '')),
                      _buildPdfRow("Father's Name", _s(studentData, 'fName', '')),
                      _buildPdfRow(
                          "Father's C.N.I.C.", _s(studentData, 'fCNIC', '')),
                      _buildPdfRow(
                          "Permanent Address", _s(studentData, 'pAddress', '')),
                      _buildPdfRow("Date of Birth", "$dob (Age: $age)"),
                      _buildPdfRow("District", _s(studentData, 'district', '')),
                      _buildPdfRow("Religion", _s(studentData, 'religion', '')),
                      _buildPdfRow("Gender", _s(studentData, 'gender')),
                      _buildPdfRow(
                          "Contact no. 1", _s(studentData, 'contactNo', '')),
                      _buildPdfRow(
                          "Contact no. 2", _s(studentData, 'contactNo2')),
                    ]),
                pw.SizedBox(height: 10),
                pw.Text("Pervious Institute Information",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black),
                    children: [
                      _buildPdfRow(
                          "School Name", _s(studentData, 'preSchool', '')),
                      _buildPdfRow("Class", studentClass),
                      _buildPdfRow("Section", section),
                      _buildPdfRow("Reason of school leaving",
                          _s(studentData, 'leavingReason', '')),
                    ]),
                pw.SizedBox(height: 15),
                pw.Text(
                    "1. Attached three passport size pictures.\n2. B form two copy.\n3. Father CNIC two copy.\n4. Previous School leaving certificate.",
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 15),
                pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                    child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("For Office use",
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 12)),
                          pw.Text(
                              "Admission date: $dateOfAdmission    Admission fee: $addFee    Class name: $studentClass    Section: $section"),
                          pw.SizedBox(height: 20),
                          pw.Align(
                              alignment: pw.Alignment.bottomRight,
                              child: pw.Text("Principal signature ________")),
                        ])),
              ]),
        );
      }));

  return pdf.save();
}

/// Opens the in-app preview/print/share screen for a student's saved
/// admission form. Works from any saved student record (e.g. from the
/// student detail/update page) since it only needs the student's data
/// map — no need to be on the original admission screen.
Future<void> showSavedAdmissionFormPreview(
  BuildContext context,
  Map<String, dynamic> studentData,
) async {
  final name = _s(studentData, 'name', 'student');
  final pdfBytes = await buildAdmissionFormPdfBytes(studentData);
  if (!context.mounted) return;
  await showPdfPreviewPage(
    context,
    title: "Admission Form - $name",
    shareFileName: "admission_$name.pdf",
    build: (PdfPageFormat format) async => pdfBytes,
  );
}
