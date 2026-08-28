import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'school_context.dart';
import 'notification_service.dart';
import 'notification_bell_icon.dart';
import 'teacher_notices_page.dart';
import 'role_selector_page.dart';
import 'teacher_attendance_page.dart';
import 'teacher_student_list_page.dart';
import 'teacher_result_menu_page.dart';
import 'teacher_homework_page.dart';
import 'teacher_events_page.dart';
import 'ai_paper_generator_page.dart';
import 'teacher_own_id_card_page.dart';
import 'teacher_timetable_page.dart';
import 'ai_chat_page.dart';
import 'responsive_grid.dart';
import 'online_classes_page.dart';
import 'live_attendance_scanner_page.dart';
import 'change_pin_dialog.dart';
import 'teacher_performance_page.dart';
import 'app_update_checker.dart';

class TeacherDashboard extends StatelessWidget {
  final String staffDocId;
  final Map<String, dynamic> staffData;

  const TeacherDashboard({
    super.key,
    required this.staffDocId,
    required this.staffData,
  });

  Future<void> _changePin(BuildContext context) async {
    final currentPin = staffData['staffPin']?.toString() ?? '';

    await showChangePinDialog(
      context: context,
      currentPin: currentPin,
      onChangePin: (newPin) async {
        await schoolCollection('staff')
            .doc(staffDocId)
            .update({'staffPin': newPin});
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Do you want logout?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Logout", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await NotificationService().clearToken();
      await AuthService().signOut();
      SchoolContext.clear();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const RoleSelectorPage()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String name = staffData['name'] ?? 'Teacher';
    String designation = staffData['designation'] ?? 'Teacher';
    String contact = staffData['contact'] ?? 'N/A';
    // New format: a list of {class, section} maps. Falls back to the old
    // single assignedClass/assignedSection fields for older staff records.
    List<Map<String, String>> assignedClasses = [];
    if (staffData['assignedClasses'] is List) {
      assignedClasses = List<dynamic>.from(staffData['assignedClasses'] as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } else if (staffData['assignedClass'] != null) {
      assignedClasses = [
        {
          'class': staffData['assignedClass'].toString(),
          'section': staffData['assignedSection']?.toString() ?? '',
        }
      ];
    }

    String classLabel = assignedClasses.isEmpty
        ? "No class assigned"
        : assignedClasses
            .map((a) => a['section']!.isNotEmpty
                ? "${a['class']} - ${a['section']}"
                : a['class']!)
            .join(", ");

    return Scaffold(
      appBar: AppBar(
        // Dashboard opens directly (via pushAndRemoveUntil), so there's no
        // previous route for the default back-arrow to pop to — so we've
        // added our own back arrow that goes back to the Login/Role
        // Selector screen (signing out too, so it doesn't auto-route back
        // to this same dashboard).
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: "Back to Login",
          onPressed: () => _logout(context),
        ),
        title: const Text("Teacher Dashboard"),
        backgroundColor: Colors.teal[800],
        actions: [
          NotificationBellIcon(uids: [staffDocId]),
          // Less-used actions collapsed into a single 3-dot menu so the
          // AppBar stays uncluttered.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: "More Options",
            onSelected: (value) {
              switch (value) {
                case 'update':
                  AppUpdateChecker.of(context)
                      ?.checkForUpdate(showResult: true);
                  break;
                case 'pin':
                  _changePin(context);
                  break;
                case 'ai':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const AIChatPage(role: 'teacher')),
                  );
                  break;
                case 'logout':
                  _logout(context);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'update',
                child: ListTile(
                  leading: Icon(Icons.system_update_alt),
                  title: Text("Check for Update"),
                ),
              ),
              PopupMenuItem(
                value: 'pin',
                child: ListTile(
                  leading: Icon(Icons.password),
                  title: Text("Change PIN"),
                ),
              ),
              PopupMenuItem(
                value: 'ai',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome, color: Colors.orange),
                  title: Text("AI Assistant"),
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text("Logout"),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  // Max width to keep the content centered on wide
                  // desktop/web screens — otherwise cards would stretch
                  // edge-to-edge, unlike the role selector page which is
                  // already constrained this way.
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.teal.shade100,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : "T",
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade800),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                Text(designation,
                                    style:
                                        TextStyle(color: Colors.grey.shade600)),
                                Text(contact,
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(classLabel,
                                    style: TextStyle(
                                        color: Colors.teal.shade800,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Quick Actions",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ResponsiveGrid(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    spacing: 12,
                    children: [
                      _DashboardTile(
                        icon: Icons.groups,
                        label: "Student List",
                        onTap: () {
                          if (assignedClasses.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    "No class assigned contact administration."),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherStudentListPage(
                                assignedClasses: assignedClasses,
                              ),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.checklist,
                        label: "Attendance",
                        onTap: () {
                          if (assignedClasses.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    "No class assigned contact administration."),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherAttendancePage(
                                assignedClasses: assignedClasses,
                              ),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.grade,
                        label: "Marks",
                        onTap: () {
                          if (assignedClasses.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    "No class assigned contact administration."),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherResultMenuPage(
                                assignedClasses: assignedClasses,
                              ),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.assignment,
                        label: "Homework",
                        onTap: () {
                          if (assignedClasses.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    "No class assigned contact administration."),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherHomeworkPage(
                                assignedClasses: assignedClasses,
                                teacherName: name,
                              ),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.qr_code_scanner,
                        label: "Live Attendance",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LiveAttendanceScannerPage(),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.insights,
                        label: "My Performance",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherPerformancePage(
                                staffDocId: staffDocId,
                                staffData: staffData,
                                assignedClasses: assignedClasses,
                              ),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.schedule,
                        label: "Timetable",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherTimetablePage(
                                assignedClasses: assignedClasses,
                              ),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.video_call,
                        label: "Online Classes",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OnlineClassesPage(
                                createdByName: name,
                                assignedClasses: assignedClasses,
                              ),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.event,
                        label: "Events",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TeacherEventsPage(),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.campaign,
                        label: "Notices",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TeacherNoticesPage(),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.auto_awesome,
                        label: "AI Paper Generator",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AiPaperGeneratorPage(),
                            ),
                          );
                        },
                      ),
                      _DashboardTile(
                        icon: Icons.badge,
                        label: "My ID Card",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherOwnIdCardPage(
                                staffData: staffData,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DashboardTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.teal[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.teal[100]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.teal[800]),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: Colors.teal[800], fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
