import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'notification_bell_icon.dart';
import 'role_selector_page.dart';
import 'notification_ticker_widget.dart';
import 'ai_chat_page.dart';
import 'teacher_events_page.dart';
import 'teacher_timetable_page.dart';
import 'parent_admission_view_page.dart';
import 'parent_documents_page.dart';
import 'parent_fee_history_page.dart';
import 'parent_attendance_page.dart';
import 'parent_result_page.dart';
import 'parent_home_task_page.dart';
import 'parent_id_card_page.dart';
import 'pay_fee_online_page.dart';
import 'school_context.dart';
import 'parent_complaint_page.dart';
import 'parent_leave_application_page.dart';
import 'parent_online_classes_page.dart';
import 'change_pin_dialog.dart';
import 'parent_performance_page.dart';
import 'performance_bar_chart.dart';
import 'app_update_checker.dart';
import 'parent_home_task_page.dart';

/// This dashboard opens after Parent login — every student (sibling)
/// linked to that phone number is listed here.
///
/// Tapping a child's card opens a quick menu: Admission Form, Attendance,
/// Result, Home Task (diary/homework/message), ID Card, and Timetable —
/// each reads live data straight from its matching admin/teacher
/// collection (students, attendance, results, school_diary,
/// school_homework, special_messages, timetable).
class ParentDashboard extends StatelessWidget {
  final List<DocumentSnapshot> children;

  const ParentDashboard({super.key, required this.children});

  // These keys exist in the fee_structures document but aren't actual fee
  // amounts — never include them in the total.
  // (must match _nonFeeKeys in pay_fee_page.dart)
  static const Set<String> _nonFeeKeys = {
    'studentId',
    'name',
    'fName',
    'class',
    'section',
    'updatedAt',
    'docId',
  };

  // Sums all fee fields from the fee_structures doc + adds the student's
  // 'dues' field (previous outstanding amount) to get the actual current
  // dues — exactly the same calculation PayFeePage does on the admin side
  // (_calculateDues), so the number matches in both places.
  double _computeTotalDues(
      Map<String, dynamic> studentData, Map<String, dynamic>? feeData) {
    double previousDues =
        double.tryParse(studentData['dues']?.toString() ?? '0') ?? 0;

    if (feeData == null) return previousDues;

    double feeTotal = 0;
    for (var key in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      feeTotal += double.tryParse(feeData[key]?.toString() ?? '0') ?? 0;
    }

    return feeTotal + previousDues;
  }

