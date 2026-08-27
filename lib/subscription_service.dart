import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

/// Implementation of the Subscription Roadmap.
///
/// Firestore: the schools/{schoolId} document gets 2 new fields:
///   subscriptionStatus   -> 'trial' | 'active'
///   subscriptionEndDate  -> Timestamp (access is valid until this date)
///
/// If these fields don't exist yet on an older school doc (so this new
/// feature doesn't break existing schools), [SubscriptionInfo.fetch]
/// automatically starts a 30-day trial (the first time any admin logs in).
class SubscriptionInfo {
  final String status; // 'trial' | 'active'
  final DateTime endDate;

  const SubscriptionInfo({required this.status, required this.endDate});

  int get daysLeft {
    final diff = endDate.difference(DateTime.now());
    // Round up so "6 hours left" still shows as "1 day left", not 0.
    return diff.isNegative ? 0 : (diff.inHours / 24).ceil();
  }

  bool get isExpired => DateTime.now().isAfter(endDate);
  bool get isExpiringSoon => !isExpired && daysLeft <= 7;
  bool get isActive => !isExpired;

  /// Call this on every app open (right after login, and again when the
  /// Dashboard loads) — reads the schools/{schoolId} doc and returns the
  /// current status. If the fields are missing it sets up a fresh 30-day
  /// trial.
  static Future<SubscriptionInfo> fetch() async {
    final ref = schoolDoc();
    final snap = await ref.get();
    final data = snap.data();

    final rawStatus = data?['subscriptionStatus'] as String?;
    final rawEnd = data?['subscriptionEndDate'];

    if (rawStatus == null || rawEnd == null) {
      // First time — start a 30-day free trial for this school.
      final trialEnd = DateTime.now().add(const Duration(days: 30));
      await ref.set({
        'subscriptionStatus': 'trial',
        'subscriptionEndDate': Timestamp.fromDate(trialEnd),
      }, SetOptions(merge: true));
      return SubscriptionInfo(status: 'trial', endDate: trialEnd);
    }

    final endDate = (rawEnd as Timestamp).toDate();
    return SubscriptionInfo(status: rawStatus, endDate: endDate);
  }

  /// Called when "Extend Subscription" is tapped in the Super Admin panel —
  /// sets subscriptionStatus to 'active' and pushes endDate forward. If
  /// [fromToday] is true, it always extends from today+extraDays (even if
  /// the old date already expired); otherwise it adds extraDays on top of
  /// the existing endDate (if it hasn't expired yet).
  static Future<void> extend({
    required String schoolId,
    int extraDays = 30,
    bool fromToday = true,
  }) async {
    final ref = FirebaseFirestore.instance.collection('schools').doc(schoolId);
    DateTime base = DateTime.now();
    if (!fromToday) {
      final snap = await ref.get();
      final rawEnd = snap.data()?['subscriptionEndDate'];
      if (rawEnd is Timestamp) {
        final current = rawEnd.toDate();
        if (current.isAfter(base)) base = current;
      }
    }
    final newEnd = base.add(Duration(days: extraDays));
    await ref.set({
      'subscriptionStatus': 'active',
      'subscriptionEndDate': Timestamp.fromDate(newEnd),
    }, SetOptions(merge: true));
  }
}
