import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_helper.dart';
import 'school_context.dart';

class HomeTaskPage extends StatefulWidget {
  const HomeTaskPage({super.key});

  @override
  State<HomeTaskPage> createState() => _HomeTaskPageState();
}

class _HomeTaskPageState extends State<HomeTaskPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Set Diary Controllers
  final TextEditingController _diaryClassController = TextEditingController();
  final TextEditingController _diarySectionController = TextEditingController();
  final TextEditingController _diaryTextController = TextEditingController();
  bool _isSavingDiary = false;

  // Set Homework Controllers
  final TextEditingController _hwClassController = TextEditingController();
  final TextEditingController _hwSectionController = TextEditingController();
  final TextEditingController _hwSubjectController = TextEditingController();
  final TextEditingController _hwTextController = TextEditingController();
  bool _isSavingHw = false;

  // Set Special Message Controllers
  final TextEditingController _msgClassController = TextEditingController();
  final TextEditingController _msgSectionController = TextEditingController();
  final TextEditingController _msgTextController = TextEditingController();
  bool _isSavingMsg = false;

  // Class aur Section list Firestore se (students collection) fetch hoti hai
  // — jo classes/sections admission ke waqt already bana di gayi hain
  List<String> classesList = [];
  // Har class ke apne hi sections — key: class name, value: us class ke sections
  Map<String, List<String>> _classSectionMap = {};
  bool _isLoadingLists = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchExistingClassesAndSections();
  }

  // Students collection se distinct Class aur har Class ke sections nikalna
  Future<void> _fetchExistingClassesAndSections() async {
    try {
      var snapshot =
          await schoolCollection('students').get();
      Set<String> classesSet = {};
      Map<String, Set<String>> classSectionSetMap = {};
      for (var doc in snapshot.docs) {
        var data = doc.data();
        String cls = (data['class'] ?? '').toString().trim();
        String sec = (data['section'] ?? '').toString().trim();
        if (cls.isNotEmpty && cls != 'Not Selected') {
          classesSet.add(cls);
          if (sec.isNotEmpty && sec != 'Not Selected') {
            classSectionSetMap.putIfAbsent(cls, () => {}).add(sec);
          }
        }
      }
      List<String> classes = classesSet.toList()..sort();
      Map<String, List<String>> sortedMap = {};
      classSectionSetMap.forEach((cls, secs) {
        sortedMap[cls] = secs.toList()..sort();
      });
      if (mounted) {
        setState(() {
          classesList = classes;
          _classSectionMap = sortedMap;
          _isLoadingLists = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingLists = false);
    }
  }

  // Diya gaya class ke liye uske existing sections wapis dena
  List<String> _sectionsForClass(String? className) {
    if (className == null || className.isEmpty) return [];
    return _classSectionMap[className] ?? [];
  }

  @override
  void dispose() {
    _tabController.dispose();
    _diaryClassController.dispose();
    _diarySectionController.dispose();
    _diaryTextController.dispose();
    _hwClassController.dispose();
    _hwSectionController.dispose();
    _hwSubjectController.dispose();
    _hwTextController.dispose();
    _msgClassController.dispose();
    _msgSectionController.dispose();
    _msgTextController.dispose();
    super.dispose();
  }

  // Diary Save karne ka function
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
      debugPrint('Notify students failed: $e');
    }
  }

  Future<void> _saveDiary() async {
    if (_diaryClassController.text.isEmpty ||
        _diaryTextController.text.isEmpty) {
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
        'class': _diaryClassController.text,
        'section': _diarySectionController.text,
        'diary': _diaryTextController.text.trim(),
        'date': Timestamp.now(),
        'dateString': DateTime.now().toString().split(' ')[0],
      });

      await _notifyClassStudents(
        className: _diaryClassController.text,
        section: _diarySectionController.text,
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

  // Homework Save karne ka function
  Future<void> _saveHomework() async {
    if (_hwClassController.text.isEmpty ||
        _hwSubjectController.text.isEmpty ||
        _hwTextController.text.isEmpty) {
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
        'class': _hwClassController.text,
        'section': _hwSectionController.text,
        'subject': _hwSubjectController.text.trim(),
        'homework': _hwTextController.text.trim(),
        'date': Timestamp.now(),
        'dateString': DateTime.now().toString().split(' ')[0],
      });

      await _notifyClassStudents(
        className: _hwClassController.text,
        section: _hwSectionController.text,
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

  // Special Message Save karne ka function
  Future<void> _saveSpecialMessage() async {
    if (_msgClassController.text.isEmpty || _msgTextController.text.isEmpty) {
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
        'class': _msgClassController.text,
        'section': _msgSectionController.text,
        'message': _msgTextController.text.trim(),
        'date': Timestamp.now(),
        'dateString': DateTime.now().toString().split(' ')[0],
      });

      await _notifyClassStudents(
        className: _msgClassController.text,
        section: _msgSectionController.text,
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

  // Edit / Update Dialog open karne ke liye function
  void _openManagementDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Manage & Update Records"),
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
                      _buildRecordList('school_diary', 'diary'),
                      _buildRecordList('school_homework', 'homework'),
                      _buildRecordList('special_messages', 'message'),
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

  // Firestore se data fetch kar ke Edit/Update karne ki list view
  Widget _buildRecordList(String collectionName, String fieldKey) {
    return StreamBuilder<QuerySnapshot>(
      stream: schoolCollection(collectionName)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snapshot.data!.docs;
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

  // Record Update karne ka Dialog
  void _editRecord(String docId, String collectionName, String fieldKey,
      Map<String, dynamic> existingData) {
    TextEditingController editController =
        TextEditingController(text: existingData[fieldKey]);
    TextEditingController subjectEditController =
        TextEditingController(text: existingData['subject'] ?? '');
    TextEditingController sectionEditController =
        TextEditingController(text: existingData['section'] ?? '');

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
              controller: sectionEditController,
              decoration: const InputDecoration(labelText: "Section"),
            ),
            const SizedBox(height: 10),
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
                'section': sectionEditController.text.trim(),
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

  // Record Delete karne ka function
  Future<void> _deleteRecord(String docId, String collectionName) async {
    await schoolCollection(collectionName)
        .doc(docId)
        .delete();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Deleted Successfully!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Home Task & Diary Management",
          style: TextStyle(color: Colors.white),
        ),
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
      body: SafeArea(child: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Set Diary
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _diaryClassController.text.isNotEmpty
                            ? _diaryClassController.text
                            : null,
                        decoration: InputDecoration(
                            labelText: "Select Class",
                            border: const OutlineInputBorder(),
                            hintText: _isLoadingLists ? "Loading..." : null),
                        items: classesList
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (val) => setState(() {
                          _diaryClassController.text = val ?? '';
                          _diarySectionController.clear();
                        }),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _diarySectionController.text.isNotEmpty
                            ? _diarySectionController.text
                            : null,
                        decoration: InputDecoration(
                            labelText: "Select Section",
                            border: const OutlineInputBorder(),
                            hintText: _diaryClassController.text.isEmpty
                                ? "Select class first"
                                : null),
                        items: _sectionsForClass(_diaryClassController.text)
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (val) => setState(
                            () => _diarySectionController.text = val ?? ''),
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
                                  borderRadius: BorderRadius.circular(10))),
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

                // Tab 2: Set Homework
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _hwClassController.text.isNotEmpty
                            ? _hwClassController.text
                            : null,
                        decoration: InputDecoration(
                            labelText: "Select Class",
                            border: const OutlineInputBorder(),
                            hintText: _isLoadingLists ? "Loading..." : null),
                        items: classesList
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (val) => setState(() {
                          _hwClassController.text = val ?? '';
                          _hwSectionController.clear();
                        }),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _hwSectionController.text.isNotEmpty
                            ? _hwSectionController.text
                            : null,
                        decoration: InputDecoration(
                            labelText: "Select Section",
                            border: const OutlineInputBorder(),
                            hintText: _hwClassController.text.isEmpty
                                ? "Select class first"
                                : null),
                        items: _sectionsForClass(_hwClassController.text)
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (val) => setState(
                            () => _hwSectionController.text = val ?? ''),
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
                                  borderRadius: BorderRadius.circular(10))),
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
                        initialValue: _msgClassController.text.isNotEmpty
                            ? _msgClassController.text
                            : null,
                        decoration: InputDecoration(
                            labelText: "Select Class",
                            border: const OutlineInputBorder(),
                            hintText: _isLoadingLists ? "Loading..." : null),
                        items: classesList
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (val) => setState(() {
                          _msgClassController.text = val ?? '';
                          _msgSectionController.clear();
                        }),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _msgSectionController.text.isNotEmpty
                            ? _msgSectionController.text
                            : null,
                        decoration: InputDecoration(
                            labelText: "Select Section",
                            border: const OutlineInputBorder(),
                            hintText: _msgClassController.text.isEmpty
                                ? "Select class first"
                                : null),
                        items: _sectionsForClass(_msgClassController.text)
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (val) => setState(
                            () => _msgSectionController.text = val ?? ''),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _msgTextController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: "Special Message for Students / Parents",
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
                                  borderRadius: BorderRadius.circular(10))),
                          onPressed: _isSavingMsg ? null : _saveSpecialMessage,
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

          // Niche Edit / Update / Delete Button
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
                "Edit / Update Diary, Homework & Messages",
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
