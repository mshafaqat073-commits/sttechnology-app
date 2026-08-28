import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admission_page.dart';
import 'login_page.dart';
import 'class_selection_page.dart';
import 'StaffDashboard.dart';
import 'fee_dashboard.dart';
import 'ExpenseDashboard.dart';
import 'settings_page.dart';
import 'result_menu_page.dart';
import 'profit_loss_page.dart';
import 'ai_chat_page.dart';
import 'home_task_page.dart';
import 'events_page.dart';
import 'attendance_selection_page.dart';
import 'reports_page.dart';
import 'IdCardGeneratorHubPage.dart';
import 'ai_paper_generator_page.dart';
import 'notification_ticker_widget.dart';
import 'responsive_grid.dart';
import 'teacher_notification_admin_page.dart';
import 'timetable_management_page.dart';
import 'fee_payment_verification_page.dart';
import 'document_management_page.dart';
import 'app_usage_page.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'admin_complaints_page.dart';
import 'admin_leave_applications_page.dart';
import 'birthday_page.dart';
import 'live_attendance_scanner_page.dart';
import 'online_classes_page.dart';
import 'subscription_gate.dart';
import 'app_update_checker.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 32,
              width: 32,
              child: SchoolLogo(fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: SchoolNameText(
                suffix: " Dashboard",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.teal[800],
        actions: [
          // All account/dashboard actions live under a single menu button,
          // opened as a dropdown list, instead of a row of separate icons.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: "Menu",
            onSelected: (value) async {
              switch (value) {
                case 'notifications':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManageNotificationsPage(),
                    ),
                  );
                  break;
                case 'teacher_notifications':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const ManageTeacherNotificationsPage(),
                    ),
                  );
                  break;
                case 'ai_assistant':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AIChatPage(role: 'admin'),
                    ),
                  );
                  break;
                case 'check_update':
                  AppUpdateChecker.of(context)
                      ?.checkForUpdate(showResult: true);
                  break;
                case 'logout':
                  // Sign out of the Firebase Auth session and clear the
                  // school context first — otherwise authStateChanges()
                  // still reports the user as "logged in", and the next
                  // time the app opens it jumps straight back into this
                  // admin dashboard instead of the Role Selector
                  // (settings_page.dart's _logout() follows this same
                  // pattern).
                  await FirebaseAuth.instance.signOut();
                  SchoolContext.clear();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginPage()),
                      (route) => false,
                    );
                  }
                  break;
              }
            },
            itemBuilder: (context) => const [
              // Notification-related actions grouped first, ordered by
              // audience reach (all-school notice before the narrower
              // teacher notice).
              PopupMenuItem(
                value: 'notifications',
                child: ListTile(
                  leading: Icon(Icons.campaign),
                  title: Text("Manage Notifications"),
                ),
              ),
              PopupMenuItem(
                value: 'teacher_notifications',
                child: ListTile(
                  leading: Icon(Icons.groups_2),
                  title: Text("Teacher Notifications"),
                ),
              ),
              // AI Assistant: a feature action, placed after notifications.
              PopupMenuItem(
                value: 'ai_assistant',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text("AI Assistant"),
                ),
              ),
              // System/maintenance action, placed just before account
              // actions.
              PopupMenuItem(
                value: 'check_update',
                child: ListTile(
                  leading: Icon(Icons.system_update_alt),
                  title: Text("Check for Update"),
                ),
              ),
              PopupMenuDivider(),
              // Account action (logout) always sits last, separated by a
              // divider, to avoid accidental taps.
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text("Logout", style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('students')
            .where('status', isEqualTo: 'active')
            .snapshots(),
        builder: (context, snapshot) {
          int total = 0, boys = 0, girls = 0;
          if (snapshot.hasData) {
            var docs = snapshot.data!.docs;
            total = docs.length;
            boys = docs
                .where((d) =>
                    (d.data() as Map<String, dynamic>)['gender'] == 'Male')
                .length;
            girls = docs
                .where((d) =>
                    (d.data() as Map<String, dynamic>)['gender'] == 'Female')
                .length;
          }

          return Column(
            children: [
              const SubscriptionBanner(),
              StreamBuilder<QuerySnapshot>(
                stream: schoolCollection('notifications')
                    .orderBy('createdAt', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, notifSnapshot) {
                  if (!notifSnapshot.hasData) return const SizedBox.shrink();
                  final texts = notifSnapshot.data!.docs
                      .map((d) =>
                          (d.data() as Map<String, dynamic>)['text']
                              as String? ??
                          '')
                      .where((t) => t.trim().isNotEmpty)
                      .toList();
                  return NotificationTickerBar(notifications: texts);
                },
              ),
              Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.teal[700],
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // Reads the live school name from the 'schoolName'
                    // field of the settings/global doc (set via
                    // Settings > School Name) — falls back to "AEP" if
                    // it hasn't been set.
                    StreamBuilder<DocumentSnapshot>(
                      stream: schoolCollection('settings')
                          .doc('global')
                          .snapshots(),
                      builder: (context, settingsSnapshot) {
                        String schoolName = "AEP";
                        if (settingsSnapshot.hasData &&
                            settingsSnapshot.data!.exists) {
                          var settingsData = settingsSnapshot.data!.data()
                              as Map<String, dynamic>;
                          String? name = settingsData['schoolName'];
                          if (name != null && name.trim().isNotEmpty) {
                            schoolName = name.trim();
                          }
                        }
                        return Text("Welcome, Admin $schoolName",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold));
                      },
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statItem("Total", "$total"),
                        _statItem("Boys", "$boys"),
                        _statItem("Girls", "$girls"),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  // Max width keeps the grid centered on wide desktop/web
                  // screens — otherwise the cards stretch edge-to-edge
                  // across the whole screen (the role selector page is
                  // already constrained the same way).
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: ResponsiveGrid(
                  children: [
                    // --- Most frequently used, day-to-day ---
                    _dashboardCard(context, Icons.app_registration, "Admission",
                        Colors.purple),
                    _dashboardCard(
                        context, Icons.people, "Students", Colors.blue),
                    _dashboardCard(context, Icons.how_to_reg, "Attendance",
                        Colors.deepPurple),
                    _dashboardCard(context, Icons.qr_code_scanner,
                        "Live Attendance", Colors.deepPurple),
                    _dashboardCard(context, Icons.payment, "Fee", Colors.green),
                    _dashboardCard(
                        context, Icons.analytics, "Result", Colors.orange),

                    // --- Other everyday academic tools ---
                    _dashboardCard(
                        context, Icons.task_alt, "Home Task", Colors.cyan),
                    _dashboardCard(context, Icons.schedule, "Timetable",
                        Colors.deepOrange),

                    // --- Financial (remaining fee-related items) ---
                    _dashboardCard(context, Icons.receipt_long,
                        "Online Payments", Colors.lightGreen),
                    _dashboardCard(context, Icons.video_call, "Online Classes",
                        Colors.blueAccent),
                    _dashboardCard(
                        context, Icons.money_off, "Expense", Colors.red),
                    _dashboardCard(context, Icons.assignment_turned_in,
                        "Leave Applications", Colors.indigo),
                    _dashboardCard(
                        context, Icons.cake, "Birthdays", Colors.pink),
                    _dashboardCard(context, Icons.badge, "Staff", Colors.brown),

                    // --- Tools / utilities (less frequently used) ---
                    _dashboardCard(
                        context, Icons.quiz, "Ai Paper Maker", Colors.pink),
                    _dashboardCard(context, Icons.credit_card, "Card Generator",
                        Colors.teal),
                    _dashboardCard(context, Icons.folder_shared, "Documents",
                        Colors.deepPurple),
                    _dashboardCard(context, Icons.trending_up, "Profit/Loss",
                        Colors.indigo),
                    // --- Communication / admin actions ---
                    _dashboardCard(context, Icons.report_problem, "Complaints",
                        Colors.deepOrange),
                    _dashboardCard(context, Icons.event_note, "Events",
                        Colors.amber[800]!),
                    _dashboardCard(
                        context, Icons.report, "Reports", Colors.blueGrey),
                    _dashboardCard(context, Icons.phone_android, "App Usage",
                        Colors.pinkAccent),

                    // --- Settings always goes last ---
                    _dashboardCard(
                        context, Icons.settings, "Settings", Colors.grey),
                  ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statItem(String label, String value) => Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      );

  Widget _dashboardCard(
      BuildContext context, IconData icon, String title, Color color) {
    return InkWell(
      onTap: () {
        if (title == "Admission") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const AdmissionPage()));
        } else if (title == "Students") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const ClassSelectionPage()));
        } else if (title == "Ai Paper Maker") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const AiPaperGeneratorPage()));
        } else if (title == "Staff") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const StaffDashboard()));
        } else if (title == "Fee") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const FeeDashboard()));
        } else if (title == "Online Payments") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const FeePaymentVerificationPage()));
        } else if (title == "Reports") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const ReportsPage()));
        } else if (title == "Expense") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const ExpenseDashboard()));
        } else if (title == "Settings") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const SettingsPage()));
        } else if (title == "Result") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const ResultMenuPage()));
        } else if (title == "Profit/Loss") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const ProfitLossPage()));
        } else if (title == "Home Task") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const HomeTaskPage()));
        } else if (title == "Events") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const EventsPage()));
        } else if (title == "Attendance") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const AttendanceSelectionPage()));
        } else if (title == "Card Generator") {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const IdCardGeneratorHubPage()),
          );
        } else if (title == "Timetable") {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const TimetableManagementPage()),
          );
        } else if (title == "Documents") {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const DocumentManagementPage()),
          );
        } else if (title == "App Usage") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AppUsagePage()),
          );
        } else if (title == "Complaints") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const AdminComplaintsPage()));
        } else if (title == "Leave Applications") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const AdminLeaveApplicationsPage()));
        } else if (title == "Birthdays") {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const BirthdayPage()));
        } else if (title == "Live Attendance") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const LiveAttendanceScannerPage()));
        } else if (title == "Online Classes") {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      const OnlineClassesPage(isAdmin: true)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("$title section coming soon!")));
        }
      },
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
