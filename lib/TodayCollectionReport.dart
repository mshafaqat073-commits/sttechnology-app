import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class TodayCollectionReport extends StatefulWidget {
  const TodayCollectionReport({super.key});

  @override
  State<TodayCollectionReport> createState() => _TodayCollectionReportState();
}

class _TodayCollectionReportState extends State<TodayCollectionReport> {
  bool isLoading = false;

  // Ye default fields hain — inhi ki tarteeb pehle dikhai jayegi.
  // Koi bhi naya custom field (set_fee_page se add kiya gaya) automatically
  // inke baad list ho jayega — same pattern jo history_page/pay_fee_page
  // mein use hota hai, taake naya field yahan bhi khud-b-khud aa jaye.
  static const List<String> _defaultFieldOrder = [
    'monthlyFee',
    'admissionFee',
    'books',
    'notebooks',
    'diary',
    'file',
    'stationary',
    'paperMoney',
    'uniform',
    'other',
  ];

  List<String> _orderedFeeFields(Map<String, dynamic> feeData) {
    List<String> known =
        _defaultFieldOrder.where((f) => feeData.containsKey(f)).toList();
    List<String> extra = feeData.keys
        .where((f) => !_defaultFieldOrder.contains(f))
        .toList()
      ..sort();
    return [...known, ...extra];
  }

  // camelCase field name ko readable label me convert karta hai
  String _formatFieldLabel(String key) {
    if (key.isEmpty) return key;
    String spaced =
        key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  Future<void> _generateTodayCollectionPdf() async {
    setState(() => isLoading = true);

    try {
      DateTime now = DateTime.now();
      String todayStandard = DateFormat('yyyy-MM-dd').format(now); // 2026-07-26
      String todayMonthName =
          DateFormat('MMMM d, yyyy').format(now); // July 26, 2026
      String todayDayNum =
          now.day.toString(); // 26 (ya single digit ke liye bhi check)

      var snapshot =
          await schoolCollection('fee_history').get();

      var docs = snapshot.docs.where((d) {
        var data = d.data() as Map<String, dynamic>? ?? {};
        var dateValue = data['date'] ?? data['timestamp'];

        if (dateValue == null) return false;

        if (dateValue is Timestamp) {
          DateTime dt = dateValue.toDate();
          return DateFormat('yyyy-MM-dd').format(dt) == todayStandard;
        }

        String dateStr = dateValue.toString().toLowerCase();
        String monthStr = DateFormat('MMMM').format(now).toLowerCase(); // july
        String yearStr = now.year.toString(); // 2026

        // Check if date string contains current year, month name, and day number
        bool matchesFull = dateStr.contains(yearStr) &&
            dateStr.contains(monthStr) &&
            (dateStr.contains(" $todayDayNum ") ||
                dateStr.contains(", $todayDayNum") ||
                dateStr.contains("$todayDayNum,"));

        return dateStr.contains(todayStandard) || matchesFull;
      }).toList();

      double totalAmount = 0;
      // Field-wise (monthlyFee, admissionFee, ..., aur koi bhi custom field)
      // totals — 'restoredFees' map fee_history ke har doc mein pay_fee_page
      // ne save kiya hota hai, wahi se breakdown nikal rahe hain.
      Map<String, double> fieldTotals = {};

      for (var doc in docs) {
        var data = doc.data() as Map<String, dynamic>? ?? {};
        double amount = double.tryParse(
                (data['amountPaid'] ?? data['amount'] ?? data['paid'] ?? '0')
                    .toString()) ??
            0;
        totalAmount += amount;

        Map<String, dynamic> restoredFees = data['restoredFees'] != null
            ? Map<String, dynamic>.from(data['restoredFees'])
            : {};
        for (var f in _orderedFeeFields(restoredFees)) {
          double val = double.tryParse(restoredFees[f]?.toString() ?? '0') ?? 0;
          fieldTotals[f] = (fieldTotals[f] ?? 0) + val;
        }
      }

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(currentSchoolDisplayName(),
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Today Collection Report",
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text("Date: $todayMonthName",
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Total Transactions: ${docs.length}",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("Total Collection: Rs. $totalAmount",
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green700)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),
            docs.isEmpty
                ? pw.Text("No collection recorded for today.",
                    style: const pw.TextStyle(fontSize: 12))
                : pw.Table.fromTextArray(
                    headers: [
                      'Sr.',
                      'Student Name',
                      'Class',
                      'Amount Paid'
                    ],
                    data: List.generate(docs.length, (i) {
                      var d = docs[i].data() as Map<String, dynamic>? ?? {};
                      return [
                        "${i + 1}",
                        d['studentName'] ?? d['name'] ?? 'N/A',
                        d['class'] ?? 'N/A',
                        "Rs. ${d['amountPaid'] ?? d['amount'] ?? d['paid'] ?? '0'}"
                      ];
                    }),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    headerDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey300),
                  ),
            if (fieldTotals.isNotEmpty) ...[
              pw.SizedBox(height: 15),
              pw.Text("Fee-wise Breakdown",
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              pw.Table.fromTextArray(
                headers: ['Fee Head', 'Amount'],
                data: [
                  for (var f in _orderedFeeFields(fieldTotals))
                    [
                      _formatFieldLabel(f),
                      "Rs. ${fieldTotals[f]!.toStringAsFixed(0)}"
                    ],
                ],
                headerStyle:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 10),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
              ),
            ],
          ],
        ),
      );

      await showPdfPreviewPage(context, title: "Today Collection Report Preview", build: (format) async => pdf.save());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generating PDF: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = Colors.green.shade700;

    return InkWell(
      onTap: isLoading ? null : _generateTodayCollectionPdf,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 55,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.today, color: color, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "Today Collection Report",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.green),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
