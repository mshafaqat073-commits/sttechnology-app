import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'notification_helper.dart';
import 'school_context.dart';

// -----------------------------------------------------------------------
// Individual Student Issue page.
//
// Unlike school_diary / school_homework / special_messages (which always
// go to a whole class or a whole section), this sends a message to ONE
// specific student only. Only that student's parent will see it, because
// the parent-side stream filters strictly by studentId (see
// StudentIssuesParentList below) — no "whole class" fallback like the
// other collections have.
//
// Works for both Admin and Teacher:
// - Admin: pass `assignedClasses: null` -> every class/section is fetched
//   from the students collection.
// - Teacher: pass the teacher's `assignedClasses` (same shape used in
//   TeacherHomeworkPage) -> only their own classes/sections are shown.
//
// Firestore collection used: 'student_issues'
// Fields written: studentId, studentName, class, section, message,
// imageUrl, date, dateString, postedBy.
//
// Requires these packages in pubspec.yaml (add if not already present):
//   firebase_storage: ^11.0.0
//   image_picker: ^1.0.0
// -----------------------------------------------------------------------

class StudentIssuePage extends StatefulWidget {
  // Pass null for Admin (fetches every class). Pass the teacher's own
  // assigned classes/sections to restrict the picker, same shape as
  // TeacherHomeworkPage.assignedClasses.
  final List<Map<String, String>>? assignedClasses;
  // Name of the admin/teacher sending the message, saved with the record.
  final String? postedByName;

  const StudentIssuePage({
    super.key,
    this.assignedClasses,
    this.postedByName,
  });

  @override
  State<StudentIssuePage> createState() => _StudentIssuePageState();
}

class _StudentIssuePageState extends State<StudentIssuePage> {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  // Class / Section source data
  List<String> _classesList = [];
  Map<String, List<String>> _classSectionMap = {};
  bool _isLoadingClasses = true;

  // Selection state
  String? _selectedClass;
  String? _selectedSection;
  String? _selectedStudentId;
  String? _selectedStudentName;

  // Students within the selected class + section
  List<Map<String, dynamic>> _studentsInSection = [];
  bool _isLoadingStudents = false;

  // Picked photo (kept as bytes so this works on web and mobile alike)
  XFile? _pickedImageFile;
  Uint8List? _pickedImageBytes;

  bool _isSending = false;

  bool get _isTeacherMode => widget.assignedClasses != null;

