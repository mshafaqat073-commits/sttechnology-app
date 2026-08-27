import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'set_fee_page.dart';

/// Finds every student whose monthlyFee is 0 (or was never set at all)
/// — useful for catching admissions where the fee amount was
/// accidentally left blank.
class ZeroFeeStudentsPage extends StatefulWidget {
  const ZeroFeeStudentsPage({super.key});

  @override
  State<ZeroFeeStudentsPage> createState() => _ZeroFeeStudentsPageState();
}

class _ZeroFeeStudentsPageState extends State<ZeroFeeStudentsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final studentsSnap = await schoolCollection('students')
        .where('status', isEqualTo: 'active')
        .get();
    // Monthly fee ka asal rate sirf students collection se lena hai —
    // fee_structures.monthlyFee ek "remaining balance" hai jo is mahine
    // ki payment hote hi 0 ho jata hai, is liye usay yahan (ya kisi bhi
    // "kitna fee assign hai" wale check mein) source ke tor par nahi
    // lena chahiye, warna har fully-paid student ghalati se "0 fee"
    // dikhne lag jata hai.

    final List<Map<String, dynamic>> results = [];
    for (var doc in studentsSnap.docs) {
      final data = doc.data();
      final monthlyFee = (data['monthlyFee'] as num? ?? 0).toDouble();
      if (monthlyFee <= 0) {
        results.add({
          'docId': doc.id,
          'name': data['name'] ?? 'N/A',
          'fName': data['fName'] ?? 'N/A',
          'class': data['class'] ?? 'N/A',
        });
      }
    }

    if (mounted) {
      setState(() {
        _results = results;
        _loading = false;
      });
    }
  }

  // PDF Generation — lists every active student currently on 0 monthly
  // fee, so the office has a printable record to follow up on.
  Future<void> _generateAndPrintPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(currentSchoolDisplayName(),
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Students with 0 Monthly Fee",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text("Total: ${_results.length} active student(s)",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Sr.', 'Student Name', 'Father Name', 'Class'],
              data: List.generate(_results.length, (index) {
                final item = _results[index];
                return [
                  "${index + 1}",
                  item['name'],
                  item['fName'],
                  item['class'],
                ];
              }),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
            ),
          ];
        },
      ),
    );

    if (!mounted) return;
    await showPdfPreviewPage(
      context,
      title: "0 Monthly Fee Students Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Students with 0 Monthly Fee"),
        backgroundColor: Colors.red[700],
        actions: [
          if (!_loading && _results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: "Generate / Print PDF",
              onPressed: _generateAndPrintPdf,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? const Center(
                  child: Text(
                    "All active students have a monthly fee set!",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.red[50],
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        "${_results.length} active student(s) have monthly fee = 0",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final r = _results[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            child: ListTile(
                              leading: const Icon(Icons.money_off,
                                  color: Colors.red),
                              title: Text(r['name'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  "Father: ${r['fName']}  |  Class: ${r['class']}"),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal[800]),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SetFeePage(
                                        docId: r['docId'],
                                        studentName: r['name'],
                                      ),
                                    ),
                                  );
                                  _load();
                                },
                                child: const Text("Set Fee",
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
