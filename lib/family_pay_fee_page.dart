import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'family_fee_receipt_page.dart';
import 'subscription_gate.dart';

// These keys exist in the fee_structures document but aren't actual fee
// amounts — never include them in the fee list/total.
const Set<String> _nonFeeKeys = {
  'studentId',
  'name',
  'fName',
  'class',
  'section',
  'updatedAt',
  'docId',
};

const List<String> _defaultFieldOrder = [
  'monthlyFee',
  'admissionFee',
  'books',
  'notebooks',
  'diary',
  'file',
  'stationary',
  'paperMoney',
  'uniform',
  'other',
];

List<String> _orderedFeeFields(Map<String, dynamic> feeData) {
  List<String> known =
      _defaultFieldOrder.where((f) => feeData.containsKey(f)).toList();
  List<String> extra = feeData.keys
      .where((f) => !_defaultFieldOrder.contains(f) && !_nonFeeKeys.contains(f))
      .toList()
    ..sort();
  return [...known, ...extra];
}

String _formatFieldLabel(String key) {
  if (key.isEmpty) return key;
  String spaced =
      key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Full payment state for one family member (their own fee doc + a
/// "Paid Now" controller for each field).
class _MemberEntry {
  final QueryDocumentSnapshot studentDoc;
  DocumentSnapshot? feeDoc;
  final Map<String, TextEditingController> paidControllers = {};
  final TextEditingController duesPaidController = TextEditingController();
  bool expanded = true;

  _MemberEntry(this.studentDoc);

  Map<String, dynamic> get feeData =>
      (feeDoc?.data() as Map<String, dynamic>?) ?? {};

  double get previousDues {
    final data = studentDoc.data() as Map<String, dynamic>;
    return double.tryParse(data['dues']?.toString() ?? '0') ?? 0;
  }

  double fieldDue(String field) =>
      double.tryParse(feeData[field]?.toString() ?? '0') ?? 0;

  double paidFor(String field) {
    final due = fieldDue(field);
    final input = double.tryParse(paidControllers[field]?.text ?? '0') ?? 0;
    return input.clamp(0, due);
  }

  double get duesPaidApplied {
    final due = previousDues;
    final input = double.tryParse(duesPaidController.text) ?? 0;
    return input.clamp(0, due);
  }

  double get totalDue {
    double total = previousDues;
    for (var f in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      total += fieldDue(f);
    }
    return total;
  }

  double get totalPaidNow {
    double total = duesPaidApplied;
    for (var f in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      total += paidFor(f);
    }
    return total;
  }

  void initControllers() {
    for (var c in paidControllers.values) {
      c.dispose();
    }
    paidControllers.clear();
    for (var field in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      final due = fieldDue(field);
      paidControllers[field] =
          TextEditingController(text: due > 0 ? _trim(due) : '0');
    }
    final prevDues = previousDues;
    duesPaidController.text = prevDues > 0 ? _trim(prevDues) : '0';
  }

  void payFull() {
    for (var field in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      paidControllers[field]!.text = _trim(fieldDue(field));
    }
    final prevDues = previousDues;
    duesPaidController.text = prevDues > 0 ? _trim(prevDues) : '0';
  }

  void clearAll() {
    for (var c in paidControllers.values) {
      c.text = '0';
    }
    duesPaidController.text = '0';
  }

  void dispose() {
    for (var c in paidControllers.values) {
      c.dispose();
    }
    duesPaidController.dispose();
  }
}

/// Lets multiple siblings (same familyId) pay their fees together from
/// one place — at the end, everything is combined into one printed
/// slip (see family_fee_receipt_page.dart).
class FamilyPayFeePage extends StatefulWidget {
  final List<QueryDocumentSnapshot> students;
  const FamilyPayFeePage({super.key, required this.students});

  @override
  State<FamilyPayFeePage> createState() => _FamilyPayFeePageState();
}

class _FamilyPayFeePageState extends State<FamilyPayFeePage> {
  late List<_MemberEntry> _members;
  bool _loading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _members = widget.students.map((s) => _MemberEntry(s)).toList();
    _loadAll();
  }

  Future<void> _loadAll() async {
    for (var m in _members) {
      final feeSnap =
          await schoolCollection('fee_structures').doc(m.studentDoc.id).get();
      m.feeDoc = feeSnap;
      m.initControllers();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (var m in _members) {
      m.dispose();
    }
    super.dispose();
  }

  double get _grandTotalDue =>
      _members.fold(0.0, (sum, m) => sum + m.totalDue);

  double get _grandTotalPaidNow =>
      _members.fold(0.0, (sum, m) => sum + m.totalPaidNow);

  double get _grandRemaining => (_grandTotalDue - _grandTotalPaidNow)
      .clamp(0, double.infinity)
      .toDouble();

  Future<void> _submitAll() async {
    if (!await SubscriptionGuard.ensureActive(context)) return;
    setState(() => _isSaving = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final familyReceiptRef =
          schoolCollection('family_fee_receipts').doc();

      final List<Map<String, dynamic>> receiptChildren = [];

      for (var m in _members) {
        final feeData = m.feeData;
        final fieldKeys =
            feeData.keys.where((f) => !_nonFeeKeys.contains(f)).toList();

        final Map<String, double> fieldRemaining = {
          for (var f in fieldKeys) f: m.fieldDue(f) - m.paidFor(f)
        };
        final duesRemaining = m.previousDues - m.duesPaidApplied;

        batch.update(m.studentDoc.reference, {
          'dues': duesRemaining > 0 ? duesRemaining : 0,
          'lastPaymentDate': DateTime.now().toString(),
        });

        batch.update(m.feeDoc!.reference, {
          for (var f in fieldKeys)
            f: fieldRemaining[f]! > 0 ? fieldRemaining[f] : 0,
        });

        final historyRef = schoolCollection('fee_history').doc();
        final breakdown = {for (var f in fieldKeys) f: m.paidFor(f)};
        batch.set(historyRef, {
          'studentId': m.studentDoc.id,
          'name': (m.studentDoc.data() as Map<String, dynamic>)['name'],
          'fName': (m.studentDoc.data() as Map<String, dynamic>)['fName'],
          'class': (m.studentDoc.data() as Map<String, dynamic>)['class'],
          'amountPaid': m.totalPaidNow,
          'discount': 0,
          'totalAtPayment': m.totalDue,
          'date': FieldValue.serverTimestamp(),
          'paidBreakdown': breakdown,
          'duesPaid': m.duesPaidApplied,
          'remainingAfterPayment': {
            for (var f in fieldKeys) f: fieldRemaining[f],
            'dues': duesRemaining > 0 ? duesRemaining : 0,
          },
          // Part of this family payment — to reprint the combined slip
          // later, the full record can be found at
          // family_fee_receipts/{familyReceiptRef.id}.
          'familyReceiptId': familyReceiptRef.id,
        });

        receiptChildren.add({
          'name': (m.studentDoc.data() as Map<String, dynamic>)['name'] ?? '',
          'fName': (m.studentDoc.data() as Map<String, dynamic>)['fName'] ?? '',
          'class': (m.studentDoc.data() as Map<String, dynamic>)['class'] ?? '',
          'amountPaid': m.totalPaidNow,
          'duesRemaining': duesRemaining > 0 ? duesRemaining : 0,
          'breakdown': breakdown,
        });
      }

      batch.set(familyReceiptRef, {
        'date': FieldValue.serverTimestamp(),
        'totalPaid': _grandTotalPaidNow,
        'children': receiptChildren,
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Family Payment Saved Successfully!"),
          backgroundColor: Colors.green));

      final wantsReceipt = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Print Combined Slip?"),
          content: const Text(
              "Do you want to print one combined receipt for the whole family now?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("No")),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Print Slip")),
          ],
        ),
      );

      if (!mounted) return;
      if (wantsReceipt == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FamilyFeeReceiptPage(
              receiptNo: familyReceiptRef.id,
              paymentDate: DateTime.now(),
              children: receiptChildren,
              totalPaid: _grandTotalPaidNow,
            ),
          ),
        );
      }
      Navigator.pop(context, true);
    } catch (e) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pay Family Fee (Together)"),
        backgroundColor: Colors.teal[800],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (var m in _members) _memberCard(m),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: const Offset(0, -2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Family Grand Total",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(_grandTotalDue.toStringAsFixed(0),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Paying Now",
                              style: TextStyle(color: Colors.green)),
                          Text(_grandTotalPaidNow.toStringAsFixed(0),
                              style: const TextStyle(color: Colors.green)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Remaining After Payment",
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold)),
                          Text(_grandRemaining.toStringAsFixed(0),
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal[800]),
                          onPressed: _isSaving ? null : _submitAll,
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text("SUBMIT FAMILY PAYMENT",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _memberCard(_MemberEntry m) {
    final data = m.studentDoc.data() as Map<String, dynamic>;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(data['name'] ?? 'N/A',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            "Class: ${data['class'] ?? 'N/A'}  |  Due: ${m.totalDue.toStringAsFixed(0)}"),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(m.payFull),
                        icon: const Icon(Icons.done_all, size: 16),
                        label: const Text("Pay Full"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(m.clearAll),
                        icon: const Icon(Icons.clear_all, size: 16),
                        label: const Text("Clear"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ..._orderedFeeFields(m.feeData)
                    .map((f) => _fieldRow(m, f, isDuesRow: false)),
                _fieldRow(m, null, isDuesRow: true),
                const Divider(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(_MemberEntry m, String? field, {required bool isDuesRow}) {
    final due = isDuesRow ? m.previousDues : m.fieldDue(field!);
    final controller =
        isDuesRow ? m.duesPaidController : m.paidControllers[field!]!;
    final label = isDuesRow ? "Previous Dues" : _formatFieldLabel(field!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text(label,
                  style: TextStyle(
                      fontWeight:
                          isDuesRow ? FontWeight.bold : FontWeight.normal,
                      color: isDuesRow ? Colors.red[700] : Colors.black87))),
          Expanded(
              flex: 2,
              child: Text(due.toStringAsFixed(0),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
