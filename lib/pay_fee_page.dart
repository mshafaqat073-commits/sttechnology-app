import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'fee_receipt_page.dart';
import 'family_pay_fee_page.dart';
import 'subscription_gate.dart';

class PayFeePage extends StatefulWidget {
  const PayFeePage({super.key});

  @override
  State<PayFeePage> createState() => _PayFeePageState();
}

class _PayFeePageState extends State<PayFeePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();

  // Har fee field (Books, Uniform, Monthly Fee, waghera) ke liye alag
  // "Paid" input — key = field name, value = us field ke against jitni
  // amount abhi pay ki ja rahi hai.
  final Map<String, TextEditingController> _paidControllers = {};

  // "Previous Dues" (student['dues']) ke against jitni amount pay ki ja
  // rahi hai, uska apna alag input.
  final TextEditingController _duesPaidController = TextEditingController();

  // Ye keys fee_structures document mein hoti hain lekin actual fee amount
  // nahi hain (student info / timestamps hain) — inhe kabhi bhi fee list
  // ya total mein shamil nahi karna.
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
  // Koi bhi naya custom field (set_fee_page se "+ Add New Field" se add kiya gaya)
  // automatically inke baad list ho jayega.
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

  // fee_structures document me jo bhi keys maujood hon unhe order karta hai:
  // pehle jaani-pehchani (default) fields, phir koi bhi naya/custom field.
  // Meta fields (name, class, waghera) hamesha exclude rehti hain.
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

  // camelCase field name ko readable label me convert karta hai
  // e.g. "monthlyFee" -> "Monthly Fee", "examFee" -> "Exam Fee"
  String _formatFieldLabel(String key) {
    if (key.isEmpty) return key;
    String spaced =
        key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  DocumentSnapshot? _studentDoc;
  DocumentSnapshot? _feeDoc;
  double _remainingDues = 0;
  double _grandTotal = 0;
  bool _isSaving = false;

  // Live search ke liye variables
  List<QueryDocumentSnapshot> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    _duesPaidController.dispose();
    for (var c in _paidControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Jaise hi user type karega, yeh function chalega
  Future<void> _onSearchChanged(String query) async {
    query = query.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      String queryLower = query.toLowerCase();

      // Firestore ki range query (isGreaterThanOrEqualTo/isLessThanOrEqualTo)
      // case-sensitive hoti hai, is liye sirf active students fetch karke
      // client-side pe case-insensitive "contains" match kiya ja raha hai —
      // isse ek hi letter type karne par bhi (chahe capital ho ya small)
      // student turant show ho jayega.
      var activeSnapshot = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();

      List<QueryDocumentSnapshot> results = activeSnapshot.docs.where((doc) {
        var data = doc.data();
        String name = (data['name'] ?? '').toString().toLowerCase();
        return name.contains(queryLower);
      }).toList();

      if (results.isEmpty) {
        results = activeSnapshot.docs.where((doc) {
          var data = doc.data();
          String familyId = (data['familyId'] ?? '').toString().toLowerCase();
          return familyId.contains(queryLower);
        }).toList();
      }

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint("Live Search Error: $e");
      setState(() => _isSearching = false);
    }
  }

  // Groups the current _searchResults by familyId — only returns
  // groups with 2 or more siblings (no need to show the family option
  // for results that are just a single student).
  Map<String, List<QueryDocumentSnapshot>> get _familyGroupsInResults {
    final Map<String, List<QueryDocumentSnapshot>> groups = {};
    for (var doc in _searchResults) {
      final data = doc.data() as Map<String, dynamic>;
      final familyId = (data['familyId'] ?? '').toString().trim();
      if (familyId.isEmpty) continue;
      groups.putIfAbsent(familyId, () => []).add(doc);
    }
    groups.removeWhere((key, docs) => docs.length < 2);
    return groups;
  }

  Future<void> _openFamilyPayment(List<QueryDocumentSnapshot> members) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyPayFeePage(students: members),
      ),
    );
    if (saved == true) {
      setState(() {
        _searchResults = [];
        _searchController.clear();
      });
    }
  }

  Future<void> _loadStudentData(QueryDocumentSnapshot student) async {
    var data = student.data() as Map<String, dynamic>;
    var feeSnapshot =
        await schoolCollection('fee_structures').doc(student.id).get();

    setState(() {
      _studentDoc = student;
      _feeDoc = feeSnapshot;
      _searchController.text = data['name'] ?? "";
      _searchResults = []; // List select hone ke baad gayab ho jaye gi
      _discountController.clear();
      _initPaidControllers();
      _calculateDues();
    });
  }

  // Har fee field aur previous dues ke liye "Paid" controller taiyar karta
  // hai — default poori due amount se bhara hota hai (yani agar staff koi
  // field edit na kare to wo pehle jaisa "full payment" hi rahega).
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

    double previousDues = _previousDuesAmount();
    _duesPaidController.text = previousDues > 0 ? _trim(previousDues) : '0';
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double _fieldDue(String field) {
    var feeData = _feeDoc?.data() as Map<String, dynamic>? ?? {};
    return double.tryParse(feeData[field]?.toString() ?? '0') ?? 0;
  }

  double _previousDuesAmount() {
    var studentData = _studentDoc?.data() as Map<String, dynamic>? ?? {};
    return double.tryParse(studentData['dues']?.toString() ?? '0') ?? 0;
  }

  // Field ke against jitni amount pay ki ja rahi hai — kabhi bhi due se
  // zyada ya 0 se kam nahi ho sakti.
  double _paidFor(String field) {
    double due = _fieldDue(field);
    double input = double.tryParse(_paidControllers[field]?.text ?? '0') ?? 0;
    return input.clamp(0, due);
  }

  double _duesPaidApplied() {
    double due = _previousDuesAmount();
    double input = double.tryParse(_duesPaidController.text) ?? 0;
    return input.clamp(0, due);
  }

  void _calculateDues() {
    if (_studentDoc == null || _feeDoc == null) return;

    var feeData = _feeDoc!.data() as Map<String, dynamic>? ?? {};

    double totalFee = 0;
    for (var f in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      totalFee += double.tryParse(feeData[f]?.toString() ?? '0') ?? 0;
    }

    setState(() {
      _grandTotal = totalFee + _previousDuesAmount();
    });
    _updateRemaining();
  }

  // Har field ka (due - paid) jama karke, discount minus karke live
  // "Remaining Dues" nikalta hai.
  void _updateRemaining([String? _]) {
    if (_feeDoc == null || _studentDoc == null) return;
    var feeData = _feeDoc!.data() as Map<String, dynamic>? ?? {};
    double discount = double.tryParse(_discountController.text) ?? 0;

    double totalRemaining = 0;
    for (var f in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      totalRemaining += (_fieldDue(f) - _paidFor(f));
    }
    totalRemaining += (_previousDuesAmount() - _duesPaidApplied());
    totalRemaining = (totalRemaining - discount).clamp(0, double.infinity);

    setState(() => _remainingDues = totalRemaining);
  }

  // Ek click mein sab fields + previous dues poori pay kar do (ikatha
  // payment) — jaisa pehle default behaviour tha.
  void _payFullAmount() {
    if (_feeDoc == null) return;
    var feeData = _feeDoc!.data() as Map<String, dynamic>? ?? {};
    setState(() {
      for (var f in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
        _paidControllers[f]!.text = _trim(_fieldDue(f));
      }
      double previousDues = _previousDuesAmount();
      _duesPaidController.text = previousDues > 0 ? _trim(previousDues) : '0';
    });
    _updateRemaining();
  }

  // Sab "Paid" boxes 0 kar do taake staff har field mein manually,
  // alag-alag partial amount likh sake.
  void _clearAllPayments() {
    setState(() {
      for (var c in _paidControllers.values) {
        c.text = '0';
      }
      _duesPaidController.text = '0';
    });
    _updateRemaining();
  }

  Future<void> _submitFee() async {
    if (_studentDoc == null || _feeDoc == null) return;
    if (!await SubscriptionGuard.ensureActive(context)) return;

    setState(() => _isSaving = true);

    try {
      var feeData = _feeDoc!.data() as Map<String, dynamic>? ?? {};
      double discount = double.tryParse(_discountController.text) ?? 0;
      List<String> fieldKeys =
          feeData.keys.where((f) => !_nonFeeKeys.contains(f)).toList();

      // Payment ke baad har field/dues mein kitni raqam baaki reh jayegi
      Map<String, double> fieldRemaining = {
        for (var f in fieldKeys) f: _fieldDue(f) - _paidFor(f)
      };
      double duesRemaining = _previousDuesAmount() - _duesPaidApplied();

      // Discount ko pehle Previous Dues se, phir baqi fields se (tarteeb
      // ke mutabiq) munha karte hain jab tak discount khatam na ho jaye.
      double leftoverDiscount = discount;
      if (leftoverDiscount > 0) {
        double applied = leftoverDiscount.clamp(0, duesRemaining);
        duesRemaining -= applied;
        leftoverDiscount -= applied;
      }
      if (leftoverDiscount > 0) {
        for (var f in fieldKeys) {
          if (leftoverDiscount <= 0) break;
          double applied = leftoverDiscount.clamp(0, fieldRemaining[f]!);
          fieldRemaining[f] = fieldRemaining[f]! - applied;
          leftoverDiscount -= applied;
        }
      }

      double totalCashPaid =
          fieldKeys.fold(0.0, (sum, f) => sum + _paidFor(f)) +
              _duesPaidApplied();

      var batch = FirebaseFirestore.instance.batch();

      batch.update(_studentDoc!.reference, {
        'dues': duesRemaining > 0 ? duesRemaining : 0,
        'lastPaymentDate': DateTime.now().toString(),
      });

      // Har field ab poori 0 nahi hoti — sirf jitna paid hua utna minus
      // hota hai, baqi amount usi field mein reh jati hai.
      batch.update(_feeDoc!.reference, {
        for (var f in fieldKeys)
          f: fieldRemaining[f]! > 0 ? fieldRemaining[f] : 0,
      });

      var historyRef = schoolCollection('fee_history').doc();
      batch.set(historyRef, {
        'studentId': _studentDoc!.id,
        'name': _studentDoc!['name'],
        'fName': _studentDoc!['fName'],
        'class': _studentDoc!['class'],
        'amountPaid': totalCashPaid,
        'discount': discount,
        'totalAtPayment': _grandTotal,
        'date': FieldValue.serverTimestamp(),
        // Is payment mein har field ke against kitna paid hua
        'paidBreakdown': {for (var f in fieldKeys) f: _paidFor(f)},
        'duesPaid': _duesPaidApplied(),
        // Payment ke baad har field/dues mein kitna baaki reh gaya
        'remainingAfterPayment': {
          for (var f in fieldKeys) f: fieldRemaining[f],
          'dues': duesRemaining > 0 ? duesRemaining : 0,
        },
      });

      await batch.commit();

      // Receipt print karne ke liye is payment ki poori tafseel save kar
      // lete hain — neeche setState() state reset kar deta he, is liye
      // ye values abhi (commit ke foran baad) nikalna zaroori he.
      final receiptStudentName = (_studentDoc!['name'] ?? '').toString();
      final receiptFatherName = (_studentDoc!['fName'] ?? '').toString();
      final receiptClass = (_studentDoc!['class'] ?? '').toString();
      final receiptSection =
          (_studentDoc!.data() as Map<String, dynamic>).containsKey('section')
              ? (_studentDoc!['section'] ?? '').toString()
              : '';
      final receiptBreakdown = {for (var f in fieldKeys) f: _paidFor(f)};
      final receiptDuesRemaining = duesRemaining > 0 ? duesRemaining : 0.0;
      final receiptPreviousDues = _previousDuesAmount();
      final receiptNo = historyRef.id;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Payment Saved Successfully!"),
            backgroundColor: Colors.green));
        setState(() {
          _studentDoc = null;
          _feeDoc = null;
          _searchController.clear();
          _discountController.clear();
          for (var c in _paidControllers.values) {
            c.dispose();
          }
          _paidControllers.clear();
          _duesPaidController.clear();
          _remainingDues = 0;
          _grandTotal = 0;
        });

        // Payment save hone ke baad receipt print karne ka option.
        final wantsReceipt = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Print Receipt?"),
            content: const Text(
                "Do you want to print the receipt for this payment now?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("No")),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Print Receipt")),
            ],
          ),
        );
        if (wantsReceipt == true && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FeeReceiptPage(
                receiptNo: receiptNo,
                studentName: receiptStudentName,
                fatherName: receiptFatherName,
                className: receiptClass,
                section: receiptSection,
                amountPaid: totalCashPaid,
                previousDues: receiptPreviousDues,
                duesRemaining: receiptDuesRemaining,
                paymentDate: DateTime.now(),
                feeBreakdown: receiptBreakdown,
              ),
            ),
          );
        }
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
  void initState() {
    super.initState();
    checkAndAutoAddMonthlyFee();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Fee Payment"), backgroundColor: Colors.teal[800]),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Search TextField aur uske neche live suggestions list
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: "Search by Name or Family ID",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged:
                    _onSearchChanged, // <-- Yeh har letter type hone par chalega
              ),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              // If the search results contain 2 or more siblings (same
              // familyId), show the option here to view them
              // separately or pay for the family together.
              if (!_isSearching && _familyGroupsInResults.isNotEmpty)
                ..._familyGroupsInResults.entries.map((entry) {
                  final members = entry.value;
                  final names = members
                      .map((d) =>
                          (d.data() as Map<String, dynamic>)['name'] ?? '')
                      .join(', ');
                  return Card(
                    margin: const EdgeInsets.only(top: 6),
                    color: Colors.teal[50],
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Family found (${members.length}): $names",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    // "View Separately" — just picking
                                    // any one student from the normal
                                    // list below runs the usual single
                                    // payment flow.
                                    setState(() {});
                                  },
                                  child: const Text("View Separately"),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal[800]),
                                  onPressed: () =>
                                      _openFamilyPayment(members),
                                  child: const Text(
                                    "Pay Together",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              if (_searchResults.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.2),
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      var data =
                          _searchResults[index].data() as Map<String, dynamic>;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person,
                            color: Colors.teal, size: 20),
                        title: Text(data['name'] ?? "No Name",
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            "Father: ${data['fName'] ?? 'N/A'} | Class: ${data['class'] ?? 'N/A'}"),
                        onTap: () {
                          _loadStudentData(_searchResults[index]);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (_studentDoc != null && _feeDoc != null)
            Expanded(
                child: SingleChildScrollView(
                    child: Column(children: [
              const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Student Details",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.teal))),
              _infoTile("Name", _studentDoc!['name'] ?? 'N/A'),
              _infoTile("Father Name", _studentDoc!['fName'] ?? 'N/A'),
              _infoTile("Class", _studentDoc!['class'] ?? 'N/A'),
              _infoTile("Date",
                  DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())),
              const Divider(thickness: 2),

              // Quick actions: pay everything at once, or clear
              // everything to fill amounts in manually one by one.
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
              const SizedBox(height: 12),

              // Header row for the fee table
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
                      child: Text("Paid Now",
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              const Divider(),

              ..._orderedFeeFields(
                      _feeDoc!.data() as Map<String, dynamic>? ?? {})
                  .map((f) => _feeFieldRow(f)),

              const Divider(thickness: 2),

              // Previous dues ka apna alag row
              _feeFieldRow(null, isDuesRow: true),

              const SizedBox(height: 10),
              TextField(
                  controller: _discountController,
                  keyboardType: TextInputType.number,
                  onChanged: _updateRemaining,
                  decoration: const InputDecoration(
                      labelText: "Discount", border: OutlineInputBorder())),
              const SizedBox(height: 90),
            ]))),
        ]),
      )),
      // Sticky bottom bar — Grand Total / Remaining Dues / Submit button
      // always stay visible on screen (no need to scroll all the way
      // down on smaller mobile screens to find the Submit button).
      bottomNavigationBar: (_studentDoc != null && _feeDoc != null)
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: const Offset(0, -2)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(thickness: 2, height: 8),
                    _infoTile("GRAND TOTAL", _grandTotal.toStringAsFixed(0)),
                    const SizedBox(height: 6),
                    Text(
                        "REMAINING DUES: ${_remainingDues.toStringAsFixed(0)}",
                        style: const TextStyle(
                            fontSize: 18,
                            color: Colors.red,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal[800]),
                        onPressed: _isSaving ? null : _submitFee,
                        child: _isSaving
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2)),
                                  SizedBox(width: 10),
                                  Text("Processing...",
                                      style: TextStyle(color: Colors.white)),
                                ],
                              )
                            : const Text("SUBMIT PAYMENT",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  // Ek fee field (ya previous dues) ke liye row banata hai: label, due
  // amount, aur editable "paid now" box.
  Widget _feeFieldRow(String? field, {bool isDuesRow = false}) {
    final double due = isDuesRow ? _previousDuesAmount() : _fieldDue(field!);
    final TextEditingController controller =
        isDuesRow ? _duesPaidController : _paidControllers[field!]!;
    final String label =
        isDuesRow ? "Previous Dues" : _formatFieldLabel(field!);

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
              child: Text(due.toStringAsFixed(0),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              onChanged: (_) => _updateRemaining(),
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

  Widget _infoTile(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold))
        ]),
      );

  Future<void> checkAndAutoAddMonthlyFee() async {
    final prefs = await SharedPreferences.getInstance();
    String currentMonthYear = DateFormat('MM-yyyy').format(DateTime.now());
    String lastUpdated = prefs.getString('last_fee_update') ?? '';

    if (DateTime.now().day == 1 && lastUpdated != currentMonthYear) {
      var students = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();
      var batch = FirebaseFirestore.instance.batch();

      // Har student ke fee_structures doc ko sequentially (await loop ke
      // andar) parhne ke bajaye, sab ek sath parallel mein parhte hain —
      // result/logic bilkul same rehta hai, sirf poora kaam ek sath hota
      // hai isliye bohat zyada students hone par bhi ye step fast rehta hai.
      var duesUpdates = await Future.wait(students.docs.map((doc) async {
        var feeDoc =
            await schoolCollection('fee_structures').doc(doc.id).get();
        double monthlyFee =
            double.tryParse(feeDoc.data()?['monthlyFee']?.toString() ?? '0') ??
                0;
        double currentDues =
            double.tryParse(doc['dues']?.toString() ?? '0') ?? 0;
        return MapEntry(doc.reference, currentDues + monthlyFee);
      }));

      for (var entry in duesUpdates) {
        batch.update(entry.key, {'dues': entry.value});
      }
      await batch.commit();
      await prefs.setString('last_fee_update', currentMonthYear);
    }
  }
}
