import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'subscription_service.dart';

/// Roadmap step 7: "You Confirm in Super Admin Panel".
///
/// This panel sits outside any school's SchoolContext (it's used by the
/// developer/owner) — so it reads the top-level `schools` collection
/// directly (not schoolCollection(), which is scoped to the currently
/// logged-in school).
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
    extends State<SuperAdminSubscriptionPage> {
  static const String _ownerPassword = "sm6585073";

  bool _unlocked = false;
  bool _obscurePassword = true;
  final _pwController = TextEditingController();
  String? _error;

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
      ),
      body: StreamBuilder<QuerySnapshot>(
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
              final expired =
                  endDate != null && DateTime.now().isAfter(endDate);

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
      ),
    );
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
              const Text("Days: "),
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
              child: const Text("Confirm Payment Received"),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    await SubscriptionInfo.extend(schoolId: schoolId, extraDays: result);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$schoolName subscription extended by $result days."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
