import 'package:flutter/material.dart';
import 'teacher_enter_result_page.dart';
import 'teacher_view_result_page.dart';

// Teacher-only version of the result menu. Unlike the admin's
// ResultMenuPage, this always restricts Enter/View result access to the
// teacher's own assigned class/section list.
class TeacherResultMenuPage extends StatelessWidget {
  final List<Map<String, String>> assignedClasses;

  const TeacherResultMenuPage({super.key, required this.assignedClasses});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Results")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ListTile(
            leading: const Icon(Icons.add_box, size: 40, color: Colors.blue),
            title: const Text("Enter New Result", style: TextStyle(fontSize: 18)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    TeacherEnterResultPage(allowedClasses: assignedClasses),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.list_alt, size: 40, color: Colors.green),
            title: const Text("View & Print Results", style: TextStyle(fontSize: 18)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    TeacherViewResultPage(allowedClasses: assignedClasses),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
