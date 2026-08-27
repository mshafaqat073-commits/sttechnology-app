import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

/// Balance Sheet — a simple school-finance snapshot:
///
///   ASSETS
///     Cash Collected     = Fee Collection + Other Income
///     Accounts Receivable = Pending Student Dues (fee still owed)
///   -------------------------------------------------------------
///   LIABILITIES / EXPENSES
///     Total Expenses Paid
///   -------------------------------------------------------------
///   NET POSITION = Total Assets − Total Liabilities
///
/// The period filter (All Time / Monthly / Yearly) only applies to the
/// CASH FLOW figures (fee income, other income, expenses paid) — these
/// have a date attached and can meaningfully be scoped to a period.
/// "Accounts Receivable (Pending Dues)" is a running balance as of right
/// now, not a flow, so it always reflects the current total regardless
/// of the period filter (there's no historical "dues as of last month"
/// data stored).
enum _BSPeriod { all, monthly, yearly }

class BalanceSheetPage extends StatefulWidget {
  const BalanceSheetPage({super.key});

  @override
  State<BalanceSheetPage> createState() => _BalanceSheetPageState();
}

class _BalanceSheetPageState extends State<BalanceSheetPage> {
  _BSPeriod _period = _BSPeriod.all;
  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedYear = DateTime.now().year;

  String get _periodLabel {
    switch (_period) {
      case _BSPeriod.all:
        return "All Time";
      case _BSPeriod.monthly:
        return DateFormat('MMMM yyyy').format(_selectedMonth);
      case _BSPeriod.yearly:
        return _selectedYear.toString();
    }
  }

