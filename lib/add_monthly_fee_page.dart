import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'subscription_gate.dart';

class AddMonthlyFeePage extends StatefulWidget {
  const AddMonthlyFeePage({super.key});

  @override
  State<AddMonthlyFeePage> createState() => _AddMonthlyFeePageState();
}

class _AddMonthlyFeePageState extends State<AddMonthlyFeePage> {
  bool _isProcessing = false;

  Future<void> _processMonthlyFee(BuildContext context) async {
    if (!await SubscriptionGuard.ensureActive(context)) return;
    setState(() => _isProcessing = true);

    // Loading Dialog dikhayein
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Active students ki list lein
      var students = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();

      if (students.docs.isEmpty) {
        if (context.mounted) Navigator.pop(context); // Dialog hatayein
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No active student found!")));
        setState(() => _isProcessing = false);
        return;
      }

      var batch = FirebaseFirestore.instance.batch();

      // Har student ko kitna amount add hua — ye map hi baad mein "Undo"
      // karne ke kaam aayega (kisay kitna wapis minus karna hai).
      Map<String, double> studentAmounts = {};

      for (var doc in students.docs) {
        // students table se monthlyFee ki value nikalna
        double studentFee =
            double.tryParse(doc.data()['monthlyFee']?.toString() ?? '0') ?? 0;

        if (studentFee > 0) {
          var feeRef = schoolCollection('fee_structures')
              .doc(doc.id);

          // FieldValue.increment ka istemal taake pehli fee mein nayi fee khud-ba-khud sum ho jaye
          batch.set(feeRef, {'monthlyFee': FieldValue.increment(studentFee)},
              SetOptions(merge: true) // Baaki fields ko mehfooz rakhne ke liye
              );

          studentAmounts[doc.id] = studentFee;
        }
      }

      // Is operation ka log save karein taake baad mein "Undo" kiya ja sake
      var logRef =
          schoolCollection('bulk_fee_operations').doc();
      batch.set(logRef, {
        'type': 'Monthly Fee',
        'field': 'monthlyFee',
        'studentAmounts': studentAmounts,
        'totalStudents': studentAmounts.length,
        'totalAmount': studentAmounts.values.fold(0.0, (a, b) => a + b),
        'timestamp': FieldValue.serverTimestamp(),
        'reverted': false,
      });

      await batch.commit();

      // Success par Dialog hatayein aur message dikhayein
      if (context.mounted) {
        Navigator.pop(context); // Dialog hatayein
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "Success: Monthly fee added & summed in all fee structures!")));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Dialog hatayein
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Ek pehle se kiye gaye "Add Monthly Fee" operation ko reverse karta hai —
  // har student se utni hi amount wapis minus kar deta hai jitni us waqt
  // add hui thi, aur log ko "reverted" mark kar deta hai.
  Future<void> _undoOperation(
      BuildContext context, DocumentSnapshot logDoc) async {
    var data = logDoc.data() as Map<String, dynamic>;
    int totalStudents = data['totalStudents'] ?? 0;
    double totalAmount = (data['totalAmount'] ?? 0).toDouble();

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Undo Monthly Fee?"),
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
        batch.set(feeRef, {'monthlyFee': FieldValue.increment(-amount)},
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
      appBar: AppBar(title: const Text("Add Monthly Fee Sum")),
      body: SafeArea(child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : () => _processMonthlyFee(context),
              icon: const Icon(Icons.calendar_month),
              label: const Text("ADD & SUM MONTHLY FEE FOR ALL"),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
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
                  .where('field', isEqualTo: 'monthlyFee')
                  .orderBy('timestamp', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                // Firestore se koi error aaya (jaise missing composite index)
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
                          reverted ? Icons.undo : Icons.calendar_month,
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
