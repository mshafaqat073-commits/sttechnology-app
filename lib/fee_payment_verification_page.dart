import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

/// Admin uses this page to verify parents' online-submitted fee payments
/// (Easypaisa / UBL Bank). On Approve:
///  - The 'fieldBreakdown' the parent submitted (e.g. Books: 500,
///    Monthly Fee: 4000) is subtracted from those fee_structures fields
///    (exactly like pay_fee_page.dart), and 'duesPaid' is subtracted
///    from the student's 'dues' field.
///  - A record with exactly the same schema that admin's manual
///    PayFeePage creates (paidBreakdown, remainingAfterPayment,
///    duesPaid, totalAtPayment) is created in fee_history — just with
///    source:'online' and paymentMethod added too. Because of this,
///    history_page.dart's (and parent_fee_history_page.dart's) PDF,
///    Fee Breakdown, and long-press Delete & Restore all work exactly
///    the same for these online payments as they do for manual
///    payments.
/// On Reject, only the status becomes 'rejected' — dues are unaffected.
class FeePaymentVerificationPage extends StatefulWidget {
  const FeePaymentVerificationPage({super.key});

  @override
  State<FeePaymentVerificationPage> createState() =>
      _FeePaymentVerificationPageState();
}

class _FeePaymentVerificationPageState extends State<FeePaymentVerificationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // These keys exist in the fee_structures document but are not actual
  // fee amounts (they're meta / timestamps) — never include them in the
  // fee list or total. (Same as pay_fee_page.dart's admin side.)
  static const Set<String> _nonFeeKeys = {
    'studentId',
    'name',
    'fName',
    'class',
    'section',
    'updatedAt',
    'docId',
  };

  static const List<String> _tabStatuses = ['pending', 'approved', 'rejected'];

  // Create the streams for all three tabs once. Previously _list() was
  // called from inside build(), and a full setState() ran on every tab
  // switch (for the tooltip update), which recreated (and reconnected
  // to Firestore) all three streams every time.
  late final Map<String, Stream<QuerySnapshot>> _statusStreams = {
    for (final status in _tabStatuses)
      status: schoolCollection('fee_payments')
          .where('status', isEqualTo: status)
          .snapshots(),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _approve(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final studentId = data['studentId'];
    final double amount =
        double.tryParse(data['amount']?.toString() ?? '0') ?? 0;

    // The amount the parent submitted against each fee field (comes
    // as 'fieldBreakdown' + 'duesPaid' from pay_fee_online_page.dart).
    // Older pending records (from before this schema) won't have these
    // fields — fallback for those: put the whole amount toward previous
    // dues (as it worked before), so approving old pending records
    // doesn't crash.
    final bool hasBreakdown = data.containsKey('fieldBreakdown');
    final Map<String, dynamic> submittedBreakdown = hasBreakdown
        ? Map<String, dynamic>.from(data['fieldBreakdown'] ?? {})
        : {};
    final double submittedDuesPaid = hasBreakdown
        ? (double.tryParse(data['duesPaid']?.toString() ?? '0') ?? 0)
        : amount;

    final studentRef =
        schoolCollection('students').doc(studentId);
    final feeRef =
        schoolCollection('fee_structures').doc(studentId);
    // Reference for the new fee_history doc — history pages listen to
    // this collection, so an entry must be created here as soon as it's
    // approved, otherwise it won't show up in the payment History.
    final historyRef =
        schoolCollection('fee_history').doc();

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final studentSnap = await txn.get(studentRef);
        final feeSnap = await txn.get(feeRef);

        double currentDues = 0;
        String fName = '';
        if (studentSnap.exists) {
          final sData = studentSnap.data() as Map<String, dynamic>;
          currentDues = double.tryParse(sData['dues']?.toString() ?? '0') ?? 0;
          fName = sData['fName'] ?? '';
        }

        Map<String, dynamic> feeData =
            feeSnap.exists ? (feeSnap.data() as Map<String, dynamic>) : {};
        List<String> fieldKeys =
            feeData.keys.where((f) => !_nonFeeKeys.contains(f)).toList();

        // Grand total (fee fields + previous dues) — same as
        // pay_fee_page.dart's _grandTotal, so "Remaining Dues (at
        // that time)" is calculated correctly in history.
        double totalFee = 0;
        for (var f in fieldKeys) {
          totalFee += double.tryParse(feeData[f]?.toString() ?? '0') ?? 0;
        }
        double grandTotal = totalFee + currentDues;

        // Subtract whatever was submitted from each field to get the
        // remaining amount left in that field — exactly like
        // pay_fee_page.dart's _submitFee. The submitted amount is never
        // applied beyond a field's due (safety).
        Map<String, double> fieldRemaining = {};
        Map<String, double> paidBreakdown = {};
        for (var f in fieldKeys) {
          double due = double.tryParse(feeData[f]?.toString() ?? '0') ?? 0;
          double submitted =
              double.tryParse(submittedBreakdown[f]?.toString() ?? '0') ?? 0;
          double applied = submitted.clamp(0, due);
          fieldRemaining[f] = due - applied;
          paidBreakdown[f] = applied;
        }

        double duesApplied = submittedDuesPaid.clamp(0, currentDues);
        double duesRemaining = currentDues - duesApplied;

        if (feeSnap.exists && fieldKeys.isNotEmpty) {
          txn.update(feeRef, {for (var f in fieldKeys) f: fieldRemaining[f]});
        }
        txn.update(studentRef, {'dues': duesRemaining});
        txn.update(doc.reference, {
          'status': 'approved',
          'reviewedAt': FieldValue.serverTimestamp(),
        });

        // Entry for the history pages (admin + parent) — exactly the
        // same schema as pay_fee_page.dart's _submitFee, so Fee
        // Breakdown, PDF receipt, and Delete & Restore all work the
        // same way as they do for manual payments.
        txn.set(historyRef, {
          'studentId': studentId,
          'name': data['studentName'] ?? '',
          'fName': fName,
          'class': data['class'] ?? '',
          'amountPaid': amount,
          'discount': 0,
          'totalAtPayment': grandTotal,
          'date': FieldValue.serverTimestamp(),
          'paidBreakdown': paidBreakdown,
          'duesPaid': duesApplied,
          'remainingAfterPayment': {
            ...fieldRemaining,
            'dues': duesRemaining,
          },
          'source': 'online',
          'paymentMethod': data['method'] ?? '',
          'transactionId': data['transactionId'] ?? '',
        });
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Payment approved & dues updated.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  // Deletes all fee_payments entries in the currently selected tab
  // (Pending / Approved / Rejected) — shows a confirm dialog first
  // because these records can't be recovered (especially since they're
  // proof of approved payments). This is only visible to admin (it was
  // previously on the parent-facing pay_fee_online_page.dart by
  // mistake).
  Future<void> _clearPaymentHistory() async {
    final status = _tabStatuses[_tabController.index];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete '${status.toUpperCase()}' history?"),
        content: Text(
            "All entries in this tab ('${status.toUpperCase()}') will be "
            "permanently deleted. This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete All"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final snapshot = await schoolCollection('fee_payments')
          .where('status', isEqualTo: status)
          .get();

      if (snapshot.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No history found.")));
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payment history cleared.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _reject(DocumentSnapshot doc) async {
    await doc.reference.update({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Payment rejected.")));
    }
  }

  Widget _list(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _statusStreams[status],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No record found."));
        }
        final docs = snapshot.data!.docs;

        // Client-side sorting so newer records appear first (without needing an index)
        docs.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['submittedAt'];
          final bTime = (b.data() as Map<String, dynamic>)['submittedAt'];
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final name = data['studentName'] ?? '';
            final className = data['class'] ?? '';
            final section = (data['section'] ?? '').toString();
            final amount = data['amount']?.toString() ?? '0';
            final method = data['method'] ?? '';
            final trx = data['transactionId'] ?? '';
            final st = (data['status'] ?? 'pending').toString();
            final Map<String, dynamic> fieldBreakdown =
                data['fieldBreakdown'] != null
                    ? Map<String, dynamic>.from(data['fieldBreakdown'])
                    : {};
            final double duesPaid =
                double.tryParse(data['duesPaid']?.toString() ?? '0') ?? 0;

            String breakdownText = [
              ...fieldBreakdown.entries
                  .where((e) => (double.tryParse(e.value.toString()) ?? 0) > 0)
                  .map((e) => "${e.key}: Rs. ${e.value}"),
              if (duesPaid > 0)
                "Previous Dues: Rs. ${duesPaid.toStringAsFixed(0)}",
            ].join(', ');

            Color color = st == 'approved'
                ? Colors.green
                : st == 'rejected'
                    ? Colors.red
                    : Colors.orange;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              "$name  (Class $className${section.isNotEmpty ? ' - $section' : ''})",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Chip(
                          label: Text(st.toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
                          backgroundColor: color,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text("Amount: Rs. $amount   •   Method: $method"),
                    Text("Trx ID: $trx"),
                    if (breakdownText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(breakdownText,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700])),
                    ],
                    if (st == 'pending') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _reject(doc),
                              icon: const Icon(Icons.close, color: Colors.red),
                              label: const Text("Reject",
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _approve(doc),
                              icon: const Icon(Icons.check),
                              label: const Text("Approve"),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[700],
                                  foregroundColor: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Online Fee Payments"),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(
            onPressed: _clearPaymentHistory,
            icon: const Icon(Icons.delete_outline),
            tooltip: "Clear ${_tabStatuses[_tabController.index]} history",
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color.fromRGBO(255, 255, 0, 1),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: "Pending"),
            Tab(text: "Approved"),
            Tab(text: "Rejected"),
          ],
        ),
      ),
      body: SafeArea(child: TabBarView(
        controller: _tabController,
        children: [
          _list('pending'),
          _list('approved'),
          _list('rejected'),
        ],
      )),
    );
  }
}
