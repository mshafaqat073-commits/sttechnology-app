import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notification_helper.dart';
import 'school_context.dart';

/// Shows the admin students/staff whose birthdays fall today or within
/// the next 7 days. Each entry has a "Send WhatsApp Wish" button — this
/// opens WhatsApp's free deep-link (wa.me) with a ready-made message; the
/// admin just taps Send (no paid API needed). Each entry also has a
/// "Send App Notification" button, which queues an in-app push
/// notification (see [_sendPushNotification] below) for the recipient.
///
/// The student's 'dob' field is saved by admission_page.dart in
/// "d-m-yyyy" format (without zero-padding) — that's the format parsed
/// here.
class BirthdayPage extends StatefulWidget {
  const BirthdayPage({super.key});

  @override
  State<BirthdayPage> createState() => _BirthdayPageState();
}

class _BirthdayEntry {
  final String name;
  final String label; // class/section or "Staff"
  final String phone;
  final String? userId; // linked auth/user doc id, used for push notifications
  final String role; // 'student' | 'teacher' — matches NotificationHelper.toRole
  final String? fcmToken; // used by NotificationHelper to send the actual push
  final int day;
  final int month;
  final bool isToday;
  _BirthdayEntry(
      {required this.name,
      required this.label,
      required this.phone,
      required this.userId,
      required this.role,
      required this.fcmToken,
      required this.day,
      required this.month,
      required this.isToday});
}

class _BirthdayPageState extends State<BirthdayPage> {
  bool _loading = true;
  List<_BirthdayEntry> _today = [];
  List<_BirthdayEntry> _upcoming = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _parseDob(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    // Expected "d-m-yyyy" (admission_page.dart format) — some older
    // records may use "d/m/yyyy", so both are handled here.
    final parts = raw.trim().split(RegExp(r'[-/]'));
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final List<_BirthdayEntry> today = [];
    final List<_BirthdayEntry> upcoming = [];

    try {
      final studentsSnap = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();

      for (var doc in studentsSnap.docs) {
        final d = doc.data();
        final dob = _parseDob(d['dob']?.toString());
        if (dob == null) continue;
        final label = "${d['class'] ?? ''} ${d['section'] ?? ''}".trim();
        final phone =
            (d['contactNo'] ?? d['contactNo2'] ?? '').toString().trim();
        final entry = _BirthdayEntry(
          name: d['name'] ?? 'N/A',
          label: label.isEmpty ? 'Student' : label,
          phone: phone,
          userId: (d['userId'] ?? doc.id).toString(),
          role: 'student',
          fcmToken: d['fcmToken']?.toString(),
          day: dob.day,
          month: dob.month,
          isToday: dob.day == now.day && dob.month == now.month,
        );
        _classifyAndAdd(entry, now, today, upcoming);
      }

      // Staff birthdays (only if a 'dob' field is present — optional).
      final staffSnap = await schoolCollection('staff').get();
      for (var doc in staffSnap.docs) {
        final d = doc.data();
        final dob = _parseDob(d['dob']?.toString());
        if (dob == null) continue;
        final phone = (d['contact'] ?? '').toString().trim();
        final entry = _BirthdayEntry(
          name: d['name'] ?? 'N/A',
          label: 'Staff',
          phone: phone,
          userId: (d['userId'] ?? doc.id).toString(),
          role: 'teacher',
          fcmToken: d['fcmToken']?.toString(),
          day: dob.day,
          month: dob.month,
          isToday: dob.day == now.day && dob.month == now.month,
        );
        _classifyAndAdd(entry, now, today, upcoming);
      }
    } catch (e) {
      debugPrint('Birthday load error: $e');
    }

    today.sort((a, b) => a.name.compareTo(b.name));
    upcoming.sort((a, b) {
      final aOrdinal = _dayOrdinal(a, now);
      final bOrdinal = _dayOrdinal(b, now);
      return aOrdinal.compareTo(bOrdinal);
    });

    if (mounted) {
      setState(() {
        _today = today;
        _upcoming = upcoming;
        _loading = false;
      });
    }
  }

  // How many days away the birthday is (used for sorting).
  int _dayOrdinal(_BirthdayEntry e, DateTime now) {
    var next = DateTime(now.year, e.month, e.day);
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year + 1, e.month, e.day);
    }
    return next.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  void _classifyAndAdd(_BirthdayEntry entry, DateTime now,
      List<_BirthdayEntry> today, List<_BirthdayEntry> upcoming) {
    if (entry.isToday) {
      today.add(entry);
      return;
    }
    final daysAway = _dayOrdinal(entry, now);
    if (daysAway > 0 && daysAway <= 7) {
      upcoming.add(entry);
    }
  }

  Future<void> _sendWhatsAppWish(_BirthdayEntry entry) async {
    if (entry.phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No phone number is saved for this person."),
          backgroundColor: Colors.red));
      return;
    }
    var phone = entry.phone.replaceAll(RegExp(r'[^0-9]'), '');
    // If it's a Pakistani number starting with 0, prefix +92.
    if (phone.startsWith('0')) {
      phone = '92${phone.substring(1)}';
    }
    final schoolName = SchoolContext.schoolName ?? 'School';
    final message = Uri.encodeComponent(
        "🎉 Happy Birthday ${entry.name}! 🎂\n\nBest wishes and good luck from $schoolName!");
    final url = Uri.parse("https://wa.me/$phone?text=$message");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Could not open WhatsApp."),
            backgroundColor: Colors.red));
      }
    }
  }

  /// Sends the in-app notification (+ real push, if a device token is on
  /// file) using the same [NotificationHelper] that the rest of the app
  /// (e.g. DefaultersPage's fee reminders) uses. This writes to the
  /// `push_notifications` collection the app's Notifications screen
  /// actually reads, and — when `fcmToken` is available — relays a real
  /// push via the Apps Script endpoint configured in NotificationHelper.
  Future<void> _sendPushNotification(_BirthdayEntry entry) async {
    if (entry.userId == null || entry.userId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No linked user account found for this person."),
          backgroundColor: Colors.red));
      return;
    }
    final schoolName = SchoolContext.schoolName ?? 'School';
    try {
      await NotificationHelper.sendToUser(
        toId: entry.userId!,
        toRole: entry.role,
        title: 'Happy Birthday, ${entry.name}! 🎉',
        body: 'Best wishes and good luck from $schoolName!',
        type: 'birthday_wish',
        fcmToken: entry.fcmToken,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("App notification sent."),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint('Push notification error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Could not send app notification."),
            backgroundColor: Colors.red));
      }
    }
  }

  Widget _entryTile(_BirthdayEntry e) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: const CircleAvatar(
            backgroundColor: Colors.pink,
            child: Icon(Icons.cake, color: Colors.white)),
        title:
            Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${e.label} • ${e.day}/${e.month}"),
        trailing: Wrap(
          spacing: 6,
          children: [
            ElevatedButton.icon(
              onPressed: () => _sendWhatsAppWish(e),
              icon: const Icon(Icons.chat, size: 16),
              label: const Text("Wish"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white),
            ),
            ElevatedButton.icon(
              onPressed: () => _sendPushNotification(e),
              icon: const Icon(Icons.notifications_active, size: 16),
              label: const Text("Notify"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal[700],
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Birthdays"),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text("Today (${_today.length})",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (_today.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text("No birthdays today."),
                    ),
                  ..._today.map(_entryTile),
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text("Next 7 Days (${_upcoming.length})",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (_upcoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text("No birthdays coming up next week."),
                    ),
                  ..._upcoming.map(_entryTile),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
