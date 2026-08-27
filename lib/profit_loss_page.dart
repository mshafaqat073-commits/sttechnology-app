import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';

/// Dashboard's quick Profit & Loss card — now with a period filter so it
/// can show All-time, a specific Month, or a specific Year's income vs
/// expense instead of only the all-time total.
class ProfitLossPage extends StatefulWidget {
  const ProfitLossPage({super.key});

  @override
  State<ProfitLossPage> createState() => _ProfitLossPageState();
}

enum _PLPeriod { all, monthly, yearly }

class _ProfitLossPageState extends State<ProfitLossPage> {
  _PLPeriod _period = _PLPeriod.all;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedYear = DateTime.now().year;

  bool _inSelectedPeriod(Timestamp? ts) {
    if (_period == _PLPeriod.all) return true;
    if (ts == null) return false;
    final d = ts.toDate();
    if (_period == _PLPeriod.monthly) {
      return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
    }
    // yearly
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profit & Loss Report")),
      body: Column(
        children: [
          _buildPeriodBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Fees: from fee_history 'amountPaid'
              stream: schoolCollection('fee_history').snapshots(),
              builder: (context, feeSnap) {
                return StreamBuilder<QuerySnapshot>(
                  // Expenses: from expenses 'paid' (as saved by AddExpensePage)
                  stream: schoolCollection('expenses').snapshots(),
                  builder: (context, expSnap) {
                    return StreamBuilder<QuerySnapshot>(
                      // Monthly fee average: sum of monthlyFee across all
                      // students, divided by total number of students.
                      stream: schoolCollection('students').snapshots(),
                      builder: (context, studentSnap) {
                        if (!feeSnap.hasData ||
                            !expSnap.hasData ||
                            !studentSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        // Calculate Total Income (filtered by selected period)
                        double totalIncome = 0;
                        for (var doc in feeSnap.data!.docs) {
                          var data = doc.data() as Map<String, dynamic>;
                          if (!_inSelectedPeriod(data['date'] as Timestamp?)) {
                            continue;
                          }
                          totalIncome += (data['amountPaid'] ?? 0).toDouble();
                        }

                        // Calculate Total Expenses (filtered by selected period)
                        double totalExpense = 0;
                        for (var doc in expSnap.data!.docs) {
                          var data = doc.data() as Map<String, dynamic>;
                          if (!_inSelectedPeriod(data['date'] as Timestamp?)) {
                            continue;
                          }
                          totalExpense += (data['paid'] ?? 0).toDouble();
                        }

                        double netProfit = totalIncome - totalExpense;

                        // Average (Monthly) Fee = sum of every student's
                        // monthlyFee (from the students collection) divided by
                        // the total number of students. This is a current
                        // snapshot, not a flow, so it isn't affected by the
                        // period filter.
                        double totalMonthlyFee = 0;
                        for (var doc in studentSnap.data!.docs) {
                          var data = doc.data() as Map<String, dynamic>;
                          totalMonthlyFee += (data['monthlyFee'] ?? 0).toDouble();
                        }
                        final int studentCount = studentSnap.data!.docs.length;
                        final double averageFee =
                            studentCount > 0 ? totalMonthlyFee / studentCount : 0;

                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              _buildStatCard("Total Income",
                                  "Rs. ${totalIncome.toStringAsFixed(0)}", Colors.green),
                              _buildStatCard("Total Expenses",
                                  "Rs. ${totalExpense.toStringAsFixed(0)}", Colors.red),
                              const Divider(height: 40, thickness: 2),
                              _buildStatCard(
                                netProfit >= 0 ? "Net Profit" : "Net Loss",
                                "Rs. ${netProfit.abs().toStringAsFixed(0)}",
                                netProfit >= 0 ? Colors.blue : Colors.orange,
                              ),
                              const Divider(height: 40, thickness: 2),
                              _buildStatCard(
                                "Average Monthly Fee (per student)",
                                "Rs. ${averageFee.toStringAsFixed(0)}",
                                Colors.purple,
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
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
        color: Colors.blue.shade50,
        border: Border.all(color: Colors.blue.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<_PLPeriod>(
                  segments: const [
                    ButtonSegment(value: _PLPeriod.all, label: Text("All Time")),
                    ButtonSegment(value: _PLPeriod.monthly, label: Text("Monthly")),
                    ButtonSegment(value: _PLPeriod.yearly, label: Text("Yearly")),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() => _period = s.first),
                ),
              ),
            ],
          ),
          if (_period == _PLPeriod.monthly) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('MMMM yyyy').format(_selectedMonth),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.blue)),
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
                        fontWeight: FontWeight.bold, color: Colors.blue)),
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

  Widget _buildStatCard(String title, String value, Color color) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        trailing: Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
