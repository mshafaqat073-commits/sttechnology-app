import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_helper.dart';
import 'school_context.dart';

class TeacherAttendancePage extends StatefulWidget {
  // A teacher can be assigned multiple classes/sections.
  // Each entry: {'class': '6', 'section': 'A'} — section can be empty.
  final List<Map<String, String>> assignedClasses;

  const TeacherAttendancePage({
    super.key,
    required this.assignedClasses,
  });

  @override
  State<TeacherAttendancePage> createState() => _TeacherAttendancePageState();
}

class _TeacherAttendancePageState extends State<TeacherAttendancePage> {
  DateTime _selectedDate = DateTime.now();
  String get formattedDate => _selectedDate.toString().split(' ')[0];

  late Map<String, String> _selectedClass;

  Map<String, String> studentAttendanceMap = {};
  bool _isLoadingStudents = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.assignedClasses.isNotEmpty
        ? widget.assignedClasses.first
        : {'class': '', 'section': ''};
    if (widget.assignedClasses.isNotEmpty) {
      _loadStudentAttendanceForDate();
    } else {
      _isLoadingStudents = false;
    }
  }

  String get _currentClass => _selectedClass['class'] ?? '';
  String get _currentSection => _selectedClass['section'] ?? '';

  String _labelFor(Map<String, String> a) {
    final section = a['section'] ?? '';
    final cls = a['class'] ?? '';
    return section.isNotEmpty ? "$cls - $section" : cls;
  }

  Query<Map<String, dynamic>> _studentsQuery() {
    Query<Map<String, dynamic>> q = schoolCollection('students')
        .where('class', isEqualTo: _currentClass);
    if (_currentSection.isNotEmpty) {
      q = q.where('section', isEqualTo: _currentSection);
    }
    return q;
  }

  void _onClassChanged(Map<String, String> newSelection) {
    setState(() {
      _selectedClass = newSelection;
      studentAttendanceMap.clear();
    });
    _loadStudentAttendanceForDate();
  }

  Future<void> _pickDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        studentAttendanceMap.clear();
      });
      _loadStudentAttendanceForDate();
    }
  }

  // Loads the existing attendance for this date for the currently
  // selected class/section's students (if it was already marked),
  // otherwise defaults to 'Present'.
  Future<void> _loadStudentAttendanceForDate() async {
    setState(() => _isLoadingStudents = true);

    try {
      // Previously this made a separate doc().get() call per student
      // (N+1 pattern). Now the class's students and that day's attendance
      // are fetched in just 2 parallel queries — the result is exactly
      // the same, only the loading is faster.
      final results = await Future.wait([
        _studentsQuery().get(),
        schoolCollection('attendance')
            .where('date', isEqualTo: formattedDate)
            .get(),
      ]);
      var studentsSnapshot = results[0];
      var attendanceSnapshot = results[1];

      Map<String, String> attendanceByStudentId = {
        for (var doc in attendanceSnapshot.docs)
          (doc.data()['studentId'] as String? ?? doc.id):
              (doc.data()['status'] as String? ?? 'Present')
      };

      Map<String, String> tempMap = {};

      for (var doc in studentsSnapshot.docs) {
        String studentId = doc.id;
        tempMap[studentId] = attendanceByStudentId[studentId] ?? 'Present';
      }

      if (mounted) {
        setState(() {
          studentAttendanceMap = tempMap;
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  Future<void> _saveAttendance() async {
    setState(() => _isSaving = true);
    try {
      var firestore = FirebaseFirestore.instance;
      WriteBatch batch = firestore.batch();

      for (var entry in studentAttendanceMap.entries) {
        String studentId = entry.key;
        String status = entry.value;
        // NOTE: docId is based only on date + studentId — kept consistent
        // with the admin attendance page and QR scanner, so that each
        // student gets only ONE attendance record per day.
        String docId = "${formattedDate}_$studentId";

        var docRef = schoolCollection('attendance').doc(docId);
        batch.set(
          docRef,
          {
            'class': _currentClass,
            'section': _currentSection,
            'studentId': studentId,
            'status': status,
            'date': formattedDate,
            'timestamp': Timestamp.now(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      // Send a notification to students marked 'Absent' today.
      final absentIds = studentAttendanceMap.entries
          .where((e) => e.value == 'Absent')
          .map((e) => e.key)
          .toList();
      if (absentIds.isNotEmpty) {
        await _notifyAbsentStudents(absentIds);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Attendance for $formattedDate Saved Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Pulls the fcmToken for students marked Absent from Firestore and
  // sends them a notification. FieldPath.documentId whereIn has a limit
  // of 30 ids/query, so the ids are split into chunks.
  Future<void> _notifyAbsentStudents(List<String> studentIds) async {
    try {
      final targets = <Map<String, String?>>[];
      for (var i = 0; i < studentIds.length; i += 30) {
        final chunk = studentIds.sublist(
            i, i + 30 > studentIds.length ? studentIds.length : i + 30);
        final snap = await schoolCollection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (var d in snap.docs) {
          targets.add({'id': d.id, 'token': d.data()['fcmToken'] as String?});
        }
      }

      await NotificationHelper.sendToMultiple(
        targets: targets,
        toRole: 'student',
        title: 'Attendance: Absent',
        body: 'Today ($formattedDate) your child is absent.',
        type: 'attendance',
      );
    } catch (e) {
      debugPrint('Notify absent students failed: $e');
    }
  }

  Widget _statusButton(
      String studentId, String statusLabel, Color color, String currentStatus) {
    bool isSelected = currentStatus == statusLabel;
    return InkWell(
      onTap: () {
        setState(() {
          studentAttendanceMap[studentId] = statusLabel;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          statusLabel,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assignedClasses.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Attendance"),
          backgroundColor: Colors.teal[800],
        ),
        body: SafeArea(child: const Center(
          child: Text("No class assigned contact administration."),
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Attendance - ${_labelFor(_selectedClass)}",
                style: const TextStyle(fontSize: 17)),
            Text("Date: $formattedDate",
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.teal[800],
        actions: [
          if (widget.assignedClasses.length > 1)
            PopupMenuButton<Map<String, String>>(
              icon: const Icon(Icons.class_outlined),
              tooltip: "Change class",
              onSelected: _onClassChanged,
              itemBuilder: (context) => widget.assignedClasses
                  .map(
                    (a) => PopupMenuItem(
                      value: a,
                      child: Text(_labelFor(a)),
                    ),
                  )
                  .toList(),
            ),
          IconButton(
            icon: const Icon(Icons.calendar_month, size: 28),
            onPressed: () => _pickDate(context),
            tooltip: "Change Date",
          ),
        ],
      ),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: _isLoadingStudents
                  ? const Center(child: CircularProgressIndicator())
                  : studentAttendanceMap.isEmpty
                      ? const Center(
                          child: Text("No students found in this class."))
                      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _studentsQuery().snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            var students = snapshot.data!.docs;

                            if (students.isEmpty) {
                              return const Center(
                                  child:
                                      Text("No students found in this class."));
                            }

                            return ListView.builder(
                              itemCount: students.length,
                              itemBuilder: (context, index) {
                                var studentDoc = students[index];
                                var studentData = studentDoc.data();
                                String studentId = studentDoc.id;
                                String studentName =
                                    studentData['name'] ?? 'Unknown';
                                String rollNo = studentData['rollNo'] ?? 'N/A';

                                String currentStatus =
                                    studentAttendanceMap[studentId] ??
                                        'Present';

                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(studentName,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16)),
                                            Text("Roll No: $rollNo",
                                                style: const TextStyle(
                                                    color: Colors.grey)),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            _statusButton(studentId, 'Present',
                                                Colors.green, currentStatus),
                                            const SizedBox(width: 5),
                                            _statusButton(studentId, 'Absent',
                                                Colors.red, currentStatus),
                                            const SizedBox(width: 5),
                                            _statusButton(studentId, 'Leave',
                                                Colors.orange, currentStatus),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.teal[800]),
                onPressed: _isSaving ? null : _saveAttendance,
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        "SAVE ATTENDANCE FOR $formattedDate",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      )),
    );
  }
}
