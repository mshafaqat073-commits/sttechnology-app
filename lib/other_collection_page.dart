import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

class OtherCollectionPage extends StatefulWidget {
  const OtherCollectionPage({super.key});

  @override
  State<OtherCollectionPage> createState() => _OtherCollectionPageState();
}

class _OtherCollectionPageState extends State<OtherCollectionPage> {
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController =
      TextEditingController(); // For extra details (optional)

  bool _isSaving = false;

  // Save Income to 'other_incomes' collection
  Future<void> _submitIncome() async {
    String source = _sourceController.text.trim();
    double? enteredAmount = double.tryParse(_amountController.text.trim());

    if (source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Enter source of income!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (enteredAmount == null || enteredAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Enter correct amount!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Save the record into the 'other_incomes' collection
      await schoolCollection('other_incomes').add({
        'incomeSource': source,
        'description': _descriptionController.text.trim(),
        'amountPaid': enteredAmount,
        'date': FieldValue.serverTimestamp(),
        'dateString': DateFormat('dd-MM-yyyy').format(DateTime.now()),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Other income successfully saved!"),
              backgroundColor: Colors.green),
        );
        setState(() {
          _sourceController.clear();
          _amountController.clear();
          _descriptionController.clear();
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentDate = DateFormat('dd-MM-yyyy').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Other Income Collection"),
        backgroundColor: Colors.teal[800],
      ),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Date Display Card
              Card(
                color: Colors.teal.shade50,
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Current Date:",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(currentDate,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.teal)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Income Source Field
              TextField(
                controller: _sourceController,
                decoration: const InputDecoration(
                  labelText: "Income Source (e.g., Donation, Rent, Fund, Sale)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.source),
                ),
              ),
              const SizedBox(height: 16),

              // Description / Note Field (Optional)
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: "Description / Details (Optional)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 16),

              // Amount Field
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Amount",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 24),

              // Receive Payment Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[800]),
                  onPressed: _isSaving ? null : _submitIncome,
                  child: _isSaving
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text("Processing...",
                                style: TextStyle(color: Colors.white)),
                          ],
                        )
                      : const Text("SAVE INCOME",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}
