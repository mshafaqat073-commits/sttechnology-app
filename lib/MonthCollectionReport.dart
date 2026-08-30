import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class MonthCollectionReport extends StatefulWidget {
  const MonthCollectionReport({super.key});

  @override
  State<MonthCollectionReport> createState() => _MonthCollectionReportState();
}

class _MonthCollectionReportState extends State<MonthCollectionReport> {
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

  // Helper function to convert a date into a clean, readable format
  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';

    try {
      if (dateValue is Timestamp) {
        DateTime dt = dateValue.toDate();
        return DateFormat('dd MMM yyyy').format(dt); // e.g., 22 Jul 2026
      }

      String str = dateValue.toString();
      // If the date is already in a standard format, parse it and make it readable
      DateTime? parsedDate = DateTime.tryParse(str);
      if (parsedDate != null) {
        return DateFormat('dd MMM yyyy').format(parsedDate);
      }

      return str;
    } catch (e) {
      return dateValue.toString();
    }
  }

  // Derives a standard sort key (yyyy-MM-dd) from a raw date string
  String _getDateKey(dynamic dateValue) {
    if (dateValue == null) return 'Unknown Date';
    try {
      if (dateValue is Timestamp) {
        return DateFormat('yyyy-MM-dd').format(dateValue.toDate());
      }
      String str = dateValue.toString();
      DateTime? parsedDate = DateTime.tryParse(str);
      if (parsedDate != null) {
        return DateFormat('yyyy-MM-dd').format(parsedDate);
      }
      // If it's a plain text format, try taking the first 10 characters (yyyy-MM-dd)
      if (str.length >= 10) {
        return str.substring(0, 10);
      }
      return str;
    } catch (e) {
      return 'Unknown Date';
    }
  }

  // Matches a 'date' or 'timestamp' field against the current month — both
  // fee_history and other_incomes collections are filtered using this same
  // logic, so this common helper covers both.
  bool _isInMonth(dynamic dateValue, String currentMonthPrefix,
      String monthNameStr, String yearStr) {
    if (dateValue == null) return false;

    if (dateValue is Timestamp) {
      DateTime dt = dateValue.toDate();
      return DateFormat('yyyy-MM').format(dt) == currentMonthPrefix;
    }

    String dateStr = dateValue.toString().toLowerCase();

    return dateStr.contains(currentMonthPrefix) ||
        (dateStr.contains(monthNameStr) && dateStr.contains(yearStr));
  }

  Future<void> _generateMonthCollectionPdf() async {
    setState(() => isLoading = true);

    try {
      DateTime now = DateTime.now();
      String currentMonthPrefix = DateFormat('yyyy-MM').format(now); // 2026-07
      String monthNameStr = DateFormat('MMMM').format(now).toLowerCase();
      String yearStr = now.year.toString();
      String monthTitle = DateFormat('MMMM yyyy').format(now);

      var snapshot =
          await schoolCollection('fee_history').get();

      var docs = snapshot.docs.where((d) {
        var data = d.data() as Map<String, dynamic>? ?? {};
        var dateValue = data['date'] ?? data['timestamp'];
        return _isInMonth(dateValue, currentMonthPrefix, monthNameStr, yearStr);
      }).toList();

      // Other Incomes collection (rent, donations, etc.) — included here the
      // same way profit_loss_report_page.dart does, otherwise Other Income
      // was completely missing from this report.
      List<QueryDocumentSnapshot> otherIncomeDocsRaw = [];
      try {
        var otherSnapshot = await schoolCollection('other_incomes').get();
        otherIncomeDocsRaw = otherSnapshot.docs.where((d) {
          var data = d.data() as Map<String, dynamic>? ?? {};
          var dateValue = data['date'] ?? data['timestamp'];
          return _isInMonth(
              dateValue, currentMonthPrefix, monthNameStr, yearStr);
        }).toList();
      } catch (e) {
        debugPrint("Other Incomes Error: $e");
      }

      // --- Date-wise Grouping & Sorting ---
      Map<String, List<Map<String, dynamic>>> groupedData = {};
      double feeGrandTotal = 0;
      // Field-wise (monthlyFee, admissionFee, ..., plus any custom field)
      // totals for the whole month — the 'restoredFees' map is saved by
      // pay_fee_page on every fee_history doc, and the breakdown is derived
      // from it (same pattern history_page uses).
      Map<String, double> fieldTotals = {};

      for (var doc in docs) {
        var data = doc.data() as Map<String, dynamic>? ?? {};
        var rawDate = data['date'] ?? data['timestamp'];
        String dateKey = _getDateKey(rawDate);

        groupedData.putIfAbsent(dateKey, () => []);
        groupedData[dateKey]!.add(data);

        double amount = double.tryParse(
                (data['amountPaid'] ?? data['amount'] ?? data['paid'] ?? '0')
                    .toString()) ??
            0;
        feeGrandTotal += amount;

        Map<String, dynamic> restoredFees = data['restoredFees'] != null
            ? Map<String, dynamic>.from(data['restoredFees'])
            : {};
        for (var f in _orderedFeeFields(restoredFees)) {
          double val = double.tryParse(restoredFees[f]?.toString() ?? '0') ?? 0;
          fieldTotals[f] = (fieldTotals[f] ?? 0) + val;
        }
      }

      // Other Income is also grouped by date, so it can be shown by date
      // the same way fee collections are.
      Map<String, List<Map<String, dynamic>>> otherIncomeGrouped = {};
      double otherIncomeGrandTotal = 0;

      for (var doc in otherIncomeDocsRaw) {
        var data = doc.data() as Map<String, dynamic>? ?? {};
        var rawDate = data['date'] ?? data['timestamp'];
        String dateKey = _getDateKey(rawDate);

        otherIncomeGrouped.putIfAbsent(dateKey, () => []);
        otherIncomeGrouped[dateKey]!.add(data);

        double amount = double.tryParse(
                (data['amountPaid'] ?? data['amount'] ?? data['paid'] ?? '0')
                    .toString()) ??
            0;
        otherIncomeGrandTotal += amount;
      }

      double combinedGrandTotal = feeGrandTotal + otherIncomeGrandTotal;

      // Sort the dates (ascending order: oldest date first, newest last)
      var sortedKeys = groupedData.keys.toList()..sort();
      var otherIncomeSortedKeys = otherIncomeGrouped.keys.toList()..sort();

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (context) {
            List<pw.Widget> widgets = [];

            // Header Section
            widgets.add(
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(currentSchoolDisplayName(),
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Monthly Collection Report",
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            );
            widgets.add(pw.SizedBox(height: 10));
            widgets.add(pw.Text("Month: $monthTitle",
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)));
            widgets.add(pw.SizedBox(height: 10));

            // Grand Total Summary Box
            widgets.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                        "Total Transactions: ${docs.length + otherIncomeDocsRaw.length}",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Fee Collection: Rs. $feeGrandTotal"),
                        pw.Text("Other Income: Rs. $otherIncomeGrandTotal"),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Divider(color: PdfColors.grey400),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Grand Total:",
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text("Rs. $combinedGrandTotal",
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.green700)),
                      ],
                    ),
                  ],
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 15));

            // Overall Fee-wise Breakdown for the month
            if (fieldTotals.isNotEmpty) {
              widgets.add(pw.Text("Fee-wise Breakdown (Whole Month)",
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)));
              widgets.add(pw.SizedBox(height: 5));
              widgets.add(
                pw.Table.fromTextArray(
                  headers: ['Fee Head', 'Amount'],
                  data: [
                    for (var f in _orderedFeeFields(fieldTotals))
                      [
                        _formatFieldLabel(f),
                        "Rs. ${fieldTotals[f]!.toStringAsFixed(0)}"
                      ],
                  ],
                  headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.grey300),
                ),
              );
              widgets.add(pw.SizedBox(height: 15));
            }

            if (docs.isEmpty) {
              widgets.add(pw.Text("No collection recorded for this month.",
                  style: const pw.TextStyle(fontSize: 12)));
            } else {
              int globalSr = 1;

              // Build a separate table and subtotal for each date
              for (String dateKey in sortedKeys) {
                var records = groupedData[dateKey]!;
                String readableDate = _formatDate(
                    records.first['date'] ?? records.first['timestamp']);

                double dateSubTotal = 0;
                for (var r in records) {
                  dateSubTotal += double.tryParse(
                          (r['amountPaid'] ?? r['amount'] ?? r['paid'] ?? '0')
                              .toString()) ??
                      0;
                }

                // Date Heading
                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
                    child: pw.Text("Date: $readableDate",
                        style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal800)),
                  ),
                );

                // Table for this specific date
                widgets.add(
                  pw.Table.fromTextArray(
                    headers: ['Sr.', 'Student Name', 'Class', 'Amount Paid'],
                    data: List.generate(records.length, (i) {
                      var r = records[i];
                      return [
                        "${globalSr++}",
                        r['studentName'] ?? r['name'] ?? 'N/A',
                        r['class'] ?? 'N/A',
                        "Rs. ${r['amountPaid'] ?? r['amount'] ?? r['paid'] ?? '0'}"
                      ];
                    }),
                    headerStyle: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    headerDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey300),
                  ),
                );

                // Subtotal for this specific date
                widgets.add(
                  pw.Container(
                    alignment: pw.Alignment.centerRight,
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 5, horizontal: 8),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    child: pw.Text(
                      "Subtotal ($readableDate): Rs. $dateSubTotal",
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green800),
                    ),
                  ),
                );
                widgets.add(pw.SizedBox(height: 10));
              }
            }

            // Other Income section, grouped and sub-totaled by date the
            // same way the fee section above is.
            if (otherIncomeGrouped.isNotEmpty) {
              widgets.add(pw.SizedBox(height: 10));
              widgets.add(pw.Text("Other Income",
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)));
              widgets.add(pw.SizedBox(height: 5));

              int otherIncomeSr = 1;

              for (String dateKey in otherIncomeSortedKeys) {
                var records = otherIncomeGrouped[dateKey]!;
                String readableDate = _formatDate(
                    records.first['date'] ?? records.first['timestamp']);

                double dateSubTotal = 0;
                for (var r in records) {
                  dateSubTotal += double.tryParse(
                          (r['amountPaid'] ?? r['amount'] ?? r['paid'] ?? '0')
                              .toString()) ??
                      0;
                }

                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
                    child: pw.Text("Date: $readableDate",
                        style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal800)),
                  ),
                );

                widgets.add(
                  pw.Table.fromTextArray(
                    headers: ['Sr.', 'Description', 'Category', 'Amount'],
                    data: List.generate(records.length, (i) {
                      var r = records[i];
                      return [
                        "${otherIncomeSr++}",
                        r['title'] ??
                            r['description'] ??
                            r['source'] ??
                            'Other Income',
                        r['category'] ?? 'N/A',
                        "Rs. ${r['amountPaid'] ?? r['amount'] ?? r['paid'] ?? '0'}"
                      ];
                    }),
                    headerStyle: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    headerDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey300),
                  ),
                );

                widgets.add(
                  pw.Container(
                    alignment: pw.Alignment.centerRight,
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 5, horizontal: 8),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    child: pw.Text(
                      "Subtotal ($readableDate): Rs. $dateSubTotal",
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green800),
                    ),
                  ),
                );
                widgets.add(pw.SizedBox(height: 10));
              }
            }

            return widgets;
          },
        ),
      );

      await showPdfPreviewPage(context, title: "Month Collection Report Preview", build: (format) async => pdf.save());
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
    final Color color = Colors.orange.shade800;

    return InkWell(
      onTap: isLoading ? null : _generateMonthCollectionPdf,
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
                : Icon(Icons.calendar_month, color: color, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "This Month Collection Report",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.orange),
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
