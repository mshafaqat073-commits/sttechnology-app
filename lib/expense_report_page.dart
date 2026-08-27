import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class ExpenseReportPage extends StatelessWidget {
  const ExpenseReportPage({super.key});

  // Helper function to safely convert Firestore Timestamp or String to String
  String _parseDate(dynamic dateField) {
    if (dateField == null) return 'N/A';
    if (dateField is Timestamp) {
      return DateFormat('yyyy-MM-dd').format(dateField.toDate());
    }
    return dateField.toString();
  }

  // Helper to convert dynamic number/string safely to double
  double _parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Expense Report"),
        backgroundColor: Colors.redAccent[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Download/Print PDF",
            onPressed: () => _generateAndPrintPdf(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('expenses').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error: ${snapshot.error}",
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No expense record found.",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
              ),
            );
          }

          var docs = snapshot.data!.docs;
          double grandTotal = 0.0;
          double grandPaid = 0.0;
          double grandRemaining = 0.0;

          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;

            grandTotal += _parseNum(data['total'] ?? data['paid']);
            grandPaid += _parseNum(data['paid']);
            grandRemaining += _parseNum(data['remaining']);
          }

          return Column(
            children: [
              // Grand Summary Cards Container
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryItem("Total", grandTotal, Colors.black87),
                    _buildSummaryItem("Paid", grandPaid, Colors.green.shade700),
                    _buildSummaryItem(
                        "Remaining", grandRemaining, Colors.red.shade700),
                  ],
                ),
              ),

              // Expense Items List
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;

                    String name = data['name'] ?? 'N/A';
                    String description = data['description'] ?? '';
                    String date = _parseDate(data['date'] ?? data['timestamp']);

                    double total = _parseNum(data['total'] ?? data['paid']);
                    double paid = _parseNum(data['paid']);
                    double remaining = _parseNum(data['remaining']);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                Text(
                                  "Date: $date",
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 13),
                              ),
                            ],
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Total: Rs. ${total.toStringAsFixed(0)}"),
                                Text(
                                  "Paid: Rs. ${paid.toStringAsFixed(0)}",
                                  style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  "Left: Rs. ${remaining.toStringAsFixed(0)}",
                                  style: TextStyle(
                                      color: remaining > 0
                                          ? Colors.red.shade700
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryItem(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          "Rs. ${amount.toStringAsFixed(0)}",
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  // PDF Generation Function
  Future<void> _generateAndPrintPdf(BuildContext context) async {
    final pdf = pw.Document();

    var snapshot =
        await schoolCollection('expenses').get();

    if (snapshot.docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "No expense record available to generate PDF!")),
        );
      }
      return;
    }

    var docs = snapshot.docs;
    List<Map<String, dynamic>> pdfList = [];
    double gTotal = 0.0;
    double gPaid = 0.0;
    double gRemaining = 0.0;

    for (var doc in docs) {
      var data = doc.data();

      double total = _parseNum(data['total'] ?? data['paid']);
      double paid = _parseNum(data['paid']);
      double remaining = _parseNum(data['remaining']);

      gTotal += total;
      gPaid += paid;
      gRemaining += remaining;

      pdfList.add({
        'name': data['name'] ?? 'N/A',
        'description': data['description'] ?? '',
        'date': _parseDate(data['date'] ?? data['timestamp']),
        'total': total,
        'paid': paid,
        'remaining': remaining,
      });
    }

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
                  pw.Text("Expense Detailed Report",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            // PDF Summary Box
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                color: PdfColors.grey200,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Text("Total: Rs. ${gTotal.toStringAsFixed(0)}",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("Paid: Rs. ${gPaid.toStringAsFixed(0)}",
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green800)),
                  pw.Text("Remaining: Rs. ${gRemaining.toStringAsFixed(0)}",
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.red800)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Sr.', 'Name / Desc', 'Date', 'Total', 'Paid', 'Left'],
              data: List.generate(pdfList.length, (index) {
                var item = pdfList[index];
                return [
                  "${index + 1}",
                  "${item['name']}\n${item['description']}",
                  item['date'],
                  "Rs. ${item['total'].toStringAsFixed(0)}",
                  "Rs. ${item['paid'].toStringAsFixed(0)}",
                  "Rs. ${item['remaining'].toStringAsFixed(0)}",
                ];
              }),
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          ];
        },
      ),
    );

    await showPdfPreviewPage(
      context,
      title: "Expense Report Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