  Future<void> _changePin(BuildContext context) async {
    final currentPin =
        (children.first.data() as Map<String, dynamic>)['parentPin']
                ?.toString() ??
            '';

    await showChangePinDialog(
      context: context,
      currentPin: currentPin,
      onChangePin: (newPin) async {
        // Every sibling shares the same Login ID + PIN, so update the PIN
        // on ALL of this family's student records together — otherwise
        // some siblings would keep working with the old PIN.
        var batch = FirebaseFirestore.instance.batch();
        for (var doc in children) {
          batch.update(doc.reference, {'parentPin': newPin});
        }
        await batch.commit();
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

  void _openChildMenu(BuildContext context, String studentId,
      Map<String, dynamic> data, double dues) {
    final name = data['name'] ?? 'N/A';
    final className = (data['class'] ?? 'N/A').toString();
    final section = (data['section'] ?? '').toString().trim();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.app_registration,
                        color: Colors.purple),
                    title: const Text("Admission Form"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentAdmissionViewPage(
                            studentId: studentId,
                            data: data,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.how_to_reg, color: Colors.deepPurple),
                    title: const Text("Attendance"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentAttendancePage(
                            studentId: studentId,
                            studentName: name,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.analytics, color: Colors.orange),
                    title: const Text("Result"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentResultPage(
                            studentId: studentId,
                            studentName: name,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.task_alt, color: Colors.cyan),
                    title:
                        const Text("Home Task (Diary / Homework / Messages)"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentHomeTaskPage(
                            studentId: studentId,
                            className: className,
                            section: section,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.insights, color: Colors.indigo),
                    title: const Text("Overall Performance"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentPerformancePage(
                            studentId: studentId,
                            studentName: name,
                            studentData: data,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.badge, color: Colors.brown),
                    title: const Text("ID Card"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentIdCardPage(
                              studentData: data, studentId: studentId),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.schedule, color: Colors.deepOrange),
                    title: const Text("Timetable"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherTimetablePage(
                            assignedClasses: [
                              {'class': className, 'section': section},
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.history, color: Colors.teal),
                    title: const Text("Fee History"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentFeeHistoryPage(
                            studentId: studentId,
                            studentName: name,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.payment, color: Colors.green),
                    title: const Text("Pay Fee Online"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PayFeeOnlinePage(
                            studentId: studentId,
                            studentName: name,
                            className: className,
                            section: section,
                            currentDues: dues,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.video_call, color: Colors.blueAccent),
                    title: const Text("Online Classes"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentOnlineClassesPage(
                            className: className,
                            section: section,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.report_problem,
                        color: Colors.deepOrange),
                    title: const Text("Complaint to Principal"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentComplaintPage(
                            studentId: studentId,
                            studentName: name,
                            className: className,
                            section: section,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_shared,
                        color: Colors.deepPurple),
                    title: const Text("Documents"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentDocumentsPage(
                            studentId: studentId,
                            studentName: name,
                            className: className,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.assignment_turned_in,
                        color: Colors.indigo),
                    title: const Text("Leave Application"),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentLeaveApplicationPage(
                            studentId: studentId,
                            studentName: name,
                            className: className,
                            section: section,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _quickAction(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 90,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.indigo[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.indigo[100]!),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.indigo[700]),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo[700])),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text("Parent Dashboard"),
        backgroundColor: Colors.indigo[700],
        actions: [
          NotificationBellIcon(
            uids: children.map((d) => d.id).toList(),
          ),
          // Less-used actions collapsed into a single 3-dot menu so the
          // AppBar stays uncluttered.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: "More Options",
            onSelected: (value) {
              switch (value) {
                case 'update':
                  final updateChecker = AppUpdateChecker.of(context);
                  debugPrint(
                      '[UpdateButton] AppUpdateChecker.of(context) is ${updateChecker == null ? "NULL (ancestor not found!)" : "found OK"}');
                  if (updateChecker == null) {
                    // Without this, a null ancestor meant the button tap
                    // silently did nothing — no dialog, no snackbar, no
                    // error. Fall back to a local ScaffoldMessenger so the
                    // user always gets some feedback from the tap.
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Update checker is not ready yet — please try again in a moment.',
                        ),
                      ),
                    );
                  } else {
                    updateChecker.checkForUpdate(showResult: true);
                  }
                  break;
                case 'pin':
                  _changePin(context);
                  break;
                case 'ai':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AIChatPage(role: 'parent')),
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
          StreamBuilder<QuerySnapshot>(
            stream: schoolCollection('notifications')
                .orderBy('createdAt', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, notifSnapshot) {
              if (!notifSnapshot.hasData) return const SizedBox.shrink();
              final texts = notifSnapshot.data!.docs
                  .map((d) =>
                      (d.data() as Map<String, dynamic>)['text'] as String? ??
                      '')
                  .where((t) => t.trim().isNotEmpty)
                  .toList();
              return NotificationTickerBar(notifications: texts);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _quickAction(context, Icons.event_note, "Events", () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const TeacherEventsPage()),
                  );
                }),
                const SizedBox(width: 12),
                _quickAction(context, Icons.auto_awesome, "AI Assistant", () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AIChatPage(role: 'parent')),
                  );
                }),
              ],
            ),
          ),
          _ChildrenPerformanceOverview(children: children),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                children.length > 1 ? "Your Children" : "Your Child",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: Center(
              // Max width to keep the list centered on wide desktop/web
              // screens — otherwise cards would stretch edge-to-edge
              // (the role selector page is already constrained the same
              // way).
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: children.length,
                  itemBuilder: (context, index) {
                    var data = children[index].data() as Map<String, dynamic>;
                    String studentId = children[index].id;
                    String name = data['name'] ?? 'N/A';
                    String className = data['class'] ?? 'N/A';
                    String section = (data['section'] ?? '').toString().trim();
                    String imageUrl = data['imageUrl'] ?? '';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: StreamBuilder<DocumentSnapshot>(
                        // We listen to fee_structures live, so whenever admin
                        // sets/edits the fee, dues update here instantly —
                        // we don't depend only on student.dues (which is just
                        // the previous outstanding amount).
                        stream: schoolCollection('fee_structures')
                            .doc(studentId)
                            .snapshots(),
                        builder: (context, feeSnapshot) {
                          Map<String, dynamic>? feeData;
                          if (feeSnapshot.hasData && feeSnapshot.data!.exists) {
                            feeData = feeSnapshot.data!.data()
                                as Map<String, dynamic>;
                          }
                          double dues = _computeTotalDues(data, feeData);

                          return ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.indigo.shade100,
                              backgroundImage: imageUrl.isNotEmpty
                                  ? NetworkImage(imageUrl)
                                  : null,
                              child: imageUrl.isEmpty
                                  ? const Icon(Icons.person,
                                      color: Colors.indigo)
                                  : null,
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              section.isNotEmpty
                                  ? "Class: $className - $section"
                                  : "Class: $className",
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  dues > 0
                                      ? "Dues: Rs. ${dues.toStringAsFixed(0)}"
                                      : "No Dues",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          dues > 0 ? Colors.red : Colors.green),
                                ),
                              ],
                            ),
                            onTap: () =>
                                _openChildMenu(context, studentId, data, dues),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown at the top of the Parent Dashboard, above the children list.
/// Combines each child's attendance % (attendance collection) and
/// academic % (results collection) into one overall performance figure,
/// then renders it as a bar chart — one bar per child — so a parent with
/// more than one child can compare all of them at a glance. Tapping a
/// child's name opens the same ParentPerformancePage used from the
/// child menu, for the full breakdown (results, fee dates, attendance).
class _ChildrenPerformanceOverview extends StatefulWidget {
  final List<DocumentSnapshot> children;

  const _ChildrenPerformanceOverview({required this.children});

  @override
  State<_ChildrenPerformanceOverview> createState() =>
      _ChildrenPerformanceOverviewState();
}

class _ChildrenPerformanceOverviewState
    extends State<_ChildrenPerformanceOverview> {
  late Future<List<PerformanceBarData>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PerformanceBarData>> _load() async {
    final List<PerformanceBarData> bars = [];
    for (var doc in widget.children) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? 'N/A').toString();

      final attendanceSnap = await schoolCollection('attendance')
          .where('studentId', isEqualTo: doc.id)
          .get();
      int present = 0;
      for (var a in attendanceSnap.docs) {
        if ((a.data())['status']?.toString() == 'Present') {
          present++;
        }
      }
      final attendancePercent = attendanceSnap.docs.isNotEmpty
          ? (present / attendanceSnap.docs.length) * 100
          : 0.0;

      final resultsSnap = await schoolCollection('results')
          .where('studentId', isEqualTo: doc.id)
          .get();
      double academicPercent = 0;
      if (resultsSnap.docs.isNotEmpty) {
        double sum = 0;
        for (var r in resultsSnap.docs) {
          sum +=
              double.tryParse((r.data())['percentage']?.toString() ?? '0') ?? 0;
        }
        academicPercent = sum / resultsSnap.docs.length;
      }

      final hasAttendance = attendanceSnap.docs.isNotEmpty;
      final hasResults = resultsSnap.docs.isNotEmpty;
      double overall;
      if (hasAttendance && hasResults) {
        overall = (attendancePercent + academicPercent) / 2;
      } else if (hasAttendance) {
        overall = attendancePercent;
      } else {
        overall = academicPercent;
      }

      bars.add(PerformanceBarData(
        label: name,
        value: overall,
        color: PerformanceRemark.overall(attendancePercent, academicPercent,
                hasResults: hasResults, hasAttendance: hasAttendance)
            .color,
      ));
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.indigo[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.indigo[100]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: Colors.indigo[700]),
                const SizedBox(width: 8),
                Text(
                  widget.children.length > 1
                      ? "Children's Performance"
                      : "Performance",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo[700]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<PerformanceBarData>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return PerformanceBarChart(
                  bars: snapshot.data ?? const [],
                  maxValue: 100,
                  valueSuffix: '%',
                  height: 150,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
