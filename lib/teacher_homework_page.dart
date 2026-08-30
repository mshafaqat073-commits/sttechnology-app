import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_helper.dart';
import 'school_context.dart';

// The teacher-side Diary / Homework / Special Message page.
// The only difference from the admin-side HomeTaskPage is that the
// Class/Section dropdown doesn't fetch every class from Firestore —
// it only shows the classes/sections this teacher is assigned in their
// staff record (assignedClasses). So a teacher can never send a
// diary/homework/message entry to a different class.
class TeacherHomeworkPage extends StatefulWidget {
  // The list from the staff doc, e.g. [{'class': '6', 'section': 'A'}, ...]
  final List<Map<String, String>> assignedClasses;
  // Optional: used to save the teacher's name alongside the record.
  final String? teacherName;

  const TeacherHomeworkPage({
    super.key,
    required this.assignedClasses,
    this.teacherName,
  });

  @override
  State<TeacherHomeworkPage> createState() => _TeacherHomeworkPageState();
}

class _TeacherHomeworkPageState extends State<TeacherHomeworkPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Set Diary Controllers
  String? _diaryClass;
  String? _diarySection;
  final TextEditingController _diaryTextController = TextEditingController();
  bool _isSavingDiary = false;

  // Set Homework Controllers
  String? _hwClass;
  String? _hwSection;
  final TextEditingController _hwSubjectController = TextEditingController();
  final TextEditingController _hwTextController = TextEditingController();
  bool _isSavingHw = false;

  // Set Special Message Controllers
  String? _msgClass;
  String? _msgSection;
  final TextEditingController _msgTextController = TextEditingController();
  bool _isSavingMsg = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _diaryTextController.dispose();
    _hwSubjectController.dispose();
    _hwTextController.dispose();
    _msgTextController.dispose();
    super.dispose();
  }

  // Distinct class names among the teacher's assigned classes.
  List<String> get _assignedClassNames {
    final names = widget.assignedClasses
        .map((e) => e['class'] ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  // For the given class — only the sections this teacher is assigned
  // in that class (another teacher's sections won't show up).
  List<String> _sectionsForAssignedClass(String? className) {
    if (className == null || className.isEmpty) return [];
    final sections = widget.assignedClasses
        .where((e) => e['class'] == className)
        .map((e) => e['section'] ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    sections.sort();
    return sections;
  }

  // Sends a push + in-app notification to all students of the given
  // class (and section, if given). If section is empty, students from
  // the whole class are included.
  Future<void> _notifyClassStudents({
    required String className,
    required String section,
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      Query query = schoolCollection('students')
          .where('class', isEqualTo: className);
      if (section.isNotEmpty) {
        query = query.where('section', isEqualTo: section);
      }
      final snap = await query.get();
      if (snap.docs.isEmpty) return;

      final targets = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {'id': d.id, 'token': data['fcmToken'] as String?};
      }).toList();

      await NotificationHelper.sendToMultiple(
        targets: targets,
        toRole: 'student',
        title: title,
        body: body,
        type: type,
      );
    } catch (e) {
      // Even if the notification fails, the diary/homework/message has
      // already been saved — so this is silently ignored to avoid
      // showing the user a confusing error right after a save success.
      debugPrint('Notify students failed: $e');
    }
  }

  Future<void> _saveDiary() async {
    if (_diaryClass == null || _diaryClass!.isEmpty ||
        _diaryTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please fill all fields for Diary!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSavingDiary = true);
    try {
      await schoolCollection('school_diary').add({
        'class': _diaryClass,
        'section': _diarySection ?? '',
        'diary': _diaryTextController.text.trim(),
        'date': Timestamp.now(),
        'dateString': DateTime.now().toString().split(' ')[0],
        'postedBy': widget.teacherName ?? '',
      });

      await _notifyClassStudents(
        className: _diaryClass!,
        section: _diarySection ?? '',
        title: 'New Diary Entry',
        body: _diaryTextController.text.trim(),
        type: 'diary',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Diary Saved Successfully!"),
              backgroundColor: Colors.green),
        );
        _diaryTextController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDiary = false);
    }
  }

  Future<void> _saveHomework() async {
    if (_hwClass == null || _hwClass!.isEmpty ||
        _hwSubjectController.text.trim().isEmpty ||
        _hwTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please fill all fields for Homework!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSavingHw = true);
    try {
      await schoolCollection('school_homework').add({
        'class': _hwClass,
        'section': _hwSection ?? '',
        'subject': _hwSubjectController.text.trim(),
        'homework': _hwTextController.text.trim(),
        'date': Timestamp.now(),
        'dateString': DateTime.now().toString().split(' ')[0],
        'postedBy': widget.teacherName ?? '',
      });

      await _notifyClassStudents(
        className: _hwClass!,
        section: _hwSection ?? '',
        title: 'New Homework: ${_hwSubjectController.text.trim()}',
        body: _hwTextController.text.trim(),
        type: 'homework',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Homework Assigned Successfully!"),
              backgroundColor: Colors.green),
        );
        _hwSubjectController.clear();
        _hwTextController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingHw = false);
    }
  }

  Future<void> _saveSpecialMessage() async {
    if (_msgClass == null || _msgClass!.isEmpty ||
        _msgTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please fill all fields for Special Message!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSavingMsg = true);
    try {
      await schoolCollection('special_messages').add({
        'class': _msgClass,
        'section': _msgSection ?? '',
        'message': _msgTextController.text.trim(),
        'date': Timestamp.now(),
        'dateString': DateTime.now().toString().split(' ')[0],
        'postedBy': widget.teacherName ?? '',
      });

      await _notifyClassStudents(
        className: _msgClass!,
        section: _msgSection ?? '',
        title: 'Special Message',
        body: _msgTextController.text.trim(),
        type: 'message',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Special Message Sent Successfully!"),
              backgroundColor: Colors.green),
        );
        _msgTextController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingMsg = false);
    }
  }

  // "My Posts" dialog: a teacher can only view/edit/delete posts from
  // their own assigned classes — restricted to the class list via
  // Firestore whereIn.
  void _openManagementDialog() {
    final classNames = _assignedClassNames;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("My Diary / Homework / Messages"),
        content: SizedBox(
          width: double.maxFinite,
          child: DefaultTabController(
            length: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  labelColor: Colors.teal,
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(text: "Diary"),
                    Tab(text: "Homework"),
                    Tab(text: "Message"),
                  ],
                ),
                SizedBox(
                  height: 350,
                  child: TabBarView(
                    children: [
                      _buildRecordList('school_diary', 'diary', classNames),
                      _buildRecordList(
                          'school_homework', 'homework', classNames),
                      _buildRecordList(
                          'special_messages', 'message', classNames),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordList(
      String collectionName, String fieldKey, List<String> classNames) {
    if (classNames.isEmpty) {
      return const Center(child: Text("No assigned classes."));
    }
    // Firestore whereIn supports up to 30 values (10 on older SDKs) —
    // fine here since it's just this teacher's own assigned classes.
    //
    // NOTE: orderBy('date') is deliberately not added to the query —
    // combining a whereIn on 'class' with an orderBy on 'date' would
    // require Firestore to have a composite index. If that index didn't
    // exist, the query would fail, and since we were only checking
    // hasData (not hasError), the UI would get stuck on the loading
    // spinner forever. Sorting is now done client-side in Dart below,
    // so no index needs to be created.
    return StreamBuilder<QuerySnapshot>(
      stream: schoolCollection(collectionName)
          .where('class', whereIn: classNames)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "Error loading records: ${snapshot.error}",
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        // Extra safety: keep only the docs whose class+section combo is
        // actually assigned to this teacher.
        var docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final cls = (data['class'] ?? '').toString();
          final sec = (data['section'] ?? '').toString();
          final assignedSections = _sectionsForAssignedClass(cls);
          return assignedSections.isEmpty || assignedSections.contains(sec);
        }).toList();

        // Newest entry first — the date field is a Timestamp.
        docs.sort((a, b) {
          final da = (a.data() as Map<String, dynamic>)['date'];
          final db = (b.data() as Map<String, dynamic>)['date'];
          if (da is Timestamp && db is Timestamp) {
            return db.compareTo(da);
          }
          return 0;
        });

        if (docs.isEmpty) return const Center(child: Text("No records found"));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var doc = docs[index];
            var data = doc.data() as Map<String, dynamic>;
            String className = data['class'] ?? '';
            String sectionName = data['section'] ?? '';
            String contentText = data[fieldKey] ?? data['subject'] ?? '';

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(
                    sectionName.isNotEmpty
                        ? "Class: $className - $sectionName"
                        : "Class: $className",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(contentText,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () =>
                          _editRecord(doc.id, collectionName, fieldKey, data),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteRecord(doc.id, collectionName),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _editRecord(String docId, String collectionName, String fieldKey,
      Map<String, dynamic> existingData) {
    TextEditingController editController =
        TextEditingController(text: existingData[fieldKey]);
    TextEditingController subjectEditController =
        TextEditingController(text: existingData['subject'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Update $collectionName"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (collectionName == 'school_homework') ...[
              TextField(
                controller: subjectEditController,
                decoration: const InputDecoration(labelText: "Subject"),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: editController,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: "Details", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[800]),
            onPressed: () async {
              Map<String, dynamic> updateData = {
                fieldKey: editController.text.trim(),
              };
              if (collectionName == 'school_homework') {
                updateData['subject'] = subjectEditController.text.trim();
              }

              await schoolCollection(collectionName)
                  .doc(docId)
                  .update(updateData);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Updated Successfully!")));
              }
            },
            child: const Text("Save Changes",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRecord(String docId, String collectionName) async {
    await schoolCollection(collectionName)
        .doc(docId)
        .delete();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Deleted Successfully!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final classNames = _assignedClassNames;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Homework & Diary"),
        backgroundColor: Colors.teal[800],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.book), text: "Diary"),
            Tab(icon: Icon(Icons.assignment), text: "Homework"),
            Tab(icon: Icon(Icons.message), text: "Special Msg"),
          ],
        ),
      ),
      body: SafeArea(child: classNames.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You have not been assigned any class. Please contact the admin.",
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Diary
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _diaryClass,
                              decoration: const InputDecoration(
                                  labelText: "Select Class",
                                  border: OutlineInputBorder()),
                              items: classNames
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (val) => setState(() {
                                _diaryClass = val;
                                _diarySection = null;
                              }),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _diarySection,
                              decoration: InputDecoration(
                                  labelText: "Select Section",
                                  border: const OutlineInputBorder(),
                                  hintText: _diaryClass == null
                                      ? "Select class first"
                                      : null),
                              items: _sectionsForAssignedClass(_diaryClass)
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _diarySection = val),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _diaryTextController,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: "Diary Details / Message",
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
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
                                        borderRadius:
                                            BorderRadius.circular(10))),
                                onPressed: _isSavingDiary ? null : _saveDiary,
                                child: _isSavingDiary
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : const Text("SAVE & SEND DIARY",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tab 2: Homework
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _hwClass,
                              decoration: const InputDecoration(
                                  labelText: "Select Class",
                                  border: OutlineInputBorder()),
                              items: classNames
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (val) => setState(() {
                                _hwClass = val;
                                _hwSection = null;
                              }),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _hwSection,
                              decoration: InputDecoration(
                                  labelText: "Select Section",
                                  border: const OutlineInputBorder(),
                                  hintText: _hwClass == null
                                      ? "Select class first"
                                      : null),
                              items: _sectionsForAssignedClass(_hwClass)
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _hwSection = val),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _hwSubjectController,
                              decoration: const InputDecoration(
                                  labelText: "Subject Name (e.g. Math, English)",
                                  border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _hwTextController,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: "Homework Task Details",
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepOrange[600],
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10))),
                                onPressed: _isSavingHw ? null : _saveHomework,
                                child: _isSavingHw
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : const Text("ASSIGN HOMEWORK",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tab 3: Special Message
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _msgClass,
                              decoration: const InputDecoration(
                                  labelText: "Select Class",
                                  border: OutlineInputBorder()),
                              items: classNames
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (val) => setState(() {
                                _msgClass = val;
                                _msgSection = null;
                              }),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _msgSection,
                              decoration: InputDecoration(
                                  labelText: "Select Section",
                                  border: const OutlineInputBorder(),
                                  hintText: _msgClass == null
                                      ? "Select class first"
                                      : null),
                              items: _sectionsForAssignedClass(_msgClass)
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _msgSection = val),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _msgTextController,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText:
                                    "Special Message for Students / Parents",
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple[600],
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10))),
                                onPressed:
                                    _isSavingMsg ? null : _saveSpecialMessage,
                                child: _isSavingMsg
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : const Text("SEND SPECIAL MESSAGE",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Button below to edit/delete entries this teacher has posted
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[800],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _openManagementDialog,
                    icon: const Icon(Icons.edit_note, color: Colors.white),
                    label: const Text(
                      "Edit / Update My Diary, Homework & Messages",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            )),
    );
  }
}
