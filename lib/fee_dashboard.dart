import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pay_fee_page.dart';
import 'history_page.dart';
import 'DefaultersPage.dart';
import 'UpdateFeePlanPage.dart';
import 'add_monthly_fee_page.dart';
import 'add_paper_money_page.dart';
import 'other_collection_page.dart';
import 'add_other_income_page.dart';
import 'responsive_grid.dart';
import 'school_context.dart';
import 'fee_fine_management_page.dart';
import 'promote_students_page.dart';

class FeeDashboard extends StatelessWidget {
  const FeeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fee Management System"),
        backgroundColor: Colors.teal[800],
      ),
      body: Column(
        children: [
          // 1. Dynamic Summary Card (now streams students, fee_history, fee_structures and other_incomes)
          StreamBuilder<QuerySnapshot>(
            stream:
                schoolCollection('students').snapshots(),
            builder: (context, studentSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: schoolCollection('fee_history')
                    .snapshots(),
                builder: (context, historySnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: schoolCollection('fee_structures')
                        .snapshots(),
                    builder: (context, feeStructureSnapshot) {
                      // Added Other Incomes Stream here
                      return StreamBuilder<QuerySnapshot>(
                        stream: schoolCollection('other_incomes')
                            .snapshots(),
                        builder: (context, otherIncomeSnapshot) {
                          double totalDues = 0;
                          double totalCollection = 0;

                          // These keys exist on the fee_structures document
                          // but aren't actual fee amounts — don't include
                          // them in the total.
                          const Set<String> nonFeeKeys = {
                            'studentId',
                            'name',
                            'fName',
                            'class',
                            'section',
                            'updatedAt',
                            'docId',
                          };

                          // Students Dues (previous dues carried on the
                          // student doc). Note: `fine` is no longer stored
                          // here — it now lives on the matching
                          // fee_structures document and is picked up
                          // automatically by the Fee Structures sum below.
                          if (studentSnapshot.hasData) {
                            for (var doc in studentSnapshot.data!.docs) {
                              var data = doc.data() as Map<String, dynamic>;
                              totalDues +=
                                  (data['dues'] as num? ?? 0).toDouble();
                            }
                          }

                          // Fee Structures (sum of whatever fields are present — default or custom)
                          if (feeStructureSnapshot.hasData) {
                            for (var doc in feeStructureSnapshot.data!.docs) {
                              var data = doc.data() as Map<String, dynamic>;
                              data.forEach((key, value) {
                                if (nonFeeKeys.contains(key)) return;
                                totalDues += (value is num) ? value.toDouble() : 0.0;
                              });
                            }
                          }

                          // Total Collection from Fee History
                          if (historySnapshot.hasData) {
                            for (var doc in historySnapshot.data!.docs) {
                              totalCollection +=
                                  (doc['amountPaid'] as num? ?? 0).toDouble();
                            }
                          }

                          // Total Collection from Other Incomes (amountPaid or amount field)
                          if (otherIncomeSnapshot.hasData) {
                            for (var doc in otherIncomeSnapshot.data!.docs) {
                              var data = doc.data() as Map<String, dynamic>;
                              // Handles both field name variants: 'amountPaid' or 'amount'
                              double otherAmount =
                                  (data['amountPaid'] ?? data['amount'] ?? 0)
                                      .toDouble();
                              totalCollection += otherAmount;
                            }
                          }

                          final double totalExpected =
                              totalCollection + totalDues;
                          final double percentReceived = totalExpected > 0
                              ? (totalCollection / totalExpected) * 100
                              : 0;

                          return Column(
                            children: [
                              _FeeCollectionGraph(
                                percentReceived: percentReceived,
                                totalCollection: totalCollection,
                                totalDues: totalDues,
                              ),
                              Card(
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: ListTile(
                                  leading: const Icon(Icons.analytics,
                                      size: 40, color: Colors.teal),
                                  title: Text(
                                      "Total Collection: PKR ${totalCollection.toStringAsFixed(0)}"),
                                  subtitle: Text(
                                      "Pending Dues: PKR ${totalDues.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red)),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),

          // 2. Action Buttons
          Expanded(
            child: ResponsiveGrid(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMenuButton(context, "Add Income/FeePage", Icons.payment,
                    const AddIncomeOrFeePage()),
                _buildMenuButton(
                    context, "Income", Icons.savings, OtherCollectionPage()),
                _buildMenuButton(
                    context, "Pay Fee", Icons.payment, const PayFeePage()),
                _buildMenuButton(
                    context, "Fee History", Icons.history, const HistoryPage()),
                _buildMenuButton(context, "Defaulters", Icons.warning,
                    const DefaultersPage()),
                _buildMenuButton(context, "Update Fee Plan", Icons.edit,
                    const UpdateFeePlanPage()),
                _buildMenuButton(context, "Add fee", Icons.calendar_month,
                    const AddMonthlyFeePage()),
                _buildMenuButton(context, "Add P.M", Icons.attach_money,
                    const AddPaperMoneyPage()),
                _buildMenuButton(context, "Fee Fine", Icons.warning_amber,
                    const FeeFineManagementPage()),
                _buildMenuButton(context, "Promote Students", Icons.upgrade,
                    const PromoteStudentsPage()),
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
      elevation: 4,
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

/// Shows what percentage of the total expected fee (collected + still
/// due) has actually been received, as a circular indicator plus a
/// stacked bar (green = received, red = remaining).
class _FeeCollectionGraph extends StatelessWidget {
  final double percentReceived;
  final double totalCollection;
  final double totalDues;

  const _FeeCollectionGraph({
    required this.percentReceived,
    required this.totalCollection,
    required this.totalDues,
  });

  @override
  Widget build(BuildContext context) {
    final double receivedFraction = (percentReceived / 100).clamp(0, 1);
    final double remainingPercent = 100 - percentReceived;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              height: 80,
              width: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 80,
                    width: 80,
                    child: CircularProgressIndicator(
                      value: receivedFraction,
                      strokeWidth: 8,
                      backgroundColor: Colors.red[100],
                      valueColor:
                          const AlwaysStoppedAnimation(Colors.green),
                    ),
                  ),
                  Text("${percentReceived.toStringAsFixed(0)}%",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Collection Status",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        children: [
                          Expanded(
                            flex: (receivedFraction * 1000).round().clamp(1, 1000),
                            child: Container(color: Colors.green),
                          ),
                          Expanded(
                            flex: ((1 - receivedFraction) * 1000)
                                .round()
                                .clamp(1, 1000),
                            child: Container(color: Colors.red[300]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _legendDot(Colors.green,
                          "Received ${percentReceived.toStringAsFixed(0)}%"),
                      const SizedBox(width: 14),
                      _legendDot(Colors.red[300]!,
                          "Remaining ${remainingPercent.toStringAsFixed(0)}%"),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
