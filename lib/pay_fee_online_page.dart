import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'school_context.dart';

/// Parent ye page se apni fee online (Easypaisa ya UBL Bank) jama
/// karwata he. Ab admin ki PayFeePage ki tarah har fee field (Monthly
/// Fee, Books, Uniform waghera) alag se dikhti he apni "Due" amount ke
/// sath, aur parent har field ke against jitni marzi amount likh sakta
/// he (jaise "Books: Due 1000, Paid 500") — poori ya partial, jo bhi
/// wo abhi submit karna chahta he. Total inhi fields ka jama ban ke
/// "Amount to Submit" mein show hota he.
///
/// Submit karne ke baad entry 'fee_payments' collection mein 'pending'
/// status ke sath jati he (sath hi 'fieldBreakdown' bhi save hoti he ke
/// kis field mein kitna diya) — jab tak admin (FeePaymentVerificationPage
/// se) usse Approve na kare tab tak dues automatically kam nahi hoti,
/// taake fake ya galat entries se dues na bigड़ें.
class PayFeeOnlinePage extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String className;
  final String section;
  final double currentDues;

  const PayFeeOnlinePage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.section,
    required this.currentDues,
  });

  @override
  State<PayFeeOnlinePage> createState() => _PayFeeOnlinePageState();
}

class _PayFeeOnlinePageState extends State<PayFeeOnlinePage> {
  // Note: pehle yahan developer ka apna Easypaisa/UBL account hardcoded
  // tha — ab har school SchoolContext.easypaisaNumber/ublIban (Settings >
  // "Online Payment Account" se set kiya hua) use karta hai, taake jab
  // ye app kisi bhi school/customer ko diya jaye to fee unke apne account
  // mein jaye, developer ke account mein nahi.

  // Ye keys fee_structures document mein hoti hain lekin actual fee amount
  // nahi hain (student info / timestamps hain) — inhe kabhi bhi fee list
  // ya total mein shamil nahi karna. (pay_fee_page.dart admin side ki
  // tarah hi.)
  static const Set<String> _nonFeeKeys = {
    'studentId',
    'name',
    'fName',
    'class',
    'section',
    'updatedAt',
    'docId',
  };

  // Ye default fields hain — inhi ki tarteeb pehle dikhai jayegi.
  static const List<String> _defaultFieldOrder = [
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

  final _formKey = GlobalKey<FormState>();
  final _trxController = TextEditingController();
  String _method = "Easypaisa";
  bool _submitting = false;

  // Har fee field ke liye alag "Paid" input — key = field name.
  final Map<String, TextEditingController> _paidControllers = {};
  final TextEditingController _duesPaidController =
      TextEditingController(text: '0');

  DocumentSnapshot? _feeDoc;
  bool _loadingFee = true;

  // Asal "Previous Dues" hamesha students/{studentId} ke 'dues' field se
  // seedha fetch ki jati hai — widget.currentDues (jo iss page ko bahar se
  // milta hai) par bharosa nahi karte, kyunke wo kabhi kabhi galat/duplicate
  // (jaise fee_structure fields ke sath dobara jama shuda) amount le kar
  // aa sakta he. Yehi tareeqa pay_fee_page.dart (admin) bhi use karta hai.
  double _actualPreviousDues = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _trxController.dispose();
    _duesPaidController.dispose();
    for (var c in _paidControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Do alag documents (fee_structures aur students) ek sath parallel
      // mangwate hain — pehle ye sequentially (ek ke baad ek) load hote
      // the, jo bila wajah 2 network round-trips ka time leta tha.
      final results = await Future.wait([
        schoolCollection('fee_structures').doc(widget.studentId).get(),
        schoolCollection('students').doc(widget.studentId).get(),
      ]);
      var feeSnapshot = results[0];
      var studentSnapshot = results[1];

      double dues = 0;
      if (studentSnapshot.exists) {
        var studentData = studentSnapshot.data() ?? {};
        dues = double.tryParse(studentData['dues']?.toString() ?? '0') ?? 0;
      }

      setState(() {
        _feeDoc = feeSnapshot;
        _actualPreviousDues = dues;
        _initPaidControllers();
        _loadingFee = false;
      });
    } catch (e) {
      setState(() => _loadingFee = false);
    }
  }

