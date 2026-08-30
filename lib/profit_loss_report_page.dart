import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'performance_bar_chart.dart';

enum _PLPeriod { all, monthly, yearly }

class ProfitLossReportPage extends StatefulWidget {
  const ProfitLossReportPage({super.key});

  @override
  State<ProfitLossReportPage> createState() => _ProfitLossReportPageState();
}

class _ProfitLossReportPageState extends State<ProfitLossReportPage> {
  _PLPeriod _period = _PLPeriod.all;
  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedYear = DateTime.now().year;

  String get _periodLabel {
    switch (_period) {
      case _PLPeriod.all:
        return "All Time";
      case _PLPeriod.monthly:
        return DateFormat('MMMM yyyy').format(_selectedMonth);
      case _PLPeriod.yearly:
        return _selectedYear.toString();
    }
  }

  bool _inSelectedPeriod(dynamic rawDate) {
    if (_period == _PLPeriod.all) return true;
    DateTime? d;
    if (rawDate is Timestamp) {
      d = rawDate.toDate();
    } else if (rawDate is String) {
      d = DateTime.tryParse(rawDate);
    }
    if (d == null) return false;
    if (_period == _PLPeriod.monthly) {
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
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
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
    if (year != null) setState(() => _selectedYear = year);
  }

  // Fetches Income and Expense data (from the 'fee_history',
  // 'other_incomes' and 'expenses' collections), filtered by the
  // currently selected period (All Time / Monthly / Yearly). In
  // history_page.dart, income comes from two collections — fee_history
  // (student fee payments) and other_incomes (misc income like rent,
  // donations, etc.) — so both must be included here too, otherwise
  // Other Income is completely missed.
  Future<Map<String, double>> _getFinancialData() async {
    double feeIncome = 0.0;
    double otherIncome = 0.0;
    double totalExpense = 0.0;

    // Calculate income from the Fee History collection ('amountPaid' field)
    try {
      var feeSnapshot = await schoolCollection('fee_history').get();
      for (var doc in feeSnapshot.docs) {
        var data = doc.data();
        if (!_inSelectedPeriod(data['date'])) continue;
        var rawAmount =
            data['amountPaid'] ?? data['paidAmount'] ?? data['amount'] ?? 0;
        double amt = 0.0;
        if (rawAmount is num) {
          amt = rawAmount.toDouble();
        } else if (rawAmount is String) {
          amt = double.tryParse(rawAmount) ?? 0.0;
        }
        feeIncome += amt;
      }
    } catch (e) {
      debugPrint("Fee History Error: $e");
    }

    // Calculate income from the Other Incomes collection ('amountPaid' field)
    try {
      var otherSnapshot = await schoolCollection('other_incomes').get();
      for (var doc in otherSnapshot.docs) {
        var data = doc.data();
        if (!_inSelectedPeriod(data['date'])) continue;
        var rawAmount =
            data['amountPaid'] ?? data['amount'] ?? data['paid'] ?? 0;
        double amt = 0.0;
        if (rawAmount is num) {
          amt = rawAmount.toDouble();
        } else if (rawAmount is String) {
          amt = double.tryParse(rawAmount) ?? 0.0;
        }
        otherIncome += amt;
      }
    } catch (e) {
      debugPrint("Other Incomes Error: $e");
    }

    double totalIncome = feeIncome + otherIncome;

    // Calculate expenses from the Expenses collection ('paid' field)
    try {
      var expenseSnapshot = await schoolCollection('expenses').get();
      for (var doc in expenseSnapshot.docs) {
        var data = doc.data();
        if (!_inSelectedPeriod(data['date'])) continue;
        var rawAmount = data['paid'] ?? data['amount'] ?? data['total'] ?? 0;
        double amt = 0.0;
        if (rawAmount is num) {
          amt = rawAmount.toDouble();
        } else if (rawAmount is String) {
          amt = double.tryParse(rawAmount) ?? 0.0;
        }
        totalExpense += amt;
      }
    } catch (e) {
      debugPrint("Expenses Error: $e");
    }

    return {
      'feeIncome': feeIncome,
      'otherIncome': otherIncome,
      'income': totalIncome,
      'expense': totalExpense,
      'net': totalIncome - totalExpense,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profit & Loss Report"),
        backgroundColor: Colors.blueGrey[800],
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
              // Keyed by period so the FutureBuilder re-fetches whenever
              // the filter changes.
              key: ValueKey('$_period-$_selectedMonth-$_selectedYear'),
              future: _getFinancialData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }

                if (!snapshot.hasData) {
                  return const Center(child: Text("Data cannot be fetched."));
                }

                double feeIncome = snapshot.data!['feeIncome']!;
                double otherIncome = snapshot.data!['otherIncome']!;
                double expense = snapshot.data!['expense']!;
                double netProfit = snapshot.data!['net']!;
                bool isProfit = netProfit >= 0;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Fee Income Card
                      _buildSummaryTile(
                        title: "Fee Collection Income",
                        amount: feeIncome,
                        color: Colors.green,
                        icon: Icons.arrow_downward,
                      ),
                      const SizedBox(height: 12),

                      // Other Income Card
                      _buildSummaryTile(
                        title: "Other Income",
                        amount: otherIncome,
                        color: Colors.teal,
                        icon: Icons.arrow_downward,
                      ),
                      const SizedBox(height: 12),

                      // Expense Card
                      _buildSummaryTile(
                        title: "Total Expenses",
                        amount: expense,
                        color: Colors.red,
                        icon: Icons.arrow_upward,
                      ),
                      const SizedBox(height: 16),

                      PerformanceBarChart(
                        height: 150,
                        bars: [
                          PerformanceBarData(
                              label: "Fee Income",
                              value: feeIncome,
                              color: Colors.green),
                          PerformanceBarData(
                              label: "Other Income",
                              value: otherIncome,
                              color: Colors.teal),
                          PerformanceBarData(
                              label: "Expenses", value: expense, color: Colors.red),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(thickness: 2),
                      const SizedBox(height: 16),

                      // Net Profit / Loss Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isProfit ? Colors.green.shade50 : Colors.red.shade50,
                          border: Border.all(
                            color: isProfit ? Colors.green : Colors.red,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isProfit ? "Net Profit:" : "Net Loss:",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isProfit
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                            Text(
                              "Rs. ${netProfit.abs().toStringAsFixed(0)}",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isProfit
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
        color: Colors.blueGrey.shade50,
        border: Border.all(color: Colors.blueGrey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          SegmentedButton<_PLPeriod>(
            segments: const [
              ButtonSegment(value: _PLPeriod.all, label: Text("All Time")),
              ButtonSegment(value: _PLPeriod.monthly, label: Text("Monthly")),
              ButtonSegment(value: _PLPeriod.yearly, label: Text("Yearly")),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          if (_period == _PLPeriod.monthly) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('MMMM yyyy').format(_selectedMonth),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text("Change Month"),
                  onPressed: _pickMonth,
                ),
              ],
            ),
          ],
          if (_period == _PLPeriod.yearly) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_selectedYear.toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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

  Widget _buildSummaryTile({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          Text(
            "Rs. ${amount.toStringAsFixed(0)}",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  // PDF Generation Function
  Future<void> _generateAndPrintPdf(BuildContext context) async {
    final pdf = pw.Document();
    Map<String, double> data = await _getFinancialData();

    double feeIncome = data['feeIncome']!;
    double otherIncome = data['otherIncome']!;
    double expense = data['expense']!;
    double netProfit = data['net']!;
    bool isProfit = netProfit >= 0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
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
                    pw.Text("Profit & Loss Report",
                        style: pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text("Period: $_periodLabel",
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headers: ['Financial Description', 'Amount (PKR)'],
                data: [
                  [
                    'Fee Collection Income',
                    "Rs. ${feeIncome.toStringAsFixed(0)}"
                  ],
                  ['Other Income', "Rs. ${otherIncome.toStringAsFixed(0)}"],
                  ['Total Expenses', "Rs. ${expense.toStringAsFixed(0)}"],
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
                      color: isProfit ? PdfColors.green : PdfColors.red,
                      width: 2),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      isProfit ? "NET PROFIT" : "NET LOSS",
                      style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color:
                              isProfit ? PdfColors.green900 : PdfColors.red900),
                    ),
                    pw.Text(
                      "Rs. ${netProfit.abs().toStringAsFixed(0)}",
                      style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color:
                              isProfit ? PdfColors.green900 : PdfColors.red900),
                    ),
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
      title: "Profit & Loss Report Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
