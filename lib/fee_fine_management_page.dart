import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'notification_helper.dart';

/// For students whose fee is still unpaid past the due date, this adds a
/// fine into a dedicated `fine` field on the student's document (kept
/// separate from `dues`) — and sends the student a notification.
///
/// Rules: schools/{schoolId}/settings/fine_rules -> {fineAmount, dueDay, enabled}
/// Log:   schools/{schoolId}/fine_history/{autoId}
///
/// NOTE: This check runs when the "Apply Fines Now" button is pressed
/// (same pattern as this app's monthly-fee generation, which runs when
/// the admin opens the app — see pay_fee_page.dart's
/// checkAndAutoAddMonthlyFee). So the admin needs to press this button
/// once a month, after the due date. To make this run automatically every
/// day, a Cloud Functions Scheduler would need to be set up separately.
class FeeFineManagementPage extends StatefulWidget {
  const FeeFineManagementPage({super.key});

  @override
  State<FeeFineManagementPage> createState() => _FeeFineManagementPageState();
}

class _FeeFineManagementPageState extends State<FeeFineManagementPage> {
  final _amountController = TextEditingController();
  final _dueDayController = TextEditingController();
  bool _enabled = true;
  bool _forceReapply = false;
  bool _loading = true;
  bool _applying = false;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    try {
      final doc = await schoolCollection('settings').doc('fine_rules').get();
      final d = doc.data();
      _amountController.text = (d?['fineAmount'] ?? 100).toString();
      _dueDayController.text = (d?['dueDay'] ?? 10).toString();
      _enabled = d?['enabled'] ?? true;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveRules() async {
    await schoolCollection('settings').doc('fine_rules').set({
      'fineAmount': double.tryParse(_amountController.text) ?? 100,
      'dueDay': int.tryParse(_dueDayController.text) ?? 10,
      'enabled': _enabled,
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Fine rules saved."), backgroundColor: Colors.green));
    }
  }

  Future<void> _applyFinesNow() async {
    setState(() {
      _applying = true;
      _log = '';
    });

    final fineAmount = double.tryParse(_amountController.text) ?? 100;
    final dueDay = int.tryParse(_dueDayController.text) ?? 10;
    final now = DateTime.now();
    final currentMonthKey = DateFormat('MM-yyyy').format(now);

    if (now.day < dueDay) {
      setState(() {
        _applying = false;
        _log = "Day $dueDay hasn't arrived yet — no need to apply fines.";
      });
      return;
    }

    int fined = 0;
    try {
      // Fields that show up on fee_structures documents but aren't a fee
      // amount — these are excluded when summing pending amounts.
      // (Same exclusion list DefaultersPage.dart uses.)
      const Set<String> nonFeeKeys = {
        'studentId',
        'name',
        'fName',
        'class',
        'section',
        'updatedAt',
        'docId',
      };

      // Reads a possibly-numeric-or-string value as a double, or null if
      // it isn't a usable number.
      double? asAmount(dynamic value) {
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value);
        return null;
      }

      // As confirmed by DefaultersPage.dart: a fee_structures document's
      // ID is the SAME as the student's document ID — they are not
      // linked via a separate 'studentId' field. So this is keyed
      // directly by doc.id.
      final structuresSnap = await schoolCollection('fee_structures').get();
      final Map<String, double> structureDuesByStudent = {};
      final Map<String, String> lastFineMonthByStudent = {};
      for (var doc in structuresSnap.docs) {
        final data = doc.data();
        double sum = 0;
        data.forEach((key, value) {
          if (nonFeeKeys.contains(key)) return;
          sum += asAmount(value) ?? 0;
        });
        structureDuesByStudent[doc.id] = sum;
        // `fine` and `lastFineMonth` now live on the fee_structures doc
        // (not the student doc) — `fine` is a numeric field so it's
        // already included in `sum` above (an unpaid fine still counts
        // as pending), `lastFineMonth` is a string so it's naturally
        // skipped by the numeric sum.
        lastFineMonthByStudent[doc.id] =
            data['lastFineMonth']?.toString() ?? '';
      }

      final students = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      final List<Map<String, dynamic>> notifyList = [];
      // Per-student breakdown, shown in the log below so it's clear
      // exactly what value each student was checked against — instead of
      // just "not eligible" with no way to see why.
      final List<String> debugLines = [];

      for (var doc in students.docs) {
        final data = doc.data();

        // Pending amount = student's dedicated `dues` field (matches
        // DefaultersPage.dart's "Previous Dues") + everything owed per
        // fee_structures (which now also includes any unpaid fine
        // balance). We deliberately do NOT scan every field on the
        // student document — earlier that picked up unrelated numeric
        // fields (like a phone number) and inflated the total.
        final studentDues = asAmount(data['dues']) ?? 0;
        final structureDues = structureDuesByStudent[doc.id] ?? 0;
        final totalDues = studentDues + structureDues;
        final lastFineMonth = lastFineMonthByStudent[doc.id] ?? '';
        final name = data['name']?.toString() ?? doc.id;

        final eligible = totalDues > 0 &&
            (_forceReapply || lastFineMonth != currentMonthKey);
        debugLines.add(
            "$name — dues: $studentDues, fee_structures: $structureDues, "
            "total: $totalDues, lastFineMonth: '${lastFineMonth.isEmpty ? '-' : lastFineMonth}' "
            "→ ${eligible ? 'FINED' : 'skipped'}");

        if (eligible) {
          // Fine is stored on the fee_structures doc (same id as the
          // student doc), in its own `fine` field — never mixed into
          // `dues`. set(merge: true) is used instead of update() since
          // a fee_structures doc might not exist yet for this student
          // (e.g. a defaulter whose only pending amount was `dues`).
          // FieldValue.increment is atomic and adds on top of any
          // existing fine balance, instead of overwriting it.
          final feeStructRef = schoolCollection('fee_structures').doc(doc.id);
          batch.set(
              feeStructRef,
              {
                'fine': FieldValue.increment(fineAmount),
                'lastFineMonth': currentMonthKey,
              },
              SetOptions(merge: true));
          fined++;
          notifyList.add({
            'id': doc.id,
            'token': data['fcmToken']?.toString(),
            'name': data['name'] ?? '',
          });
        }
      }

      if (fined > 0) {
        await batch.commit();
        await schoolCollection('fine_history').add({
          'month': currentMonthKey,
          'fineAmount': fineAmount,
          'studentsFined': fined,
          'appliedAt': FieldValue.serverTimestamp(),
        });

        await NotificationHelper.sendToMultiple(
          targets: notifyList
              .map((e) =>
                  {'id': e['id'] as String, 'token': e['token'] as String?})
              .toList(),
          toRole: 'student',
          title: 'Fee Fine Notice',
          body:
              'Your monthly fee was not paid by the due date, a fine of Rs. $fineAmount has been added.',
          type: 'fine',
        );
      }

      setState(() {
        _applying = false;
        final summary = fined > 0
            ? "Fine of Rs. $fineAmount applied to $fined student(s)."
            : "No students were eligible for a fine.";
        _log = "$summary\n\n${debugLines.join('\n')}";
      });
    } catch (e) {
      setState(() {
        _applying = false;
        _log = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fee Fine Management"),
        backgroundColor: Colors.teal[800],
      ),
      body: SafeArea(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Fine Rules",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: "Fine Amount (Rs.)",
                                border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _dueDayController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText:
                                    "Day of month after which fine applies (e.g. 10)",
                                border: OutlineInputBorder()),
                          ),
                          SwitchListTile(
                            title: const Text("Fine System Enabled"),
                            value: _enabled,
                            onChanged: (v) => setState(() => _enabled = v),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _saveRules,
                              child: const Text("Save Rules"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Apply Fine to Today's Defaulters",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          const Text(
                              "Students who still have pending dues (and "
                              "haven't been fined yet this month) will get "
                              "a fine added to their fine balance, and "
                              "will receive a notification.",
                              style: TextStyle(color: Colors.black54)),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: _forceReapply,
                                onChanged: (v) =>
                                    setState(() => _forceReapply = v ?? false),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                          "Ignore 'already fined this month' (for testing)",
                                          style: TextStyle(fontSize: 13)),
                                      const Text(
                                          "Turn this on to re-apply a fine to "
                                          "students who were already fined "
                                          "this month — useful while testing. "
                                          "Leave off for normal use.",
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _enabled && !_applying
                                  ? _applyFinesNow
                                  : null,
                              icon: _applying
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.money_off),
                              label: const Text("Apply Fines Now"),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[700],
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),
                          if (_log.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(_log,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )),
    );
  }
}
