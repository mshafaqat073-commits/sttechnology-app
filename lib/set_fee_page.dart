import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dashboard_page.dart';
import 'school_context.dart';
import 'subscription_gate.dart';

class SetFeePage extends StatefulWidget {
  final String docId;
  final String studentName;
  const SetFeePage({super.key, required this.docId, required this.studentName});

  @override
  State<SetFeePage> createState() => _SetFeePageState();
}

class _SetFeePageState extends State<SetFeePage> {
  final Map<String, TextEditingController> _controllers = {
    'monthlyFee': TextEditingController(),
    'admissionFee': TextEditingController(),
    'books': TextEditingController(),
    'notebooks': TextEditingController(),
    'diary': TextEditingController(),
    'file': TextEditingController(),
    'stationary': TextEditingController(),
    'paperMoney': TextEditingController(),
    'uniform': TextEditingController(),
    'other': TextEditingController(),
  };

  // Display label for each field (to show the correct name even after custom fields are added)
  final Map<String, String> _fieldLabels = {
    'monthlyFee': 'Monthly Fee',
    'admissionFee': 'Admission Fee',
    'books': 'Books',
    'notebooks': 'Notebooks',
    'diary': 'Diary',
    'file': 'File',
    'stationary': 'Stationary',
    'paperMoney': 'Paper Money',
    'uniform': 'Uniform',
    'other': 'Other',
  };

  // These are the default fields — they cannot be deleted
  late final Set<String> _defaultFieldKeys = _controllers.keys.toSet();

  // Converts the name typed by the user into a Firestore-friendly camelCase key
  String _labelToKey(String label) {
    final words = label.trim().split(RegExp(r'\s+'));
    String key = words.first.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    for (int i = 1; i < words.length; i++) {
      String w = words[i].replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      if (w.isNotEmpty) key += w[0].toUpperCase() + w.substring(1).toLowerCase();
    }
    return key.isEmpty ? 'field${DateTime.now().millisecondsSinceEpoch}' : key;
  }

  Future<void> _showAddFieldDialog() async {
    final TextEditingController newFieldController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Add New Fee Field"),
        content: TextField(
          controller: newFieldController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Field name (e.g. Exam Fee)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              String label = newFieldController.text.trim();
              if (label.isEmpty) {
                Navigator.pop(dialogContext);
                return;
              }
              String key = _labelToKey(label);
              if (_controllers.containsKey(key)) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("This field already exists!"), backgroundColor: Colors.red));
                return;
              }
              setState(() {
                _controllers[key] = TextEditingController();
                _fieldLabels[key] = label;
              });
              Navigator.pop(dialogContext);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  void _removeField(String key) {
    setState(() {
      _controllers[key]?.dispose();
      _controllers.remove(key);
      _fieldLabels.remove(key);
    });
  }

 bool _isSaving = false;

 Future<void> _saveFeeDetails() async {
  if (_isSaving) return;
  if (!await SubscriptionGuard.ensureActive(context)) return;
  setState(() => _isSaving = true);
  try {
    Map<String, dynamic> feeData = {};
    double monthlyFeeValue = 0.0;

    _controllers.forEach((key, controller) {
      double val = double.tryParse(controller.text) ?? 0.0;
      feeData[key] = val;
      if (key == 'monthlyFee') {
        monthlyFeeValue = val;
      }
    });

    var batch = FirebaseFirestore.instance.batch();

    // 1. Set the Fee Structure
    var feeDocRef = schoolCollection('fee_structures').doc(widget.docId);
    batch.set(feeDocRef, feeData, SetOptions(merge: true));

    // 2. Update monthlyFee in the Student collection
    var studentDocRef = schoolCollection('students').doc(widget.docId);
    batch.update(studentDocRef, {
      'monthlyFee': monthlyFeeValue, 
    });

    // CRITICAL: The batch must be committed!
    await batch.commit(); 
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fee Structure & Monthly Fee Saved!")));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardPage()));
    }
  } catch (e) {
    print("Error saving: $e");
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Fee Setup: ${widget.studentName}")),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ..._controllers.keys.map((key) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TextField(
                    controller: _controllers[key],
                    decoration: InputDecoration(
                      labelText: _fieldLabels[key] ?? (key[0].toUpperCase() + key.substring(1)),
                      suffixIcon: _defaultFieldKeys.contains(key)
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              tooltip: "Remove field",
                              onPressed: () => _removeField(key),
                            ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                )),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _showAddFieldDialog,
                icon: const Icon(Icons.add, color: Colors.teal),
                label: const Text("Add New Field", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
  onPressed: _isSaving ? null : _saveFeeDetails, // Click hone par disable ho jayega
  child: _isSaving 
      ? const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 20, 
              width: 20, 
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            ),
            SizedBox(width: 10),
            Text("Processing..."),
          ],
        )
      : const Text("SAVE FEE STRUCTURE"),
)
          ],
        ),
      )),
    );
  }
}