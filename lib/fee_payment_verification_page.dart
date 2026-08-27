import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

/// Admin ye page se parents ki online submit ki hui fee payments
/// (Easypaisa / UBL Bank) verify karta he. Approve karne par:
///  - Parent ne jo 'fieldBreakdown' submit ki thi (jaise Books: 500,
///    Monthly Fee: 4000) wo fee_structures ke un fields se minus hoti
///    he (bilkul pay_fee_page.dart ki tarah), aur 'duesPaid' student ke
///    'dues' field se minus hota he.
///  - fee_history mein bilkul wahi schema wala record banta he jo
///    admin ki manual PayFeePage banati he (paidBreakdown,
///    remainingAfterPayment, duesPaid, totalAtPayment) — bas sath mein
///    source:'online' aur paymentMethod bhi hote hain. Isi wajah se
///    history_page.dart (aur parent_fee_history_page.dart) ka PDF,
///    Fee Breakdown, aur long-press Delete & Restore in online
///    payments ke liye bhi bilkul waisa hi kaam karta he jaisa manual
///    payments ke liye karta he.
/// Reject karne par sirf status 'rejected' ho jata he, dues par koi
/// asar nahi parta.
class FeePaymentVerificationPage extends StatefulWidget {
  const FeePaymentVerificationPage({super.key});

  @override
  State<FeePaymentVerificationPage> createState() =>
      _FeePaymentVerificationPageState();
}

class _FeePaymentVerificationPageState extends State<FeePaymentVerificationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Ye keys fee_structures document mein hoti hain lekin actual fee
  // amount nahi hain (meta / timestamps hain) — inhe kabhi bhi fee
  // list ya total mein shamil nahi karna. (pay_fee_page.dart admin
  // side ki tarah hi.)
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

  // Teeno tabs ke streams ek dafa bana lete hain. Pehle _list() build()
  // ke andar se call hoti thi, aur tab switch par (tooltip update ke
  // liye) poora setState() chalta tha jo teeno streams ko dobara bana
  // (aur Firestore se dobara connect kar) deta tha.
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

    // Parent ne har fee field ke against jitni amount submit ki thi
    // (pay_fee_online_page.dart se 'fieldBreakdown' + 'duesPaid' aati
    // he). Purane (is schema se pehle ke) pending records mein ye
    // fields nahi hongi — un ke liye fallback: poori amount previous
    // dues mein le lo (jaisa pehle hota tha), taake purane pending
    // records approve karte waqt crash na ho.
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
    // Naya fee_history doc ke liye reference — history pages isi
    // collection ko sunte hain, isliye approve hote hi entry yahan
    // bhi banani zaroori he warna payment History mein nazar nahi aati.
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

        // Grand total (fee fields + previous dues) — jaisa
        // pay_fee_page.dart ka _grandTotal, taake "Remaining Dues (at
        // that time)" history mein sahi calculate ho.
        double totalFee = 0;
        for (var f in fieldKeys) {
          totalFee += double.tryParse(feeData[f]?.toString() ?? '0') ?? 0;
        }
        double grandTotal = totalFee + currentDues;

        // Har field mein se jitna submit hua utna minus karke baqi
        // field mein reh jane wali amount nikalna — bilkul
        // pay_fee_page.dart _submitFee ki tarah. Submitted amount
        // kabhi bhi field ki due se zyada apply nahi hoti (safety).
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

        // History pages (admin + parent) ke liye entry — bilkul
        // pay_fee_page.dart _submitFee jesa schema, taake Fee
        // Breakdown, PDF receipt, aur Delete & Restore sab isi tarah
        // kaam karein jaise manual payments ke liye karte hain.
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

  // Currently selected tab (Pending / Approved / Rejected) ki saari
  // fee_payments entries delete kar deta he — pehle confirm dialog
  // dikhata he kyunke ye records wapis nahi aa sakte (khaas kar
  // approved payments ka proof hote hain). Ye sirf admin ko dikhta
  // he (pehle parent-facing pay_fee_online_page.dart par tha, jo
  // galti se lag gaya tha).
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

        // Client-side sorting taake naye records pehle nazar aayein (bina index ke)
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
