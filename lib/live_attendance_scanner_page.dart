import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'school_context.dart';
import 'notification_helper.dart';
import 'attendance_page.dart';

/// The student holds their ID card (QR code) in front of the camera and
/// attendance is automatically marked "Present" — no need to manually
/// tick a list.
///
/// QR format (generated in student_id_card_page.dart /
/// parent_id_card_page.dart): "AEPQR|{schoolId}|{studentId}\n..."
///
/// NOTE: mobile_scanner works well on Android/iOS/macOS/Web. Camera
/// plugin support is limited on Windows desktop — this screen will open
/// on Windows but scanning won't work, so a "Manual Entry" option is
/// also provided below (attendance can also be marked by searching for
/// a Student ID).
class LiveAttendanceScannerPage extends StatefulWidget {
  const LiveAttendanceScannerPage({super.key});

  @override
  State<LiveAttendanceScannerPage> createState() =>
      _LiveAttendanceScannerPageState();
}

class _LiveAttendanceScannerPageState
    extends State<LiveAttendanceScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;
  String? _lastResult;
  DateTime? _lastScanTime;
  final List<String> _todayLog = [];

  String get _todayKey {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_processing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || !code.startsWith('AEPQR|')) return;

    // 4-second cooldown to stop the same QR from being scanned repeatedly.
    if (_lastResult == code &&
        _lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!).inSeconds < 4) {
      return;
    }

    final parts = code.split('|');
    if (parts.length < 3) return;
    final scannedSchoolId = parts[1];
    final studentId = parts[2].split('\n').first.trim();

    if (scannedSchoolId != SchoolContext.schoolId) {
      _showBanner("This card does not belong to this school!", Colors.red);
      return;
    }

    setState(() {
      _processing = true;
      _lastResult = code;
      _lastScanTime = DateTime.now();
    });

    try {
      await _markAttendance(studentId);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _markAttendance(String studentId) async {
    final studentDoc =
        await schoolCollection('students').doc(studentId).get();
    if (!studentDoc.exists) {
      _showBanner("Student record not found!", Colors.red);
      return;
    }
    final data = studentDoc.data()!;
    final className = data['class'] ?? 'N/A';
    final name = data['name'] ?? 'N/A';
    final docId = "${_todayKey}_$studentId"; // unified: date+studentId only, matches admin/teacher attendance pages

    final existing =
        await schoolCollection('attendance').doc(docId).get();
    if (existing.exists && existing.data()?['status'] == 'Present') {
      _showBanner("$name — Attendance is already marked.", Colors.orange);
      return;
    }

    await schoolCollection('attendance').doc(docId).set({
      'class': className,
      'studentId': studentId,
      'status': 'Present',
      'date': _todayKey,
      'timestamp': FieldValue.serverTimestamp(),
      'markedVia': 'qr_scan',
    }, SetOptions(merge: true));

    // Just like manual attendance, an app-notification is sent to the
    // parent here too, so they also get notified for QR-scanned attendance.
    try {
      await NotificationHelper.sendToUser(
        toId: studentId,
        toRole: 'student',
        title: 'Attendance: Present',
        body: '$name marked Present today ($_todayKey) via QR scan.',
        type: 'attendance',
        fcmToken: data['fcmToken'] as String?,
      );
    } catch (e) {
      debugPrint('QR attendance notify failed: $e');
    }

    setState(() {
      _todayLog.insert(0, "$name ($className) — Present ✅");
    });
    _showBanner("$name — Attendance Marked ✅", Colors.green);
  }

  void _showBanner(String text, Color color) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  // "Manual Entry" now opens the same Attendance page that admin uses
  // for normal (non-QR) attendance marking — same class dropdown, same
  // Present/Absent/Leave buttons, same SAVE button. Because of this,
  // attendance marked from both places (QR scan and manual) is saved in
  // exactly the same way (same collection, same doc-id format, and the
  // same parent-notification is sent for Absent students).
  Future<void> _manualEntry() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => const AttendancePage(initialTabIndex: 0)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Attendance (QR Scan)"),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(
              onPressed: () => _controller.toggleTorch(),
              icon: const Icon(Icons.flash_on)),
        ],
      ),
      body: SafeArea(child: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _handleBarcode,
                ),
                if (_processing)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: OutlinedButton.icon(
              onPressed: _manualEntry,
              icon: const Icon(Icons.keyboard),
              label: const Text("Manual Entry (if camera is unavailable)"),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[100],
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _todayLog.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(_todayLog[i]),
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