  // Har fee field ke liye "Paid" controller taiyar karta hai — default
  // poori due amount se bhara hota hai (jaisa admin side pe hota hai),
  // parent chahe to kam kar sakta he.
  void _initPaidControllers() {
    for (var c in _paidControllers.values) {
      c.dispose();
    }
    _paidControllers.clear();

    if (_feeDoc == null || !_feeDoc!.exists) return;
    var feeData = _feeDoc!.data() as Map<String, dynamic>? ?? {};

    for (var field in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      double due = double.tryParse(feeData[field]?.toString() ?? '0') ?? 0;
      _paidControllers[field] =
          TextEditingController(text: due > 0 ? _trim(due) : '0');
    }

    _duesPaidController.text =
        _actualPreviousDues > 0 ? _trim(_actualPreviousDues) : '0';
  }

  List<String> _orderedFeeFields(Map<String, dynamic> feeData) {
    List<String> known =
        _defaultFieldOrder.where((f) => feeData.containsKey(f)).toList();
    List<String> extra = feeData.keys
        .where(
            (f) => !_defaultFieldOrder.contains(f) && !_nonFeeKeys.contains(f))
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

  double _fieldDue(String field) {
    var feeData = _feeDoc?.data() as Map<String, dynamic>? ?? {};
    return double.tryParse(feeData[field]?.toString() ?? '0') ?? 0;
  }

  // Field ke against jitni amount pay ki ja rahi hai — kabhi bhi due se
  // zyada ya 0 se kam nahi ho sakti.
  double _paidFor(String field) {
    double due = _fieldDue(field);
    double input = double.tryParse(_paidControllers[field]?.text ?? '0') ?? 0;
    return input.clamp(0, due);
  }

  double _duesPaidApplied() {
    double input = double.tryParse(_duesPaidController.text) ?? 0;
    return input.clamp(0, _actualPreviousDues);
  }

  List<String> get _feeFieldKeys {
    var feeData = _feeDoc?.data() as Map<String, dynamic>? ?? {};
    return feeData.keys.where((f) => !_nonFeeKeys.contains(f)).toList();
  }

  // Sab fields ka jama + previous dues jo abhi submit ki ja rahi hai.
  double get _totalToPay {
    double total = _feeFieldKeys.fold(0.0, (sum, f) => sum + _paidFor(f));
    total += _duesPaidApplied();
    return total;
  }

  void _payFullAmount() {
    if (_feeDoc == null) return;
    setState(() {
      for (var f in _feeFieldKeys) {
        _paidControllers[f]!.text = _trim(_fieldDue(f));
      }
      _duesPaidController.text =
          _actualPreviousDues > 0 ? _trim(_actualPreviousDues) : '0';
    });
  }

  void _clearAllPayments() {
    setState(() {
      for (var c in _paidControllers.values) {
        c.text = '0';
      }
      _duesPaidController.text = '0';
    });
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("$label copy ")));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_totalToPay <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please enter an amount in at least one field")));
      return;
    }

    setState(() => _submitting = true);
    try {
      await schoolCollection('fee_payments').add({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'class': widget.className,
        'section': widget.section,
        'amount': _totalToPay,
        // Har field ke against parent ne kitni amount submit ki — admin
        // isi se verify karke wapis fee_structures/dues mein munha
        // karega (pay_fee_page.dart ki tarah).
        'fieldBreakdown': {for (var f in _feeFieldKeys) f: _paidFor(f)},
        'duesPaid': _duesPaidApplied(),
        'method': _method,
        'transactionId': _trxController.text.trim(),
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'note': '',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Payment submited status paid after admin approvel.")));
      _trxController.clear();
      setState(() {
        _initPaidControllers();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _accountCard({
    required IconData icon,
    required Color color,
    required String title,
    required String number,
    required String accountName,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(number, style: const TextStyle(fontSize: 15)),
                  Text(accountName,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: "Copy",
              onPressed: () => _copy(number, title),
            ),
          ],
        ),
      ),
    );
  }

  // Ek fee field (ya previous dues) ke liye row: label, due amount, aur
  // editable "amount submitting" box — pay_fee_page.dart ke
  // _feeFieldRow jesa hi.
  Widget _feeFieldRow(String? field, {bool isDuesRow = false}) {
    final double due = isDuesRow ? _actualPreviousDues : _fieldDue(field!);
    final TextEditingController controller =
        isDuesRow ? _duesPaidController : _paidControllers[field!]!;
    final String label =
        isDuesRow ? "Previous Dues" : _formatFieldLabel(field!);

    if (!isDuesRow && due <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              child: Text("Due: ${due.toStringAsFixed(0)}",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pay Fee Online"),
        backgroundColor: Colors.green[700],
      ),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.red[50],
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.currentDues > 0
                          ? "${widget.studentName} Current Dues: Rs. ${widget.currentDues.toStringAsFixed(0)}"
                          : "${widget.studentName} no dues ",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text("Amount submit on this account:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (!SchoolContext.hasPaymentAccountSet)
            Card(
              color: Colors.orange[50],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "School ne abhi apna payment account set nahi "
                        "kiya — admin se rabta karein (Settings > Online "
                        "Payment Account).",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (SchoolContext.easypaisaNumber != null)
              _accountCard(
                icon: Icons.phone_android,
                color: Colors.green,
                title: "Easypaisa",
                number: SchoolContext.easypaisaNumber!,
                accountName: SchoolContext.easypaisaAccountName ?? '',
              ),
            if (SchoolContext.easypaisaNumber != null)
              const SizedBox(height: 10),
            if (SchoolContext.ublIban != null)
              _accountCard(
                icon: Icons.account_balance,
                color: Colors.indigo,
                title: "UBL Bank",
                number: SchoolContext.ublIban!,
                accountName: SchoolContext.ublAccountName ?? '',
              ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Text("Select which fee heads you're paying:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            "The 'Due' amount for each field is shown — you can pay the "
            "full amount or only part of it (e.g. Books: Due 1000, "
            "you can enter 500).",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          if (_loadingFee)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_feeDoc == null || !_feeDoc!.exists)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                  "Fee structure has not been set yet — please contact the admin."),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _payFullAmount,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text("Pay Full"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearAllPayments,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text("Clear All"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: const [
                Expanded(
                    flex: 3,
                    child: Text("Fee Head",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 2,
                    child: Text("Due",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 3,
                    child: Text("Amount Now",
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            const Divider(),
            ..._orderedFeeFields(_feeDoc!.data() as Map<String, dynamic>? ?? {})
                .map((f) => _feeFieldRow(f)),
            if (_actualPreviousDues > 0) ...[
              const Divider(thickness: 2),
              _feeFieldRow(null, isDuesRow: true),
            ],
            const Divider(thickness: 2),
            Text("Amount to Submit: Rs. ${_totalToPay.toStringAsFixed(0)}",
                style: const TextStyle(
                    fontSize: 18,
                    color: Colors.green,
                    fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Text("Fill details after fee submit:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: "Payment Method",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: "Easypaisa", child: Text("Easypaisa")),
                    DropdownMenuItem(
                        value: "UBL Bank", child: Text("UBL Bank")),
                  ],
                  onChanged: (v) => setState(() => _method = v ?? "Easypaisa"),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _trxController,
                  decoration: const InputDecoration(
                    labelText: "Transaction ID / Reference No.",
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? "Fill Transaction ID"
                      : null,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    label: Text(_submitting
                        ? "Submitting..."
                        : "Submit for Verification"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text("Payment History",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: schoolCollection('fee_payments')
                .where('studentId', isEqualTo: widget.studentId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text("No payment submited."),
                );
              }
              final docs = snapshot.data!.docs;

              // Client-side sorting taake naye records pehle nazar aayein (bina index ke)
              docs.sort((a, b) {
                final aTime = (a.data() as Map<String, dynamic>)['submittedAt'];
                final bTime = (b.data() as Map<String, dynamic>)['submittedAt'];
                if (aTime == null || bTime == null) return 0;
                return bTime.compareTo(aTime);
              });

              return Column(
                children: docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final status = (data['status'] ?? 'pending').toString();
                  final amount = data['amount']?.toString() ?? '0';
                  final method = data['method'] ?? '';
                  final trx = data['transactionId'] ?? '';
                  final Map<String, dynamic> fieldBreakdown =
                      data['fieldBreakdown'] != null
                          ? Map<String, dynamic>.from(data['fieldBreakdown'])
                          : {};

                  Color statusColor;
                  String statusLabel;
                  switch (status) {
                    case 'approved':
                      statusColor = Colors.green;
                      statusLabel = "Paid";
                      break;
                    case 'rejected':
                      statusColor = Colors.red;
                      statusLabel = "Rejected";
                      break;
                    default:
                      statusColor = Colors.orange;
                      statusLabel = "Pending";
                  }

                  String breakdownText = fieldBreakdown.entries
                      .where(
                          (e) => (double.tryParse(e.value.toString()) ?? 0) > 0)
                      .map((e) => "${_formatFieldLabel(e.key)}: Rs. ${e.value}")
                      .join(', ');

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(Icons.receipt_long, color: statusColor),
                      title: Text("Rs. $amount  •  $method"),
                      subtitle: Text(breakdownText.isNotEmpty
                          ? "Trx ID: $trx\n$breakdownText"
                          : "Trx ID: $trx"),
                      isThreeLine: breakdownText.isNotEmpty,
                      trailing: Chip(
                        label: Text(statusLabel,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                        backgroundColor: statusColor,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      )),
    );
  }
}
