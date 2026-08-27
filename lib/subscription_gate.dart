import 'package:flutter/material.dart';
import 'subscription_service.dart';

/// Banner shown at the top of the Dashboard — this is where Roadmap
/// steps 4-6 (Still Active / Expiring Soon / Expired) appear.
/// Shows nothing (an empty SizedBox) when active/trial with more than
/// 7 days left.
class SubscriptionBanner extends StatelessWidget {
  const SubscriptionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SubscriptionInfo>(
      future: SubscriptionInfo.fetch(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final info = snap.data!;

        if (!info.isExpiringSoon && !info.isExpired) {
          return const SizedBox.shrink();
        }

        final bool expired = info.isExpired;
        final Color color = expired ? Colors.red[700]! : Colors.orange[800]!;
        final String message = expired
            ? "Your subscription has expired. New admissions/edits are disabled — the app is in view-only mode."
            : "Your subscription expires in ${info.daysLeft} day(s). Please renew in time to avoid interruption.";

        return Container(
          width: double.infinity,
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(expired ? Icons.lock_clock : Icons.warning_amber_rounded,
                  color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Guard any "Add/Edit" action (a new admission, adding staff, editing a
/// fee, etc.) with this — if the subscription has expired it shows a
/// dialog and returns `false` (so the action stops); otherwise it
/// returns `true` (the action proceeds normally).
///
/// Usage:
///   onPressed: () async {
///     if (!await SubscriptionGuard.ensureActive(context)) return;
///     // ... normal add/edit logic ...
///   }
class SubscriptionGuard {
  static Future<bool> ensureActive(BuildContext context) async {
    final info = await SubscriptionInfo.fetch();
    if (!info.isExpired) return true;

    if (!context.mounted) return false;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Subscription Expired"),
        content: const Text(
            "You need to renew the subscription to add a new admission/edit. "
            "Please pay the renewal fee and have the developer/admin extend your subscription."),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
    return false;
  }
}
