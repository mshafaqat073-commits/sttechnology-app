import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

class TeacherStudentListPage extends StatefulWidget {
  // A teacher can be assigned multiple classes/sections.
  // Each entry: {'class': '6', 'section': 'A'} — section can be empty.
  final List<Map<String, String>> assignedClasses;

  const TeacherStudentListPage({
    super.key,
    required this.assignedClasses,
  });

  @override
  State<TeacherStudentListPage> createState() => _TeacherStudentListPageState();
}

class _TeacherStudentListPageState extends State<TeacherStudentListPage> {
  late Map<String, String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.assignedClasses.isNotEmpty
        ? widget.assignedClasses.first
        : {'class': '', 'section': ''};
  }

  String _labelFor(Map<String, String> a) {
    final section = a['section'] ?? '';
    final cls = a['class'] ?? '';
    return section.isNotEmpty ? "$cls - $section" : cls;
  }

  Query<Map<String, dynamic>> _studentsQuery() {
    Query<Map<String, dynamic>> q = schoolCollection('students')
        .where('class', isEqualTo: _selected['class'])
        .where('status', isEqualTo: 'active');

    final section = _selected['section'] ?? '';
    if (section.isNotEmpty) {
      q = q.where('section', isEqualTo: section);
    }
    return q;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assignedClasses.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Students"),
          backgroundColor: Colors.teal[800],
        ),
        body: const Center(
          child: Text("You have not been assigned any class yet."),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Students - ${_labelFor(_selected)}"),
        backgroundColor: Colors.teal[800],
        actions: widget.assignedClasses.length > 1
            ? [
                PopupMenuButton<Map<String, String>>(
                  icon: const Icon(Icons.class_outlined),
                  tooltip: "Change class",
                  onSelected: (val) => setState(() => _selected = val),
                  itemBuilder: (context) => widget.assignedClasses
                      .map(
                        (a) => PopupMenuItem(
                          value: a,
                          child: Text(_labelFor(a)),
                        ),
                      )
                      .toList(),
                ),
              ]
            : null,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _studentsQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var students = snapshot.data!.docs;
          if (students.isEmpty) {
            return const Center(child: Text("No student found in this class."));
          }

          // Sort by name
          students.sort((a, b) {
            var dataA = a.data();
            var dataB = b.data();
            String nameA = (dataA['name'] ?? '').toString();
            String nameB = (dataB['name'] ?? '').toString();
            return nameA.compareTo(nameB);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: students.length,
            itemBuilder: (context, index) {
              var data = students[index].data();
              String name = data['name'] ?? 'N/A';
              String fatherName = data['fName']?.toString() ?? 'N/A';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.teal.shade100,
                    child: const Icon(Icons.person, color: Colors.teal),
                  ),
                  title: Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text("Father: $fatherName"),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
