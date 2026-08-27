import 'package:flutter/material.dart';
import 'pending_dues_report_page.dart';
import 'fee_collection_report_page.dart';
import 'student_attendance_report_page.dart';
import 'student_attendance_monthly_report_page.dart';
import 'active_students_report_page.dart';
import 'staff_attendance_report_page.dart';
import 'staff_attendance_monthly_report_page.dart';
import 'staff_directory_report_page.dart';
import 'expense_report_page.dart';
import 'profit_loss_report_page.dart';
import 'balance_sheet_page.dart';
import 'zero_fee_students_page.dart';
import 'TeacherAttendanceReportSeprate.dart';
import 'StudentAttendanceReportSeprate.dart';
import 'TodayCollectionReport.dart';
import 'MonthCollectionReport.dart';
import 'student_report_search_page.dart';
import 'admin_student_performance_report_page.dart';
import 'admin_teacher_performance_report_page.dart';
import 'responsive_grid.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("School Reports Dashboard"),
        backgroundColor: Colors.teal[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // --- SECTION 1: STUDENTS REPORTS ---
            const Text(
              "Students Reports",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal),
            ),
            const SizedBox(height: 10),
            ResponsiveGrid(
              padding: EdgeInsets.zero,
              spacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              aspectRatio: 2.5,
              children: [
                _reportButton(
                  context,
                  title: "Pending Dues",
                  icon: Icons.money_off,
                  color: Colors.red.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PendingDuesReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Fee Collection",
                  icon: Icons.receipt_long,
                  color: Colors.green.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const FeeCollectionReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Student Attendance",
                  icon: Icons.how_to_reg,
                  color: Colors.blue.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const StudentAttendanceReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Class Attendance (Monthly)",
                  icon: Icons.calendar_month,
                  color: Colors.blue.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const StudentAttendanceMonthlyReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Search Student Report",
                  icon: Icons.search,
                  color: Colors.blue.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const StudentReportSearchPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Active Students List",
                  icon: Icons.school,
                  color: Colors.teal.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const ActiveStudentsReportPage()),
                    );
                  },
                ),
                // --- Nayy Collection Buttons Added Here ---
                const TodayCollectionReport(),
                const MonthCollectionReport(),
                _reportButton(
                  context,
                  title: "Student Performance",
                  icon: Icons.insights,
                  color: Colors.deepOrange.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const AdminStudentPerformanceReportPage()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 25),

            // --- SECTION 2: INDIVIDUAL SEPARATE REPORTS ---
            const Text(
              "Attendance Separate Reports",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: StudentAttendanceReportSeprate()),
                const SizedBox(width: 10),
                const Expanded(child: TeacherAttendanceReportSeprate()),
              ],
            ),

            const SizedBox(height: 25),

            // --- SECTION 3: TEACHERS / STAFF REPORTS ---
            const Text(
              "Staff & Teachers Reports",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple),
            ),
            const SizedBox(height: 10),
            ResponsiveGrid(
              padding: EdgeInsets.zero,
              spacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              aspectRatio: 2.5,
              children: [
                _reportButton(
                  context,
                  title: "Staff Attendance",
                  icon: Icons.co_present,
                  color: Colors.deepPurple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const TeacherAttendanceReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Staff Attendance (Monthly)",
                  icon: Icons.calendar_month,
                  color: Colors.deepPurple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const StaffAttendanceMonthlyReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Staff Directory",
                  icon: Icons.badge,
                  color: Colors.indigo,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const StaffDirectoryReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Teacher Performance",
                  icon: Icons.insights,
                  color: Colors.deepPurple.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const AdminTeacherPerformanceReportPage()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 25),

            // --- SECTION 4: FINANCIAL REPORTS ---
            const Text(
              "Financial Reports",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown),
            ),
            const SizedBox(height: 10),
            ResponsiveGrid(
              padding: EdgeInsets.zero,
              spacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              aspectRatio: 2.5,
              children: [
                _reportButton(
                  context,
                  title: "Expense Report",
                  icon: Icons.receipt,
                  color: Colors.redAccent.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ExpenseReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Profit & Loss",
                  icon: Icons.account_balance_wallet,
                  color: Colors.blueGrey.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ProfitLossReportPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "Balance Sheet",
                  icon: Icons.account_balance,
                  color: Colors.brown.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const BalanceSheetPage()),
                    );
                  },
                ),
                _reportButton(
                  context,
                  title: "0 Monthly Fee Students",
                  icon: Icons.money_off,
                  color: Colors.red.shade700,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ZeroFeeStudentsPage()),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Report Button Design Helper
  Widget _reportButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
