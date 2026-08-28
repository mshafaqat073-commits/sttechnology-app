import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_helper.dart';
import 'school_context.dart';

class AttendancePage extends StatefulWidget {
  final int initialTabIndex; // 0 = Students, 1 = Teachers
  const AttendancePage({super.key, this.initialTabIndex = 0});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Selected Date Variable (Default is Today)
  DateTime _selectedDate = DateTime.now();
  String get formattedDate => _selectedDate.toString().split(' ')[0];

  // --- Student Variables ---
  String? selectedClass;
  String? selectedSection; // null = All Sections
  List<String> classesList = [];
  List<String> sectionsList = [];
  bool _isLoadingClasses = true;

  Map<String, String> studentAttendanceMap = {};
  Map<String, String> teacherAttendanceMap = {};

  bool _isSavingStudents = false;
  bool _isSavingTeachers = false;
  bool _isLoadingStudents = false;
  bool _isLoadingTeachers = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTabIndex);

    // Load initial data
    _fetchClasses();
    _loadTeacherAttendanceForDate();
  }

  // Firestore se active students ki saari classes nikal kar dropdown ke liye
  // list banata hai — is se admission form se add kiya gaya har naya/custom
  // class yahan bhi automatically show ho jata hai.
  Future<void> _fetchClasses() async {
    try {
      var snapshot = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();

      Set<String> classSet = {};
      for (var doc in snapshot.docs) {
        String cls = doc.data()['class']?.toString() ?? '';
        if (cls.isNotEmpty && cls != 'Not Selected') classSet.add(cls);
      }

      if (mounted) {
        setState(() {
          classesList = classSet.toList()..sort();
          _isLoadingClasses = false;
        });
      }
    } catch (e) {
      print("Error fetching classes: $e");
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  // Selected class ke andar mojood sections nikalta hai (dropdown ke liye)
  Future<void> _fetchSectionsForClass(String className) async {
    try {
      var snapshot = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .where('class', isEqualTo: className)
          .get();

      Set<String> sectionSet = {};
      for (var doc in snapshot.docs) {
        String sec = doc.data()['section']?.toString() ?? '';
        if (sec.isNotEmpty && sec != 'Not Selected') sectionSet.add(sec);
      }

      if (mounted) {
        setState(() {
          sectionsList = sectionSet.toList()..sort();
        });
      }
    } catch (e) {
      print("Error fetching sections: $e");
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Date Picker Function
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
        teacherAttendanceMap.clear();
      });

      if (selectedClass != null) {
        _loadStudentAttendanceForClassAndDate();
      }
      _loadTeacherAttendanceForDate();
    }
  }

  // --- Load Students Attendance & List ---
  Future<void> _loadStudentAttendanceForClassAndDate() async {
    if (selectedClass == null) return;
    setState(() => _isLoadingStudents = true);

    try {
      Query<Map<String, dynamic>> studentsQuery = schoolCollection('students')
          .where('class', isEqualTo: selectedClass);
      if (selectedSection != null) {
        studentsQuery =
            studentsQuery.where('section', isEqualTo: selectedSection);
      }
      // Students aur us din ki attendance dono ek sath (parallel) mangwate
      // hain — pehle har student ke liye alag se doc().get() call hoti thi
      // (N+1 pattern), jo 40 students wali class mein 40 sequential
      // network round-trips banati thi. Ab sirf 2 queries total lagti hain.
      final results = await Future.wait([
        studentsQuery.get(),
        schoolCollection('attendance')
            .where('date', isEqualTo: formattedDate)
            .get(),
      ]);
      var studentsSnapshot = results[0];
      var attendanceSnapshot = results[1];

      // Us din ki saari attendance ek dafa map mein daal lete hain taake
      // aage lookup O(1) ho, dobara query na karni pare
      Map<String, String> attendanceByStudentId = {
        for (var doc in attendanceSnapshot.docs)
          (doc.data()['studentId'] as String? ?? doc.id): (doc.data()['status']
                  as String? ??
              'Present')
      };

      Map<String, String> tempMap = {};

      for (var doc in studentsSnapshot.docs) {
        String studentId = doc.id;
        tempMap[studentId] = attendanceByStudentId[studentId] ?? 'Present';
      }

      setState(() {
        studentAttendanceMap = tempMap;
        _isLoadingStudents = false;
      });
    } catch (e) {
      print("Error loading student attendance: $e");
      setState(() => _isLoadingStudents = false);
    }
  }

  // --- Load Teachers Attendance ---
  Future<void> _loadTeacherAttendanceForDate() async {
    setState(() => _isLoadingTeachers = true);

    try {
      // Yahan bhi wahi fix: staff list aur us din ki teacher_attendance
      // dono parallel mein ek ek query se mangwate hain, har teacher ke
      // liye alag se doc().get() nahi karte (N+1 se bacha jaye)
      final results = await Future.wait([
        schoolCollection('staff').get(),
        schoolCollection('teacher_attendance')
            .where('date', isEqualTo: formattedDate)
            .get(),
      ]);
      var teachersSnapshot = results[0];
      var attendanceSnapshot = results[1];

      Map<String, String> attendanceByTeacherId = {
        for (var doc in attendanceSnapshot.docs)
          (doc.data()['teacherId'] as String? ?? doc.id): (doc.data()['status']
                  as String? ??
              'Present')
      };

      Map<String, String> tempMap = {};

      for (var doc in teachersSnapshot.docs) {
        String teacherId = doc.id;
        tempMap[teacherId] = attendanceByTeacherId[teacherId] ?? 'Present';
      }

      setState(() {
        teacherAttendanceMap = tempMap;
        _isLoadingTeachers = false;
      });
    } catch (e) {
      print("Error loading teacher attendance: $e");
      setState(() => _isLoadingTeachers = false);
    }
  }

  // 1. Save Student Attendance
  Future<void> _saveStudentAttendance() async {
    if (selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select a class first!"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSavingStudents = true);
    try {
      var firestore = FirebaseFirestore.instance;
      WriteBatch batch =
          firestore.batch(); // Batch write for better performance

      for (var entry in studentAttendanceMap.entries) {
        String studentId = entry.key;
        String status = entry.value;
        String docId = "${formattedDate}_$studentId"; // unified: date+studentId only

        // Yahan 'DocumentRef' ki jagah 'docRef' use karein
        // IMPORTANT: schoolCollection() use karna zaroori hai, warna
        // attendance is school ke data se bahar root-level 'attendance'
        // collection mein chali jati he (parents/reports ko kabhi nazar
        // nahi aati, kyunke wo hamesha schoolCollection('attendance') se
        // padhte hain).
        var docRef = schoolCollection('attendance').doc(docId);
        batch.set(
            docRef,
            {
              'class': selectedClass,
              'studentId': studentId,
              'status': status,
              'date': formattedDate,
              'timestamp': Timestamp.now(),
            },
            SetOptions(merge: true));
      }

      await batch.commit();

      // Jo students aaj 'Absent' mark hue hain, unhe notification bhejte hain.
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
              content:
                  Text("Attendance for $formattedDate Saved Successfully!"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingStudents = false);
    }
  }

  // Absent mark hue students ke fcmToken Firestore se nikal kar unhe
  // notification bhejta hai.
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

  // 2. Save Teacher Attendance
  Future<void> _saveTeacherAttendance() async {
    setState(() => _isSavingTeachers = true);
    try {
      var firestore = FirebaseFirestore.instance;
      WriteBatch batch = firestore.batch();

      for (var entry in teacherAttendanceMap.entries) {
        String teacherId = entry.key;
        String status = entry.value;
        String docId = "Teacher_${formattedDate}_$teacherId";

        var docRef = schoolCollection('teacher_attendance').doc(docId);
        batch.set(
            docRef,
            {
              'teacherId': teacherId,
              'status': status,
              'date': formattedDate,
              'timestamp': Timestamp.now(),
            },
            SetOptions(merge: true));
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Teacher Attendance for $formattedDate Saved!"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingTeachers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Attendance Management", style: TextStyle(fontSize: 18)),
            Text("Date: $formattedDate",
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.teal[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, size: 28),
            onPressed: () => _pickDate(context),
            tooltip: "Change Date",
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.white,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: const [
            Tab(text: "Students"),
            Tab(text: "Teachers"),
          ],
        ),
      ),
      body: SafeArea(child: TabBarView(
        controller: _tabController,
        children: [
          // --- TAB 1: STUDENTS ATTENDANCE VIEW ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _isLoadingClasses
                    ? const Center(child: CircularProgressIndicator())
                    : DropdownButtonFormField<String>(
                        initialValue: selectedClass,
                        decoration: const InputDecoration(
                          labelText: "Select Class for Attendance",
                          border: OutlineInputBorder(),
                        ),
                        items: classesList
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedClass = val;
                            selectedSection =
                                null; // Class badalne par section reset
                            sectionsList = [];
                          });
                          if (val != null) _fetchSectionsForClass(val);
                          _loadStudentAttendanceForClassAndDate();
                        },
                      ),
                if (selectedClass != null && sectionsList.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSection,
                    decoration: const InputDecoration(
                      labelText: "Select Section (optional)",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text("All Sections")),
                      ...sectionsList.map(
                          (s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (val) {
                      setState(() => selectedSection = val);
                      _loadStudentAttendanceForClassAndDate();
                    },
                  ),
                ],
                const SizedBox(height: 15),
                Expanded(
                  child: selectedClass == null
                      ? const Center(
                          child: Text(
                              "Please select a class above to load students."))
                      : _isLoadingStudents
                          ? const Center(child: CircularProgressIndicator())
                          : studentAttendanceMap.isEmpty
                              ? const Center(
                                  child:
                                      Text("No students found in this class."))
                              : StreamBuilder<QuerySnapshot>(
                                  stream: (() {
                                    Query<Map<String, dynamic>> q =
                                        schoolCollection('students')
                                            .where('class',
                                                isEqualTo: selectedClass);
                                    if (selectedSection != null) {
                                      q = q.where('section',
                                          isEqualTo: selectedSection);
                                    }
                                    return q.snapshots();
                                  })(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const Center(
                                          child: CircularProgressIndicator());
                                    }
                                    var students = snapshot.data!.docs;

                                    if (students.isEmpty) {
                                      return const Center(
                                          child: Text(
                                              "No students found in this class."));
                                    }

                                    return ListView.builder(
                                      itemCount: students.length,
                                      itemBuilder: (context, index) {
                                        var studentDoc = students[index];
                                        var studentData = studentDoc.data()
                                            as Map<String, dynamic>;
                                        String studentId = studentDoc.id;
                                        String studentName =
                                            studentData['name'] ?? 'Unknown';
                                        String rollNo =
                                            studentData['rollNo'] ?? 'N/A';

                                        String currentStatus =
                                            studentAttendanceMap[studentId] ??
                                                'Present';

                                        return Card(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 6),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(studentName,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 16)),
                                                    Text("Roll No: $rollNo",
                                                        style: const TextStyle(
                                                            color:
                                                                Colors.grey)),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    _statusButton(
                                                        studentId,
                                                        'Present',
                                                        Colors.green,
                                                        currentStatus,
                                                        true),
                                                    const SizedBox(width: 5),
                                                    _statusButton(
                                                        studentId,
                                                        'Absent',
                                                        Colors.red,
                                                        currentStatus,
                                                        true),
                                                    const SizedBox(width: 5),
                                                    _statusButton(
                                                        studentId,
                                                        'Leave',
                                                        Colors.orange,
                                                        currentStatus,
                                                        true),
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
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[800]),
                    onPressed:
                        _isSavingStudents ? null : _saveStudentAttendance,
                    child: _isSavingStudents
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
          ),

          // --- TAB 2: TEACHERS ATTENDANCE VIEW ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Mark Teachers Attendance ($formattedDate)",
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _isLoadingTeachers
                      ? const Center(child: CircularProgressIndicator())
                      : teacherAttendanceMap.isEmpty
                          ? const Center(child: Text("No teachers found."))
                          : StreamBuilder<QuerySnapshot>(
                              stream: schoolCollection('staff')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                var teachers = snapshot.data!.docs;

                                if (teachers.isEmpty) {
                                  return const Center(
                                      child: Text("No staff members found."));
                                }

                                return ListView.builder(
                                  itemCount: teachers.length,
                                  itemBuilder: (context, index) {
                                    var teacherDoc = teachers[index];
                                    var teacherData = teacherDoc.data()
                                        as Map<String, dynamic>;
                                    String teacherId = teacherDoc.id;
                                    String teacherName = teacherData['name'] ??
                                        teacherData['teacherName'] ??
                                        'Unknown';
                                    String phone = teacherData['contact'] ??
                                        teacherData['contactNo'] ??
                                        teacherData['phone'] ??
                                        teacherData['mobile'] ??
                                        'N/A';

                                    String currentStatus =
                                        teacherAttendanceMap[teacherId] ??
                                            'Present';

                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 6),
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
                                                Text(teacherName,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16)),
                                                Text("Phone: $phone",
                                                    style: const TextStyle(
                                                        color: Colors.grey)),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                _statusButton(
                                                    teacherId,
                                                    'Present',
                                                    Colors.green,
                                                    currentStatus,
                                                    false),
                                                const SizedBox(width: 5),
                                                _statusButton(
                                                    teacherId,
                                                    'Absent',
                                                    Colors.red,
                                                    currentStatus,
                                                    false),
                                                const SizedBox(width: 5),
                                                _statusButton(
                                                    teacherId,
                                                    'Leave',
                                                    Colors.orange,
                                                    currentStatus,
                                                    false),
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
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[800]),
                    onPressed:
                        _isSavingTeachers ? null : _saveTeacherAttendance,
                    child: _isSavingTeachers
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            "SAVE TEACHER ATTENDANCE ($formattedDate)",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }

  Widget _statusButton(String id, String statusLabel, Color color,
      String currentStatus, bool isStudent) {
    bool isSelected = currentStatus == statusLabel;
    return InkWell(
      onTap: () {
        setState(() {
          if (isStudent) {
            studentAttendanceMap[id] = statusLabel;
          } else {
            teacherAttendanceMap[id] = statusLabel;
          }
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
}
