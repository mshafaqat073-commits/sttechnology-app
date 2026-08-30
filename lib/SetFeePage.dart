import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

class SetFeePage extends StatefulWidget {
  final String docId;
  final String studentName;
  const SetFeePage({super.key, required this.docId, required this.studentName});

  @override
  State<SetFeePage> createState() => _SetFeePageState();
}

class _SetFeePageState extends State<SetFeePage> {
  final _monthlyFee = TextEditingController();
  final _transportFee = TextEditingController();
  final _otherExpense = TextEditingController();

  Future<void> _saveFeeDetails() async {
    try {
      await schoolCollection('fee_structures')
          .doc(widget.docId)
          .set({
        'monthlyFee': double.tryParse(_monthlyFee.text) ?? 0,
        'transportFee': double.tryParse(_transportFee.text) ?? 0,
        'otherExpense': double.tryParse(_otherExpense.text) ?? 0,
      }, SetOptions(merge: true)); // This line is necessary

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Fee Structure Set Successfully!")));
        Navigator.pop(context);
      }
    } catch (e) {
      // If any error occurs, it will show up here
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Set Fee: ${widget.studentName}")),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
                controller: _monthlyFee,
                decoration: const InputDecoration(labelText: "Monthly Fee"),
                keyboardType: TextInputType.number),
            TextField(
                controller: _transportFee,
                decoration: const InputDecoration(labelText: "Transport Fee"),
                keyboardType: TextInputType.number),
            TextField(
                controller: _otherExpense,
                decoration: const InputDecoration(labelText: "Other Expenses"),
                keyboardType: TextInputType.number),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: _saveFeeDetails,
                child: const Text("SAVE FEE STRUCTURE"))
          ],
        ),
      )),
    );
  }
}
