import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'subscription_service.dart';
import 'subscription_payment_page.dart' show kSubscriptionRequestsCollection;
import 'admin_auth.dart' show adminEmailForUsername;

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

class _SuperAdminSubscriptionPageState extends State<SuperAdminSubscriptionPage>
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
        actions: [
          // Lets the developer/owner create a brand new school account
          // (Firebase Auth login + schools/{id} doc) directly from this
          // panel, instead of needing to do it manually in the Firebase
          // Console every time a new school signs up.
          IconButton(
            tooltip: "Create New School Account",
            icon: const Icon(Icons.add_business),
            onPressed: _createSchoolDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // Both selected and unselected tab labels stay fully white,
          // rather than dimming the unselected one to white70.
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(
              child: Text(
                "Schools",
                style: TextStyle(color: Colors.white),
              ),
            ),
            Tab(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(kSubscriptionRequestsCollection)
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  return Text(
                    count > 0
                        ? "Payment Requests ($count)"
                        : "Payment Requests",
                    style: const TextStyle(color: Colors.white),
                  );
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

            final bool isDeactivated = status == 'deactivated';

            final Color chipColor = isDeactivated
                ? Colors.grey
                : expired
                    ? Colors.red
                    : (daysLeft != null && daysLeft <= 7)
                        ? Colors.orange
                        : Colors.green;

            return Card(
              color: Colors.white,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(
                  (data['schoolName'] as String?) ?? doc.id,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                subtitle: Text(
                  isDeactivated
                      ? "Status: $status | Account deactivated by admin"
                      : endDate == null
                          ? "No subscription data yet"
                          : "Status: $status | Ends: ${endDate.toLocal().toString().split(' ').first}"
                              "${expired ? ' (EXPIRED)' : (daysLeft != null ? ' ($daysLeft days left)' : '')}",
                  style: const TextStyle(color: Colors.black54),
                ),
                leading: CircleAvatar(
                  backgroundColor: chipColor,
                  child: const Icon(Icons.school, color: Colors.white),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => _extendDialog(
                          doc.id, (data['schoolName'] as String?) ?? doc.id),
                      child: const Text("Extend"),
                    ),
                    const SizedBox(width: 4),
                    // Small icon-only action next to Extend for blocking or
                    // restoring a school's access, independent of how much
                    // subscription time is left.
                    IconButton(
                      tooltip: isDeactivated
                          ? "Reactivate account"
                          : "Deactivate account",
                      icon: Icon(
                        isDeactivated
                            ? Icons.check_circle_outline
                            : Icons.block,
                        color: isDeactivated ? Colors.green : Colors.red,
                      ),
                      onPressed: () => _toggleAccountActive(
                        doc.id,
                        (data['schoolName'] as String?) ?? doc.id,
                        isDeactivated,
                      ),
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

  Widget _paymentRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      // Shows every payment request regardless of status (pending, approved,
      // or rejected) so approved/rejected payments stay on record here
      // instead of disappearing from the panel once they're reviewed. The
      // tab badge above still counts pending ones only (see the TabBar
      // StreamBuilder), and Approve/Reject actions only appear on requests
      // that are still pending.
      stream: FirebaseFirestore.instance
          .collection(kSubscriptionRequestsCollection)
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    "Couldn't load payment requests.",
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${snap.error}",
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "This usually means Firestore needs a composite index for "
                    "this query (status + requestedAt). Check your debug "
                    "console logs for a link to create it automatically, or "
                    "add it manually in Firebase Console > Firestore > Indexes.",
                    style: TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text("Retry"),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return _LoadingWithTimeoutHint(onRetry: () => setState(() {}));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text("No payment requests yet."));
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
            final status = (data['status'] as String?) ?? 'pending';
            final ts = data['requestedAt'];
            final date = ts is Timestamp
                ? DateFormat('d MMM, yyyy – h:mm a').format(ts.toDate())
                : '';
            final reviewedTs = data['reviewedAt'];
            final reviewedDate = reviewedTs is Timestamp
                ? DateFormat('d MMM, yyyy – h:mm a').format(reviewedTs.toDate())
                : '';
            final reviewedDays = data['reviewedDays'];

            final Color statusColor = status == 'approved'
                ? Colors.green
                : (status == 'rejected' ? Colors.red : Colors.orange);
            final String statusLabel = status == 'approved'
                ? "Approved"
                : (status == 'rejected' ? "Rejected" : "Pending");

            // Compact single-line row per record — full details (note,
            // screenshot, reviewed info, Approve/Reject) only appear once
            // the row is tapped, via _showRequestDetails below. Keeps the
            // list scannable instead of every record's screenshot and
            // buttons being expanded inline all at once.
            return Card(
              color: Colors.white,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                onTap: () => _showRequestDetails(
                  doc: doc,
                  schoolName: schoolName,
                  schoolId: schoolId,
                  note: note,
                  screenshotUrl: screenshotUrl,
                  status: status,
                  statusLabel: statusLabel,
                  statusColor: statusColor,
                  date: date,
                  reviewedDate: reviewedDate,
                  reviewedDays: reviewedDays,
                ),
                leading: CircleAvatar(
                  backgroundColor: statusColor,
                  child: const Icon(Icons.payments, color: Colors.white),
                ),
                title: Text(schoolName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black87)),
                subtitle: Text("Submitted: $date",
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
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
          backgroundColor: Colors.white,
          title: Text("Extend: $schoolName",
              style: const TextStyle(color: Colors.black87)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Extend by (days): ",
                  style: TextStyle(color: Colors.black87)),
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

  // Deactivates or reactivates a school's account, independent of its
  // subscription end date. Used by the small icon next to "Extend" in the
  // Schools tab. Deactivating blocks the school from accessing the app
  // even if their subscription is still valid; reactivating restores
  // access as 'active' so the normal expiry checks resume.
  Future<void> _toggleAccountActive(
      String schoolId, String schoolName, bool isDeactivated) async {
    final String action = isDeactivated ? "Reactivate" : "Deactivate";
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text("$action $schoolName?",
            style: const TextStyle(color: Colors.black87)),
        content: Text(
          isDeactivated
              ? "This will restore the school's access to the app."
              : "This will block the school from accessing the app, "
                  "even if their subscription is still valid.",
          style: const TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: isDeactivated ? Colors.green : Colors.red),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .update({
      'subscriptionStatus': isDeactivated ? 'active' : 'deactivated',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDeactivated
              ? "$schoolName reactivated."
              : "$schoolName deactivated."),
          backgroundColor: isDeactivated ? Colors.green : Colors.red,
        ),
      );
    }
  }

  // Shows the full record for a single payment request — submitted date,
  // status, reference note, reviewed info, screenshot, and (only while
  // still pending) the Approve/Reject actions. Opened by tapping a row in
  // the compact list built in _paymentRequestsTab.
  void _showRequestDetails({
    required QueryDocumentSnapshot doc,
    required String schoolName,
    required String schoolId,
    required String note,
    required String screenshotUrl,
    required String status,
    required String statusLabel,
    required Color statusColor,
    required String date,
    required String reviewedDate,
    required int? reviewedDays,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Expanded(
              child: Text(schoolName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black87)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Submitted: $date",
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              if (status != 'pending' && reviewedDate.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    status == 'approved'
                        ? "Approved: $reviewedDate${reviewedDays != null ? ' (+$reviewedDays days)' : ''}"
                        : "Rejected: $reviewedDate",
                    style: TextStyle(fontSize: 13, color: statusColor),
                  ),
                ),
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "Ref: $note",
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              if (screenshotUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
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
              ],
              // Approve/Reject actions only make sense while the request
              // is still pending — once reviewed, the status badge and
              // reviewed date above are the permanent record.
              if (status == 'pending') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _rejectRequest(doc.id, schoolName);
                        },
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
                            : () {
                                Navigator.pop(dialogContext);
                                _approveRequest(doc.id, schoolId, schoolName);
                              },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white),
                        child: const Text("Approve"),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Close"),
          ),
        ],
      ),
    );
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
        backgroundColor: Colors.white,
        title: Text("Reject $schoolName's request?",
            style: const TextStyle(color: Colors.black87)),
        content: const Text(
          "The school will see this request marked as rejected.",
          style: TextStyle(color: Colors.black87),
        ),
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
          backgroundColor: Colors.white,
          title: Text("Approve: $schoolName",
              style: const TextStyle(color: Colors.black87)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Extend by (days): ",
                  style: TextStyle(color: Colors.black87)),
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
          content: Text("$schoolName approved and extended by $result days."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Shows the "Create New School Account" form (School Name + Admin
  // Username/Password) and creates everything needed for that school to
  // log in immediately: a Firebase Auth account for the admin, the
  // schools/{schoolId} document (started on a 30-day trial, same as an
  // existing school's first login would auto-create), the
  // schools/{schoolId}/users/{uid} login-lookup doc, and a blank
  // settings/global doc.
  Future<void> _createSchoolDialog() async {
    final schoolNameController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirm = true;
    bool isSaving = false;
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text("Create New School Account",
              style: TextStyle(color: Colors.black87)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: schoolNameController,
                  enabled: !isSaving,
                  decoration:
                      const InputDecoration(labelText: "School Name"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: usernameController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: "Admin Username",
                    helperText: "This is what the school logs in with",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  enabled: !isSaving,
                  decoration: InputDecoration(
                    labelText: "Admin Password",
                    suffixIcon: IconButton(
                      icon: Icon(obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirm,
                  enabled: !isSaving,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setDialogState(
                          () => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(errorText!, style: const TextStyle(color: Colors.red)),
                ],
                if (isSaving) ...[
                  const SizedBox(height: 14),
                  const CircularProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final schoolName = schoolNameController.text.trim();
                      final username = usernameController.text.trim();
                      final password = passwordController.text;
                      final confirmPassword =
                          confirmPasswordController.text;

                      if (schoolName.isEmpty ||
                          username.isEmpty ||
                          password.isEmpty) {
                        setDialogState(
                            () => errorText = "All fields are required.");
                        return;
                      }
                      if (password.length < 6) {
                        setDialogState(() => errorText =
                            "Password must be at least 6 characters.");
                        return;
                      }
                      if (password != confirmPassword) {
                        setDialogState(() =>
                            errorText = "Passwords do not match.");
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        errorText = null;
                      });

                      try {
                        final schoolId = await _createSchoolAccount(
                          schoolName: schoolName,
                          username: username,
                          password: password,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  "$schoolName created (School ID: $schoolId). "
                                  "Share the username \"$username\" and password with them."),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 8),
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          errorText = e.code == 'email-already-in-use'
                              ? "That username is already taken — choose another."
                              : e.code == 'weak-password'
                                  ? "That password is too weak — choose another."
                                  : (e.message ?? "Could not create the account.");
                        });
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          errorText = "Something went wrong: $e";
                        });
                      }
                    },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );

    schoolNameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
  }

  // Creates the admin's Firebase Auth account plus the three Firestore
  // documents a school needs to exist and log in. Returns the new
  // schoolId.
  //
  // IMPORTANT: createUserWithEmailAndPassword() automatically signs in
  // as the newly created user on whichever FirebaseAuth instance it's
  // called on. Calling it on FirebaseAuth.instance directly would sign
  // the Super Admin OUT of their own session on this device. To avoid
  // that, the new admin account is created on a separate, temporary
  // secondary Firebase app instance, which is deleted right afterwards —
  // the Super Admin's own session is never touched.
  Future<String> _createSchoolAccount({
    required String schoolName,
    required String username,
    required String password,
  }) async {
    final schoolsRef = FirebaseFirestore.instance.collection('schools');

    // Build a readable, unique schoolId from the school name (e.g.
    // "City Grammar School" -> "city_grammar_school"), appending a
    // number if that slug is already taken.
    String baseSlug = schoolName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (baseSlug.isEmpty) baseSlug = 'school';
    String schoolId = baseSlug;
    int suffix = 1;
    while ((await schoolsRef.doc(schoolId).get()).exists) {
      suffix++;
      schoolId = '${baseSlug}_$suffix';
    }

    final tempApp = await Firebase.initializeApp(
      name: 'create_school_${DateTime.now().millisecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final String authEmail = adminEmailForUsername(username);
    String uid;
    try {
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final cred = await tempAuth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw StateError("Account creation failed — no user returned.");
      }
      uid = user.uid;
      await tempAuth.signOut();
    } finally {
      await tempApp.delete();
    }

    // Same 30-day trial a first-ever login would auto-create in
    // SubscriptionInfo.fetch() — see subscription_service.dart.
    final trialEnd = DateTime.now().add(const Duration(days: 30));

    final batch = FirebaseFirestore.instance.batch();
    batch.set(schoolsRef.doc(schoolId), {
      'schoolName': schoolName,
      'subscriptionStatus': 'trial',
      'subscriptionEndDate': Timestamp.fromDate(trialEnd),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      schoolsRef.doc(schoolId).collection('users').doc(uid),
      {
        'username': username,
        'authEmail': authEmail,
        'authUid': uid,
        'role': 'admin',
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      schoolsRef.doc(schoolId).collection('settings').doc('global'),
      {'schoolName': schoolName},
      SetOptions(merge: true),
    );
    await batch.commit();

    return schoolId;
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

/// A loading spinner that stops spinning silently forever: if the stream
/// hasn't delivered any data after a few seconds (most commonly because a
/// newly created Firestore composite index is still "Building"), this
/// swaps to a message explaining why and a manual Retry button, instead of
/// leaving the user staring at an endless spinner with no explanation.
class _LoadingWithTimeoutHint extends StatefulWidget {
  const _LoadingWithTimeoutHint({required this.onRetry});

  final VoidCallback onRetry;

  @override
  State<_LoadingWithTimeoutHint> createState() =>
      _LoadingWithTimeoutHintState();
}

class _LoadingWithTimeoutHintState extends State<_LoadingWithTimeoutHint> {
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showHint = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_showHint) ...[
              const SizedBox(height: 16),
              const Text(
                "Still loading. If you just created a Firestore index, "
                "it can take a few minutes to finish building before "
                "this list appears.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: widget.onRetry,
                child: const Text("Retry"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
