import 'package:flutter/material.dart';
import 'pay_fee_page.dart';
import 'history_page.dart';
import 'DefaultersPage.dart';
import 'UpdateFeePlanPage.dart';
import 'responsive_grid.dart';
import 'school_context.dart';

class FeeDashboard extends StatefulWidget {
  const FeeDashboard({super.key});

  @override
  State<FeeDashboard> createState() => _FeeDashboardState();
}

class _FeeDashboardState extends State<FeeDashboard> {
  double _pendingDues = 0;
  double _totalCollection = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    await _calculateTotals();
  }

  Future<void> _calculateTotals() async {
    double duesTotal = 0;
    double collectionTotal = 0;

    // These keys exist in the fee_structures document but are not actual
    // fee amounts — do not include them in the total.
    const Set<String> nonFeeKeys = {
      'studentId',
      'name',
      'fName',
      'class',
      'section',
      'updatedAt',
      'docId',
    };

    try {
      // 1. Sum of Fee Structures (whatever fields exist — default or custom)
      var feeSnapshot = await schoolCollection('fee_structures').get();

      for (var doc in feeSnapshot.docs) {
        Map<String, dynamic> data = doc.data();
        data.forEach((key, val) {
          if (nonFeeKeys.contains(key)) return;
          duesTotal += (val is num) ? val.toDouble() : 0.0;
        });
      }

      // 2. Total Collection (from History)
      var historySnapshot = await schoolCollection('fee_history').get();
      for (var doc in historySnapshot.docs) {
        var val = doc.data()['amountPaid'] ?? 0;
        collectionTotal += (val is num) ? val.toDouble() : 0.0;
      }

      if (mounted) {
        setState(() {
          _pendingDues = duesTotal;
          _totalCollection = collectionTotal;
          _isLoading = false;
        });
        debugPrint("Final Pending Dues: $_pendingDues");
      }
    } catch (e) {
      debugPrint("Error calculating: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Fee Management")),
      body: Column(
        children: [
          // Summary Card
          Card(
            margin: const EdgeInsets.all(16),
            child: ListTile(
              title: Text(
                  "Total Collection: PKR ${_totalCollection.toStringAsFixed(0)}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
              subtitle: _isLoading
                  ? const Text("Calculating...")
                  : Text("Pending Dues: PKR ${_pendingDues.toStringAsFixed(0)}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red)),
              trailing: IconButton(
                  icon: const Icon(Icons.refresh), onPressed: _refreshData),
            ),
          ),

          Expanded(
            child: ResponsiveGrid(
              padding: const EdgeInsets.all(10),
              children: [
                _buildMenuButton(
                    context, "Pay Fee", Icons.payment, const PayFeePage()),
                _buildMenuButton(
                    context, "Fee History", Icons.history, const HistoryPage()),
                _buildMenuButton(context, "Defaulters", Icons.warning,
                    const DefaultersPage()),
                _buildMenuButton(context, "Update Fee Plan", Icons.edit,
                    const UpdateFeePlanPage()),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMenuButton(
      BuildContext context, String title, IconData icon, Widget page) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (context) => page)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: Colors.teal[800]),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