  @override
  void initState() {
    super.initState();
    if (_isTeacherMode) {
      _buildClassSectionMapFromAssigned();
    } else {
      _fetchAllClassesAndSections();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _buildClassSectionMapFromAssigned() {
    final classes = <String>{};
    final map = <String, Set<String>>{};
    for (final entry in widget.assignedClasses!) {
      final cls = (entry['class'] ?? '').trim();
      final sec = (entry['section'] ?? '').trim();
      if (cls.isEmpty) continue;
      classes.add(cls);
      if (sec.isNotEmpty) {
        map.putIfAbsent(cls, () => {}).add(sec);
      }
    }
    final sortedClasses = classes.toList()..sort();
    final sortedMap = <String, List<String>>{};
    map.forEach((cls, secs) => sortedMap[cls] = secs.toList()..sort());
    setState(() {
      _classesList = sortedClasses;
      _classSectionMap = sortedMap;
      _isLoadingClasses = false;
    });
  }

  Future<void> _fetchAllClassesAndSections() async {
    try {
      final snapshot = await schoolCollection('students').get();
      final classesSet = <String>{};
      final classSectionSetMap = <String, Set<String>>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final cls = (data['class'] ?? '').toString().trim();
        final sec = (data['section'] ?? '').toString().trim();
        if (cls.isNotEmpty && cls != 'Not Selected') {
          classesSet.add(cls);
          if (sec.isNotEmpty && sec != 'Not Selected') {
            classSectionSetMap.putIfAbsent(cls, () => {}).add(sec);
          }
        }
      }
      final classes = classesSet.toList()..sort();
      final sortedMap = <String, List<String>>{};
      classSectionSetMap.forEach((cls, secs) {
        sortedMap[cls] = secs.toList()..sort();
      });
      if (mounted) {
        setState(() {
          _classesList = classes;
          _classSectionMap = sortedMap;
          _isLoadingClasses = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  List<String> _sectionsForClass(String? className) {
    if (className == null || className.isEmpty) return [];
    return _classSectionMap[className] ?? [];
  }

  Future<void> _fetchStudentsForSection(String cls, String sec) async {
    setState(() {
      _isLoadingStudents = true;
      _studentsInSection = [];
      _selectedStudentId = null;
      _selectedStudentName = null;
    });
    try {
      final snap = await schoolCollection('students')
          .where('class', isEqualTo: cls)
          .where('section', isEqualTo: sec)
          .get();
      final students = snap.docs.map((d) {
        final data = d.data();
        final name =
            (data['name'] ?? data['studentName'] ?? 'Unnamed').toString();
        return {
          'id': d.id,
          'name': name,
          'fcmToken': data['fcmToken'] as String?,
        };
      }).toList();
      students
          .sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      if (mounted) {
        setState(() {
          _studentsInSection = students;
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _imagePicker.pickImage(source: source, imageQuality: 70);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedImageFile = file;
      _pickedImageBytes = bytes;
    });
  }

  void _removeImage() {
    setState(() {
      _pickedImageFile = null;
      _pickedImageBytes = null;
    });
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text("Take Photo"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Choose from Gallery"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadImageIfAny(String studentId) async {
    if (_pickedImageBytes == null) return null;
    final ref = FirebaseStorage.instance
        .ref()
        .child('student_issues')
        .child(studentId)
        .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
    final uploadTask = await ref.putData(
      _pickedImageBytes!,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await uploadTask.ref.getDownloadURL();
  }

  Future<void> _sendIssue() async {
    if (_selectedClass == null ||
        _selectedSection == null ||
        _selectedStudentId == null ||
        _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Please select class, section, student and write a message."),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final studentId = _selectedStudentId!;
      final imageUrl = await _uploadImageIfAny(studentId);

      await schoolCollection('student_issues').add({
        'studentId': studentId,
        'studentName': _selectedStudentName ?? '',
        'class': _selectedClass,
        'section': _selectedSection,
        'message': _messageController.text.trim(),
        'imageUrl': imageUrl,
        'date': Timestamp.now(),
        'dateString': DateTime.now().toString().split(' ')[0],
        'postedBy': widget.postedByName ?? '',
      });

      // Notify only this one student's parent — not the whole class.
      final token = _studentsInSection
          .firstWhere((s) => s['id'] == studentId)['fcmToken'] as String?;
      try {
        await NotificationHelper.sendToMultiple(
          targets: [
            {'id': studentId, 'token': token}
          ],
          toRole: 'parent',
          title: 'Message about ${_selectedStudentName ?? "your child"}',
          body: _messageController.text.trim(),
          type: 'student_issue',
        );
      } catch (e) {
        debugPrint('Notify parent failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Message sent to the parent successfully!"),
              backgroundColor: Colors.green),
        );
        setState(() {
          _messageController.clear();
          _pickedImageFile = null;
          _pickedImageBytes = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Student Issue",
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.indigo[700],
      ),
      body: _isLoadingClasses
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "This message will be visible only to the selected "
                    "student's parent, not the rest of the class.",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedClass,
                    decoration: const InputDecoration(
                        labelText: "Select Class",
                        border: OutlineInputBorder()),
                    items: _classesList
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) => setState(() {
                      _selectedClass = val;
                      _selectedSection = null;
                      _studentsInSection = [];
                      _selectedStudentId = null;
                      _selectedStudentName = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSection,
                    decoration: InputDecoration(
                        labelText: "Select Section",
                        border: const OutlineInputBorder(),
                        hintText: _selectedClass == null
                            ? "Select class first"
                            : null),
                    items: _sectionsForClass(_selectedClass)
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) {
                      setState(() => _selectedSection = val);
                      if (_selectedClass != null && val != null) {
                        _fetchStudentsForSection(_selectedClass!, val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedStudentId,
                    decoration: InputDecoration(
                        labelText: "Select Student",
                        border: const OutlineInputBorder(),
                        hintText: _isLoadingStudents
                            ? "Loading students..."
                            : (_selectedSection == null
                                ? "Select section first"
                                : (_studentsInSection.isEmpty
                                    ? "No students found"
                                    : null))),
                    items: _studentsInSection
                        .map((s) => DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text(s['name'] as String),
                            ))
                        .toList(),
                    onChanged: (val) {
                      final match =
                          _studentsInSection.firstWhere((s) => s['id'] == val);
                      setState(() {
                        _selectedStudentId = val;
                        _selectedStudentName = match['name'] as String;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: "Describe the issue for this student",
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_pickedImageBytes != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _pickedImageBytes!,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            radius: 16,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close,
                                  color: Colors.white, size: 18),
                              onPressed: _removeImage,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _showImageSourceSheet,
                    icon: const Icon(Icons.attach_file),
                    label: Text(_pickedImageBytes == null
                        ? "Attach Photo (optional)"
                        : "Change Photo"),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo[700],
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      onPressed: _isSending ? null : _sendIssue,
                      child: _isSending
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("SEND TO PARENT",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// -----------------------------------------------------------------------
// A ready-made button that opens StudentIssuePage. Drop this into the
// existing HomeTaskPage / TeacherHomeworkPage bottom action area, next to
// the existing "Edit / Update" button.
// -----------------------------------------------------------------------
class ReportStudentIssueButton extends StatelessWidget {
  final List<Map<String, String>>? assignedClasses;
  final String? postedByName;

  const ReportStudentIssueButton({
    super.key,
    this.assignedClasses,
    this.postedByName,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent[700],
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentIssuePage(
                assignedClasses: assignedClasses,
                postedByName: postedByName,
              ),
            ),
          );
        },
        icon: const Icon(Icons.person_search, color: Colors.white),
        label: const Text(
          "Report Issue for a Specific Student",
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Parent-side widget: shows ONLY the issue messages posted for this exact
// student (strict studentId match — no whole-class fallback). Embed this
// as a 4th tab (or a section) inside ParentHomeTaskPage, passing the
// child's own document id from the students collection.
// -----------------------------------------------------------------------
class StudentIssuesParentList extends StatelessWidget {
  final String studentId;

  const StudentIssuesParentList({super.key, required this.studentId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: schoolCollection('student_issues')
          .where('studentId', isEqualTo: studentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final ta = (a.data() as Map)['date'] as Timestamp?;
            final tb = (b.data() as Map)['date'] as Timestamp?;
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta);
          });
        if (docs.isEmpty) {
          return const Center(child: Text("No messages for your child yet."));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final imageUrl = data['imageUrl'] as String?;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.priority_high,
                            color: Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text("Message about your child",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.redAccent)),
                        ),
                        Text(data['dateString']?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(data['message']?.toString() ?? ''),
                    if (imageUrl != null && imageUrl.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          imageUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(
                              height: 180,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                          errorBuilder: (context, error, stack) =>
                              const SizedBox(
                            height: 60,
                            child: Center(child: Text("Could not load image")),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