  bool _inSelectedPeriod(dynamic rawDate) {
    if (_period == _BSPeriod.all) return true;
    DateTime? d;
    if (rawDate is Timestamp) {
      d = rawDate.toDate();
    } else if (rawDate is String) {
      d = DateTime.tryParse(rawDate);
    }
    if (d == null) return false;
    if (_period == _BSPeriod.monthly) {
      return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
    }
    return d.year == _selectedYear;
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: "Pick any date in the month",
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
        _dataFuture = _getBalanceSheetData();
      });
    }
  }

  Future<void> _pickYear() async {
    final now = DateTime.now();
    final year = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Select Year"),
        children: [
          for (int y = now.year; y >= now.year - 6; y--)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, y),
              child: Text(y.toString()),
            ),
        ],
      ),
    );
    if (year != null) {
      setState(() {
        _selectedYear = year;
        _dataFuture = _getBalanceSheetData();
      });
    }
  }

  void _changePeriod(_BSPeriod p) {
    setState(() {
      _period = p;
      _dataFuture = _getBalanceSheetData();
    });
  }

  // Re-created whenever the period filter changes (see _changePeriod /
  // _pickMonth / _pickYear above); the PDF button reuses this instead of
  // hitting Firestore again.
  late Future<Map<String, double>> _dataFuture = _getBalanceSheetData();

  Future<QuerySnapshot<Map<String, dynamic>>?> _safeGet(
      String collection, String label) async {
    try {
      return await schoolCollection(collection).get();
    } catch (e) {
      debugPrint("$label Error: $e");
      return null;
    }
  }

  Future<Map<String, double>> _getBalanceSheetData() async {
    double feeIncome = 0.0;
    double otherIncome = 0.0;
    double totalExpense = 0.0;
    double pendingDues = 0.0;

    // These keys exist on the fee_structures document but aren't
    // actual fee amounts — don't include them in the receivable total.
    const Set<String> nonFeeKeys = {
      'studentId',
      'name',
      'fName',
      'class',
      'section',
      'updatedAt',
      'docId',
    };

    // Run all 5 Firestore reads in parallel instead of one-by-one —
    // this was the main reason the spinner took so long: each query
    // was waiting for the previous one to finish before starting.
    final results = await Future.wait([
      _safeGet('fee_history', 'Fee History'),
      _safeGet('other_incomes', 'Other Incomes'),
      _safeGet('expenses', 'Expenses'),
      _safeGet('students', 'Students'),
      _safeGet('fee_structures', 'Fee Structures'),
    ]);

    final feeSnapshot = results[0];
    if (feeSnapshot != null) {
      for (var doc in feeSnapshot.docs) {
        var data = doc.data();
        if (!_inSelectedPeriod(data['date'])) continue;
        feeIncome += (data['amountPaid'] as num? ?? 0).toDouble();
      }
    }

    final otherSnapshot = results[1];
    if (otherSnapshot != null) {
      for (var doc in otherSnapshot.docs) {
        var data = doc.data();
        if (!_inSelectedPeriod(data['date'])) continue;
        var raw = data['amountPaid'] ?? data['amount'] ?? 0;
        otherIncome += (raw as num? ?? 0).toDouble();
      }
    }

    final expenseSnapshot = results[2];
    if (expenseSnapshot != null) {
      for (var doc in expenseSnapshot.docs) {
        var data = doc.data();
        if (!_inSelectedPeriod(data['date'])) continue;
        var raw = data['paid'] ?? data['amount'] ?? 0;
        totalExpense += (raw as num? ?? 0).toDouble();
      }
    }

    // Pending dues = dues carried on the student doc + whatever is
    // still owed in each student's fee_structures (same calculation
    // fee_dashboard.dart uses for "Pending Dues"). This is always the
    // CURRENT total — see the class-level doc comment above.
    final studentSnapshot = results[3];
    if (studentSnapshot != null) {
      for (var doc in studentSnapshot.docs) {
        var data = doc.data();
        pendingDues += (data['dues'] as num? ?? 0).toDouble();
      }
    }

    final feeStructSnapshot = results[4];
    if (feeStructSnapshot != null) {
      for (var doc in feeStructSnapshot.docs) {
        var data = doc.data();
        data.forEach((key, value) {
          if (nonFeeKeys.contains(key)) return;
          pendingDues += (value is num) ? value.toDouble() : 0.0;
        });
      }
    }

    final double cashCollected = feeIncome + otherIncome;
    final double totalAssets = cashCollected + pendingDues;
    final double totalLiabilities = totalExpense;
    final double netPosition = totalAssets - totalLiabilities;

    return {
      'cashCollected': cashCollected,
      'pendingDues': pendingDues,
      'totalAssets': totalAssets,
      'totalLiabilities': totalLiabilities,
      'netPosition': netPosition,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Balance Sheet"),
        backgroundColor: Colors.brown[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Download/Print PDF",
            onPressed: () => _generateAndPrintPdf(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPeriodBar(),
          Expanded(
            child: FutureBuilder<Map<String, double>>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData) {
                  return const Center(child: Text("Data cannot be fetched."));
                }

                final d = snapshot.data!;
                final bool positive = d['netPosition']! >= 0;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text("ASSETS",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.teal)),
                    const SizedBox(height: 8),
                    _row("Cash Collected (Fee + Other Income)",
                        d['cashCollected']!, Colors.green),
                    _row("Accounts Receivable (Pending Dues — current)",
                        d['pendingDues']!, Colors.orange),
                    const Divider(thickness: 2),
                    _row("Total Assets", d['totalAssets']!, Colors.teal,
                        bold: true),
                    const SizedBox(height: 20),
                    const Text("LIABILITIES / EXPENSES",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.red)),
                    const SizedBox(height: 8),
                    _row("Total Expenses Paid", d['totalLiabilities']!,
                        Colors.red),
                    const Divider(thickness: 2),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color:
                            positive ? Colors.green.shade50 : Colors.red.shade50,
                        border: Border.all(
                            color: positive ? Colors.green : Colors.red,
                            width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("NET POSITION",
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: positive
                                      ? Colors.green.shade800
                                      : Colors.red.shade800)),
                          Text("Rs. ${d['netPosition']!.toStringAsFixed(0)}",
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: positive
                                      ? Colors.green.shade800
                                      : Colors.red.shade800)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.brown.shade50,
        border: Border.all(color: Colors.brown.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          SegmentedButton<_BSPeriod>(
            segments: const [
              ButtonSegment(value: _BSPeriod.all, label: Text("All Time")),
              ButtonSegment(value: _BSPeriod.monthly, label: Text("Monthly")),
              ButtonSegment(value: _BSPeriod.yearly, label: Text("Yearly")),
            ],
            selected: {_period},
            onSelectionChanged: (s) => _changePeriod(s.first),
          ),
          if (_period == _BSPeriod.monthly) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('MMMM yyyy').format(_selectedMonth),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.brown)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text("Change Month"),
                  onPressed: _pickMonth,
                ),
              ],
            ),
          ],
          if (_period == _BSPeriod.yearly) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_selectedYear.toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.brown)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: const Text("Change Year"),
                  onPressed: _pickYear,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, double amount, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          Text("Rs. ${amount.toStringAsFixed(0)}",
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: bold ? 17 : 15)),
        ],
      ),
    );
  }

  Future<void> _generateAndPrintPdf(BuildContext context) async {
    // Reuse the already-fetched data instead of hitting Firestore
    // again — this was doubling the wait time whenever the PDF
    // button was pressed.
    final data = await _dataFuture;
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(currentSchoolDisplayName(),
                        style: pw.TextStyle(
                            fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Balance Sheet",
                        style: pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text("Period: $_periodLabel",
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              pw.Text("ASSETS",
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Table.fromTextArray(
                headers: ['Description', 'Amount (PKR)'],
                data: [
                  [
                    'Cash Collected (Fee + Other Income)',
                    "Rs. ${data['cashCollected']!.toStringAsFixed(0)}"
                  ],
                  [
                    'Accounts Receivable (Pending Dues — current)',
                    "Rs. ${data['pendingDues']!.toStringAsFixed(0)}"
                  ],
                  [
                    'Total Assets',
                    "Rs. ${data['totalAssets']!.toStringAsFixed(0)}"
                  ],
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellPadding: const pw.EdgeInsets.all(8),
              ),
              pw.SizedBox(height: 16),
              pw.Text("LIABILITIES / EXPENSES",
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Table.fromTextArray(
                headers: ['Description', 'Amount (PKR)'],
                data: [
                  [
                    'Total Expenses Paid',
                    "Rs. ${data['totalLiabilities']!.toStringAsFixed(0)}"
                  ],
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellPadding: const pw.EdgeInsets.all(8),
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: data['netPosition']! >= 0
                          ? PdfColors.green
                          : PdfColors.red,
                      width: 2),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("NET POSITION",
                        style: pw.TextStyle(
                            fontSize: 15, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        "Rs. ${data['netPosition']!.toStringAsFixed(0)}",
                        style: pw.TextStyle(
                            fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    if (!context.mounted) return;
    await showPdfPreviewPage(
      context,
      title: "Balance Sheet Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
