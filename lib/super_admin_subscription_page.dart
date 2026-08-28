import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'subscription_service.dart';
import 'subscription_payment_page.dart' show kSubscriptionRequestsCollection;

/// Roadmap step 7: "You Confirm in Super Admin Panel".
///
/// This panel sits outside any school's SchoolContext (it's used by the
/// developer/owner) — so it reads top-level collections directly
/// (`schools` and `subscriptionPaymentRequests`), not schoolCollection()
/// which is scoped to the currently logged-in school.
///
/// Two tabs:
///  - Schools: manual "Extend" button per school (unchanged from before).
///  - Payment Requests: the screenshots schools submit via Settings >
///    "Pay to Renew Subscription". Approve extends that school's
///    subscription automatically; Reject just marks the request so the
///    school can see it wasn't accepted.
///
/// SECURITY NOTE: This is just a basic password gate (security through
/// obscurity — you only reach it via long-press on the role selector
/// logo). If you want this to be more secure, protect it with your own
/// Firebase Auth admin account (a custom claim like `superAdmin: true`)
/// instead — for now, change `_ownerPassword` below to something hard
/// to guess.
class SuperAdminSubscriptionPage extends StatefulWidget {
  const SuperAdminSubscriptionPage({super.key});

  @override
  State<SuperAdminSubscriptionPage> createState() =>
      _SuperAdminSubscriptionPageState();
}

class _SuperAdminSubscriptionPageState
    extends State<SuperAdminSubscriptionPage>
    with SingleTickerProviderStateMixin {
  static const String _ownerPassword = "sm6585073";

  bool _unlocked = false;
  bool _obscurePassword = true;
  final _pwController = TextEditingController();
  String? _error;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pwController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text("Super Admin")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings, size: 48),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: "Owner Password",
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onSubmitted: (_) => _tryUnlock(),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _tryUnlock,
                  child: const Text("Unlock"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Schools — Subscriptions"),
        backgroundColor: Colors.deepPurple,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: "Schools"),
            Tab(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(kSubscriptionRequestsCollection)
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  return Text(count > 0
                      ? "Payment Requests ($count)"
                      : "Payment Requests");
                },
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _schoolsTab(),
          _paymentRequestsTab(),
        ],
      ),
    );
  }

  Widget _schoolsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('schools').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text("No schools found."));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['subscriptionStatus'] as String?) ?? 'trial';
            final rawEnd = data['subscriptionEndDate'];
            final endDate = rawEnd is Timestamp ? rawEnd.toDate() : null;
            final daysLeft = endDate?.difference(DateTime.now()).inDays;
            final expired = endDate != null && DateTime.now().isAfter(endDate);

            final Color chipColor = expired
                ? Colors.red
                : (daysLeft != null && daysLeft <= 7)
                    ? Colors.orange
                    : Colors.green;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(
                  (data['schoolName'] as String?) ?? doc.id,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  endDate == null
                      ? "No subscription data yet"
                      : "Status: $status | Ends: ${endDate.toLocal().toString().split(' ').first}"
                          "${expired ? ' (EXPIRED)' : (daysLeft != null ? ' ($daysLeft days left)' : '')}",
                ),
                leading: CircleAvatar(
                  backgroundColor: chipColor,
                  child: const Icon(Icons.school, color: Colors.white),
                ),
                trailing: ElevatedButton(
                  onPressed: () => _extendDialog(
                      doc.id, (data['schoolName'] as String?) ?? doc.id),
                  child: const Text("Extend"),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _paymentRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(kSubscriptionRequestsCollection)
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text("No pending payment requests."));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final schoolName = (data['schoolName'] as String?) ?? doc.id;
            final schoolId = (data['schoolId'] as String?) ?? '';
            final note = (data['note'] as String?) ?? '';
            final screenshotUrl = (data['screenshotUrl'] as String?) ?? '';
            final ts = data['requestedAt'];
            final date = ts is Timestamp
                ? DateFormat('d MMM, yyyy – h:mm a').format(ts.toDate())
                : '';

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(schoolName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("Submitted: $date",
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text("Ref: $note"),
                      ),
                    const SizedBox(height: 8),
                    if (screenshotUrl.isNotEmpty)
                      GestureDetector(
                        onTap: () => _viewScreenshot(screenshotUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            screenshotUrl,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              height: 120,
                              child: Center(child: Icon(Icons.broken_image)),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                _rejectRequest(doc.id, schoolName),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: const Text("Reject"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: schoolId.isEmpty
                                ? null
                                : () => _approveRequest(
                                    doc.id, schoolId, schoolName),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white),
                            child: const Text("Approve"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _extendDialog(String schoolId, String schoolName) async {
    int days = 30;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text("Extend: $schoolName"),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Extend by (days): "),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: days,
                items: [30, 90, 180, 365]
                    .map((d) => DropdownMenuItem(value: d, child: Text("$d")))
                    .toList(),
                onChanged: (v) => setDialogState(() => days = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, days),
              child: const Text("Extend"),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    await SubscriptionInfo.extend(schoolId: schoolId, extraDays: result);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$schoolName extended by $result days.")),
      );
    }
  }

  void _viewScreenshot(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.network(url),
        ),
      ),
    );
  }

  Future<void> _rejectRequest(String requestId, String schoolName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Reject $schoolName's request?"),
        content: const Text(
            "The school will see this request marked as rejected."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Reject")),
        ],
      ),
    );
    if (confirmed != true) return;

    await FirebaseFirestore.instance
        .collection(kSubscriptionRequestsCollection)
        .doc(requestId)
        .update({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$schoolName's request rejected.")),
      );
    }
  }

  Future<void> _approveRequest(
      String requestId, String schoolId, String schoolName) async {
    int days = 30;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text("Approve: $schoolName"),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Extend by (days): "),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: days,
                items: [30, 90, 180, 365]
                    .map((d) => DropdownMenuItem(value: d, child: Text("$d")))
                    .toList(),
                onChanged: (v) => setDialogState(() => days = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, days),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("Approve & Extend"),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    await SubscriptionInfo.extend(schoolId: schoolId, extraDays: result);

    await FirebaseFirestore.instance
        .collection(kSubscriptionRequestsCollection)
        .doc(requestId)
        .update({
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedDays': result,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text("$schoolName approved and extended by $result days."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _tryUnlock() {
    if (_pwController.text == _ownerPassword) {
      setState(() {
        _unlocked = true;
        _error = null;
      });
    } else {
      setState(() => _error = "Wrong password");
    }
  }
}
