import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'subscription_gate.dart';

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({super.key});
  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _nameController = TextEditingController();
  final _totalController = TextEditingController();
  final _paidController = TextEditingController();
  final _descController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  double _remaining = 0.0;

  // "Other" (free-form expense) or "Staff Salary" (auto-fills the amount
  // from that staff member's salary set on the Add/Edit Staff page).
  String _expenseType = 'Other';
  List<Map<String, dynamic>> _staffList = [];
  String? _selectedStaffId;
  bool _loadingStaff = false;

  Future<void> _loadStaffList() async {
    if (_staffList.isNotEmpty || _loadingStaff) return;
    setState(() => _loadingStaff = true);
    final snap = await schoolCollection('staff').get();
    setState(() {
      _staffList = snap.docs
          .map((d) => {
                'id': d.id,
                'name': d.data()['name']?.toString() ?? '',
                'salary': d.data()['salary']?.toString() ?? '',
              })
          .toList();
      _loadingStaff = false;
    });
  }

  /// Called when a staff member is picked under "Staff Salary" — pulls in
  /// that staff member's salary (set on the Add/Edit Staff page) instead
  /// of it being typed in again by hand.
  void _onStaffSelected(String? staffId) {
    setState(() {
      _selectedStaffId = staffId;
      if (staffId == null) return;
      final staff = _staffList.firstWhere((s) => s['id'] == staffId);
      _nameController.text = "Salary - ${staff['name']}";
      _totalController.text = staff['salary'] ?? '';
      _calculateRemaining();
    });
  }

  void _calculateRemaining() {
    double total = double.tryParse(_totalController.text) ?? 0;
    double paid = double.tryParse(_paidController.text) ?? 0;
    setState(() => _remaining = total - paid);
  }

  Future<void> _submitExpense() async {
    if (_nameController.text.isEmpty) return;
    if (_isSaving) return;
    if (!await SubscriptionGuard.ensureActive(context)) return;
    setState(() => _isSaving = true);
    try {
      final staff = _selectedStaffId == null
          ? null
          : _staffList.firstWhere((s) => s['id'] == _selectedStaffId);
      await schoolCollection('expenses').add({
        'name': _nameController.text,
        'total': double.tryParse(_totalController.text) ?? 0,
        'paid': double.tryParse(_paidController.text) ?? 0,
        'remaining': _remaining,
        'description': _descController.text,
        'date': Timestamp.fromDate(_selectedDate),
        'expenseType': _expenseType,
        'staffId': _expenseType == 'Staff Salary' ? _selectedStaffId : null,
        'staffName': _expenseType == 'Staff Salary' ? (staff?['name']) : null,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _isSaving = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Expense")),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: "Expense Type"),
                  initialValue: _expenseType,
                  items: const [
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                    DropdownMenuItem(
                        value: 'Staff Salary', child: Text('Staff Salary')),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _expenseType = v ?? 'Other';
                      _selectedStaffId = null;
                    });
                    if (_expenseType == 'Staff Salary') _loadStaffList();
                  },
                ),
                if (_expenseType == 'Staff Salary') ...[
                  const SizedBox(height: 10),
                  _loadingStaff
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : DropdownButtonFormField<String>(
                          decoration:
                              const InputDecoration(labelText: "Select Staff"),
                          initialValue: _selectedStaffId,
                          items: _staffList
                              .map((s) => DropdownMenuItem(
                                  value: s['id'] as String,
                                  child: Text(s['name'] as String)))
                              .toList(),
                          onChanged: _onStaffSelected,
                        ),
                ],
                const SizedBox(height: 10),
                TextField(
                    controller: _nameController,
                    decoration:
                        const InputDecoration(labelText: "Expense Name")),
                TextField(
                    controller: _totalController,
                    decoration:
                        const InputDecoration(labelText: "Total Amount"),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _calculateRemaining()),
                TextField(
                    controller: _paidController,
                    decoration: const InputDecoration(labelText: "Paid Amount"),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _calculateRemaining()),
                TextField(
                    controller: _descController,
                    decoration:
                        const InputDecoration(labelText: "Description")),
                ListTile(
                    title: Text(
                        "Date: ${DateFormat('dd-MM-yyyy').format(_selectedDate)}"),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2025),
                          lastDate: DateTime(2030));
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    }),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSaving ? null : _submitExpense,
                  child: _isSaving
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text("Processing..."),
                          ],
                        )
                      : const Text("Save Expense"),
                ),
              ]))),
    );
  }
}
