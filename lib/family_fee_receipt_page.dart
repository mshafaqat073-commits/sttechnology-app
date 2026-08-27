import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'school_branding.dart';
import 'school_context.dart';
import 'pdf_preview_helper.dart';

/// Prints one combined slip after all siblings in a family have paid
/// together (Pay Together) — similar to what fee_receipt_page.dart
/// does, except this one lists multiple children's details and ends
/// with one combined Grand Total.
class FamilyFeeReceiptPage extends StatefulWidget {
  final String receiptNo;
  final DateTime paymentDate;
  final List<Map<String, dynamic>> children; // name, fName, class, amountPaid, duesRemaining, breakdown
  final double totalPaid;

  const FamilyFeeReceiptPage({
    super.key,
    required this.receiptNo,
    required this.paymentDate,
    required this.children,
    required this.totalPaid,
  });

  @override
  State<FamilyFeeReceiptPage> createState() => _FamilyFeeReceiptPageState();
}

class _FamilyFeeReceiptPageState extends State<FamilyFeeReceiptPage> {
  int _copiesPerPage = 1;
  String _thermalSize = '80mm';

  pw.Widget _row(String label, String value, bool compact, {bool bold = false}) {
    final style = pw.TextStyle(
        fontSize: compact ? 8 : 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  pw.Widget _receiptBlock(pw.MemoryImage? logo, {bool compact = false}) {
    final fmt = DateFormat('dd-MM-yyyy');
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (logo != null) pw.Image(logo, width: 34, height: 34),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(SchoolContext.schoolName ?? 'School',
                        style: pw.TextStyle(
                            fontSize: compact ? 11 : 14,
                            fontWeight: pw.FontWeight.bold)),
                    pw.Text("Family Fee Receipt",
                        style: pw.TextStyle(fontSize: compact ? 8 : 10)),
                  ],
                ),
              ),
              pw.SizedBox(width: 34),
            ],
          ),
          pw.Divider(thickness: 0.7),
          _row("Receipt No", widget.receiptNo, compact),
          _row("Date", fmt.format(widget.paymentDate), compact),
          pw.Divider(thickness: 0.5),
          for (var child in widget.children) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              "${child['name'] ?? ''}  (${child['class'] ?? ''})",
              style: pw.TextStyle(
                  fontSize: compact ? 8.5 : 10.5,
                  fontWeight: pw.FontWeight.bold),
            ),
            ...((child['breakdown'] as Map<String, dynamic>? ?? {})
                .entries
                .where((e) => (e.value as double? ?? 0) > 0)
                .map((e) => _row(
                    "  ${e.key}",
                    (e.value as double).toStringAsFixed(0),
                    compact))),
            _row("  Paid", "Rs. ${(child['amountPaid'] as double).toStringAsFixed(0)}",
                compact, bold: true),
            if ((child['duesRemaining'] as double? ?? 0) > 0)
              _row("  Remaining", (child['duesRemaining'] as double).toStringAsFixed(0),
                  compact),
            pw.SizedBox(height: 2),
          ],
          pw.Divider(thickness: 0.7),
          _row("Family Grand Total Paid", "Rs. ${widget.totalPaid.toStringAsFixed(0)}",
              compact, bold: true),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text("Thank You!",
                style: pw.TextStyle(
                    fontSize: compact ? 8 : 9,
                    fontStyle: pw.FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Future<void> _printThermal() async {
    final pdf = pw.Document();
    pw.MemoryImage? logo;
    try {
      logo = pw.MemoryImage(await getSchoolLogoBytes());
    } catch (_) {}

    final widthMm = _thermalSize == '58mm' ? 58.0 : 80.0;
    final format = PdfPageFormat(
        widthMm * PdfPageFormat.mm, double.infinity,
        marginAll: 4 * PdfPageFormat.mm);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => _receiptBlock(logo, compact: true),
      ),
    );

    await showPdfPreviewPage(
      context,
      title: "Family Receipt Preview (Thermal)",
      shareFileName: "family_receipt_${widget.receiptNo}.pdf",
      build: (f) async => pdf.save(),
    );
  }

  Future<void> _printFullPage() async {
    final pdf = pw.Document();
    pw.MemoryImage? logo;
    try {
      logo = pw.MemoryImage(await getSchoolLogoBytes());
    } catch (_) {}

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            children: List.generate(_copiesPerPage, (i) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: _receiptBlock(logo),
              );
            }),
          );
        },
      ),
    );

    await showPdfPreviewPage(
      context,
      title: "Family Receipt Preview",
      shareFileName: "family_receipt_${widget.receiptNo}.pdf",
      build: (f) async => pdf.save(),
    );
  }

  // On Desktop (Windows/macOS/Linux), when no printer is set up, the old
  // silent-fail approach is no longer used — the preview now always
  // opens in a new screen (the PdfPreview widget), which works on all
  // three platforms.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Print Family Fee Receipt"),
        backgroundColor: Colors.teal[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      widget.children
                          .map((c) => c['name'] ?? '')
                          .join(', '),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text("Rs. ${widget.totalPaid.toStringAsFixed(0)} Paid (Family Total)",
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.green,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Thermal Printer (58mm / 80mm roll)",
                style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text("58mm"),
                    value: '58mm',
                    groupValue: _thermalSize,
                    onChanged: (v) => setState(() => _thermalSize = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text("80mm"),
                    value: '80mm',
                    groupValue: _thermalSize,
                    onChanged: (v) => setState(() => _thermalSize = v!),
                  ),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _printThermal,
              icon: const Icon(Icons.receipt_long),
              label: const Text("Print on Thermal Printer"),
            ),
            const SizedBox(height: 24),
            const Text("Standard / A4 Printer",
                style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                const Text("Copies: "),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: _copiesPerPage,
                  items: [1, 2, 3, 4]
                      .map((n) => DropdownMenuItem(value: n, child: Text("$n")))
                      .toList(),
                  onChanged: (v) => setState(() => _copiesPerPage = v!),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _printFullPage,
              icon: const Icon(Icons.print),
              label: const Text("Print on A4 / Full Printer"),
            ),
          ],
        ),
      ),
    );
  }
}
