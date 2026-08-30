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

  // These are the default fields — they are shown in this order first.
  // Any new custom field (added from set_fee_page) is automatically listed
  // after these — same pattern used in history_page/pay_fee_page, so a new
  // field shows up here automatically too.
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

  // Converts a camelCase field name into a readable label
  String _formatFieldLabel(String key) {
    if (key.isEmpty) return key;
    String spaced =
        key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  // Matches a 'date' or 'timestamp' field against today's date — both
  // fee_history and other_incomes collections are filtered using this same
  // logic, so this common helper covers both.
  bool _isToday(dynamic dateValue, DateTime now, String todayStandard) {
    if (dateValue == null) return false;

    if (dateValue is Timestamp) {
      DateTime dt = dateValue.toDate();
      return DateFormat('yyyy-MM-dd').format(dt) == todayStandard;
    }

    String dateStr = dateValue.toString().toLowerCase();
    String monthStr = DateFormat('MMMM').format(now).toLowerCase(); // july
    String yearStr = now.year.toString(); // 2026
    String todayDayNum = now.day.toString();

    // Check if date string contains current year, month name, and day number
    bool matchesFull = dateStr.contains(yearStr) &&
        dateStr.contains(monthStr) &&
        (dateStr.contains(" $todayDayNum ") ||
            dateStr.contains(", $todayDayNum") ||
            dateStr.contains("$todayDayNum,"));

    return dateStr.contains(todayStandard) || matchesFull;
  }

  Future<void> _generateTodayCollectionPdf() async {
    setState(() => isLoading = true);

    try {
      DateTime now = DateTime.now();
      String todayStandard = DateFormat('yyyy-MM-dd').format(now); // 2026-07-26
      String todayMonthName =
          DateFormat('MMMM d, yyyy').format(now); // July 26, 2026

      var snapshot =
          await schoolCollection('fee_history').get();

      var docs = snapshot.docs.where((d) {
        var data = d.data() as Map<String, dynamic>? ?? {};
        var dateValue = data['date'] ?? data['timestamp'];
        return _isToday(dateValue, now, todayStandard);
      }).toList();

      // Other Incomes collection (rent, donations, etc.) — included here the
      // same way profit_loss_report_page.dart does, otherwise Other Income
      // was completely missing from this report.
      List<QueryDocumentSnapshot> otherIncomeDocs = [];
      try {
        var otherSnapshot = await schoolCollection('other_incomes').get();
        otherIncomeDocs = otherSnapshot.docs.where((d) {
          var data = d.data() as Map<String, dynamic>? ?? {};
          var dateValue = data['date'] ?? data['timestamp'];
          return _isToday(dateValue, now, todayStandard);
        }).toList();
      } catch (e) {
        debugPrint("Other Incomes Error: $e");
      }

      double totalAmount = 0;
      // Field-wise (monthlyFee, admissionFee, ..., plus any custom field)
      // totals — the 'restoredFees' map is saved by pay_fee_page on every
      // fee_history doc, and the breakdown is derived from it.
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

      double otherIncomeTotal = 0;
      for (var doc in otherIncomeDocs) {
        var data = doc.data() as Map<String, dynamic>? ?? {};
        double amount = double.tryParse(
                (data['amountPaid'] ?? data['amount'] ?? data['paid'] ?? '0')
                    .toString()) ??
            0;
        otherIncomeTotal += amount;
      }

      double grandTotal = totalAmount + otherIncomeTotal;

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
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                          "Total Transactions: ${docs.length + otherIncomeDocs.length}",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Fee Collection: Rs. $totalAmount"),
                      pw.Text("Other Income: Rs. $otherIncomeTotal"),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.grey400),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Grand Total:",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text("Rs. $grandTotal",
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.green700)),
                    ],
                  ),
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
            if (otherIncomeDocs.isNotEmpty) ...[
              pw.SizedBox(height: 15),
              pw.Text("Other Income",
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              pw.Table.fromTextArray(
                headers: ['Sr.', 'Description', 'Category', 'Amount'],
                data: List.generate(otherIncomeDocs.length, (i) {
                  var d =
                      otherIncomeDocs[i].data() as Map<String, dynamic>? ?? {};
                  return [
                    "${i + 1}",
                    d['title'] ??
                        d['description'] ??
                        d['source'] ??
                        'Other Income',
                    d['category'] ?? 'N/A',
                    "Rs. ${d['amountPaid'] ?? d['amount'] ?? d['paid'] ?? '0'}"
                  ];
                }),
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
