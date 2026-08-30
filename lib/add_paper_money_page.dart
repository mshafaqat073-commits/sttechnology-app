import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'subscription_gate.dart';

class AddPaperMoneyPage extends StatefulWidget {
  const AddPaperMoneyPage({super.key});

  @override
  State<AddPaperMoneyPage> createState() => _AddPaperMoneyPageState();
}

class _AddPaperMoneyPageState extends State<AddPaperMoneyPage> {
  final TextEditingController amountController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  Future<void> _addPaperMoney(BuildContext context) async {
    if (!await SubscriptionGuard.ensureActive(context)) return;
    double amount = double.tryParse(amountController.text) ?? 0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Please enter a valid amount!")));
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // 1. Loading dikhayein
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Processing...")));

      // 2. Query Active Students
      var students = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();

      if (students.docs.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No active students were found!")));
        }
        setState(() => _isProcessing = false);
        return;
      }

      // 3. Batch Set with Merge (to eliminate the error)
      var batch = FirebaseFirestore.instance.batch();

      // How much amount was added for each student — needed for "Undo".
      Map<String, double> studentAmounts = {};

      for (var doc in students.docs) {
        var feeRef = schoolCollection('fee_structures')
            .doc(doc.id);

        // Using batch.set(..., SetOptions(merge: true)) instead of batch.update
        // so that a new document is created if one doesn't exist, avoiding an error
        batch.set(
          feeRef,
          {'paperMoney': FieldValue.increment(amount)},
          SetOptions(merge: true),
        );

        studentAmounts[doc.id] = amount;
      }

      // Save a log of this operation so it can be undone later
      var logRef =
          schoolCollection('bulk_fee_operations').doc();
      batch.set(logRef, {
        'type': 'Paper Money',
        'field': 'paperMoney',
        'studentAmounts': studentAmounts,
        'totalStudents': studentAmounts.length,
        'totalAmount': studentAmounts.values.fold(0.0, (a, b) => a + b),
        'timestamp': FieldValue.serverTimestamp(),
        'reverted': false,
      });

      // 4. Commit
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Success: Paper Money added to all!")));
        amountController.clear();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Reverses a previously performed "Add Paper Money" operation —
  // subtracts back the same amount from each student that was added at
  // that time, and marks the log as "reverted".
  Future<void> _undoOperation(
      BuildContext context, DocumentSnapshot logDoc) async {
    var data = logDoc.data() as Map<String, dynamic>;
    int totalStudents = data['totalStudents'] ?? 0;
    double totalAmount = (data['totalAmount'] ?? 0).toDouble();

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Undo Paper Money?"),
        content: Text(
            "This operation will deduct a total of Rs. ${totalAmount.toStringAsFixed(0)} back from $totalStudents students. Confirm?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Undo", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      Map<String, dynamic> studentAmounts =
          Map<String, dynamic>.from(data['studentAmounts'] ?? {});

      var batch = FirebaseFirestore.instance.batch();
      studentAmounts.forEach((studentId, amt) {
        double amount = (amt as num).toDouble();
        var feeRef = schoolCollection('fee_structures')
            .doc(studentId);
        batch.set(feeRef, {'paperMoney': FieldValue.increment(-amount)},
            SetOptions(merge: true));
      });

      batch.update(logDoc.reference,
          {'reverted': true, 'revertedAt': FieldValue.serverTimestamp()});

      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Operation successfully undone!"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Paper Money")),
      body: SafeArea(child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: "Enter Amount"),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed:
                      _isProcessing ? null : () => _addPaperMoney(context),
                  child: const Text("CONFIRM & ADD"),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Recent Operations",
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: schoolCollection('bulk_fee_operations')
                  .where('field', isEqualTo: 'paperMoney')
                  .orderBy('timestamp', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                // An error came from Firestore (e.g. missing composite index)
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        "Error loading operations:\n${snapshot.error}",
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData) {
                  return const Center(
                      child: Text("No operations yet.",
                          style: TextStyle(color: Colors.grey)));
                }
                var docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                      child: Text("No operations yet.",
                          style: TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    bool reverted = data['reverted'] ?? false;
                    double totalAmount = (data['totalAmount'] ?? 0).toDouble();
                    int totalStudents = data['totalStudents'] ?? 0;
                    String dateStr = "N/A";
                    if (data['timestamp'] != null) {
                      dateStr = DateFormat('dd-MM-yyyy HH:mm')
                          .format((data['timestamp'] as Timestamp).toDate());
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: Icon(
                          reverted ? Icons.undo : Icons.attach_money,
                          color: reverted ? Colors.grey : Colors.teal,
                        ),
                        title: Text(
                            "Rs. ${totalAmount.toStringAsFixed(0)} across $totalStudents students"),
                        subtitle: Text(
                            "$dateStr${reverted ? '  •  Reverted' : ''}"),
                        trailing: reverted
                            ? const Text("Reverted",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold))
                            : TextButton(
                                onPressed: () => _undoOperation(context, doc),
                                child: const Text("Undo",
                                    style: TextStyle(color: Colors.red)),
                              ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      )),
    );
  }
}
