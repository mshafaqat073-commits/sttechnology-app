import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'school_branding.dart';
import 'school_context.dart';
import 'pdf_preview_helper.dart';

/// For printing the receipt after a fee payment. Two printer options:
///
///  1) Thermal Printer (58mm/80mm roll) — a small, long slip, like what
///     POS machines print.
///  2) Regular/A4 Printer — normal size, and you can also choose how
///     many copies (School Copy / Parent Copy / Bank Copy, etc.) to
///     print on one page (1 to 4).
///
/// Printing.layoutPdf() opens the OS's print dialog, from where any
/// connected printer (thermal or normal) can be selected.
class FeeReceiptPage extends StatefulWidget {
  final String receiptNo;
  final String studentName;
  final String fatherName;
  final String className;
  final String section;
  final double amountPaid;
  final double previousDues;
  final double duesRemaining;
  final DateTime paymentDate;
  final Map<String, double> feeBreakdown; // field label -> paid amount

  const FeeReceiptPage({
    super.key,
    required this.receiptNo,
    required this.studentName,
    required this.fatherName,
    required this.className,
    required this.section,
    required this.amountPaid,
    required this.previousDues,
    required this.duesRemaining,
    required this.paymentDate,
    this.feeBreakdown = const {},
  });

  @override
  State<FeeReceiptPage> createState() => _FeeReceiptPageState();
}

class _FeeReceiptPageState extends State<FeeReceiptPage> {
  int _copiesPerPage = 2;
  String _thermalSize = '80mm';

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
                    pw.Text("Fee Receipt",
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
          _row("Student", widget.studentName, compact),
          _row("Father", widget.fatherName, compact),
          _row("Class", "${widget.className} ${widget.section}", compact),
          pw.Divider(thickness: 0.5),
          ...widget.feeBreakdown.entries
              .where((e) => e.value > 0)
              .map((e) => _row(e.key, e.value.toStringAsFixed(0), compact)),
          if (widget.previousDues > 0)
            _row("Previous Dues", widget.previousDues.toStringAsFixed(0), compact),
          pw.Divider(thickness: 0.7),
          _row("Amount Paid", "Rs. ${widget.amountPaid.toStringAsFixed(0)}",
              compact, bold: true),
          _row("Remaining Dues", "Rs. ${widget.duesRemaining.toStringAsFixed(0)}",
              compact),
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
      title: "Receipt Preview (Thermal)",
      shareFileName: "receipt_${widget.receiptNo}.pdf",
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
          // Ek page par _copiesPerPage jitni raseedain — jaise School
          // Copy / Parent Copy / Bank Copy, sab identical.
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
      title: "Receipt Preview",
      shareFileName: "receipt_${widget.receiptNo}.pdf",
      build: (f) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Print Fee Receipt"),
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
                    Text(widget.studentName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("${widget.className} ${widget.section}"),
                    const SizedBox(height: 8),
                    Text("Rs. ${widget.amountPaid.toStringAsFixed(0)} Paid",
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
            const Text("Bara / A4 Printer",
                style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                const Text("Receipts per page: "),
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
