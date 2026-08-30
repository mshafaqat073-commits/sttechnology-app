import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

/// Enter results for a WHOLE CLASS in one go.
///
/// Problem this solves: in EnterResultPage / TeacherEnterResultPage, the
/// teacher has to pick a student, then retype every subject name + total
/// (max) marks for that one student — and repeat that for all 30 students.
///
/// Here, the teacher:
///   1) Picks Class + Section + Term
///   2) Types each Subject name + Total marks ONCE
///   3) Loads all students of that class/section (name, roll no auto-filled)
///   4) Types only the OBTAINED marks per student per subject
///   5) Hits Submit once — all students' results are saved together.
///
/// Pass [allowedClasses] (same shape used in TeacherEnterResultPage) to
/// restrict a teacher to only their assigned class/section. Leave it empty
/// (default) for unrestricted/admin use.
class BulkEnterResultPage extends StatefulWidget {
  final List<Map<String, String>> allowedClasses;

  const BulkEnterResultPage({super.key, this.allowedClasses = const []});

  @override
  State<BulkEnterResultPage> createState() => _BulkEnterResultPageState();
}

class _SubjectSetup {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController totalCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    totalCtrl.dispose();
  }
}

class _StudentRow {
  final String id;
  final String name;
  final String fatherName;
  final String rollNo;
  final String className;
  final String section;
  final List<TextEditingController> obtainedCtrls;
  // One absent flag PER SUBJECT — a student can be present for some
  // subjects and absent for others (e.g. missed one paper but sat the
  // rest), instead of only an all-or-nothing "absent" toggle.
  final List<bool> subjectAbsent;

  _StudentRow({
    required this.id,
    required this.name,
    required this.fatherName,
    required this.rollNo,
    required this.className,
    required this.section,
    required int subjectCount,
  })  : obtainedCtrls =
            List.generate(subjectCount, (_) => TextEditingController()),
        subjectAbsent = List.generate(subjectCount, (_) => false);

  // True only when every subject is marked absent — drives the
  // "Absent (All)" convenience checkbox.
  bool get allAbsent =>
      subjectAbsent.isNotEmpty && subjectAbsent.every((a) => a);

  // Marks (or unmarks) every subject absent at once, clearing any
  // obtained-marks text for subjects being marked absent.
  void setAllAbsent(bool value) {
    for (int i = 0; i < subjectAbsent.length; i++) {
      subjectAbsent[i] = value;
      if (value) obtainedCtrls[i].clear();
    }
  }

  void dispose() {
    for (final c in obtainedCtrls) {
      c.dispose();
    }
  }
}

class _BulkEnterResultPageState extends State<BulkEnterResultPage> {
  bool get _isRestricted => widget.allowedClasses.isNotEmpty;

  // Sentinel section value meaning "every section of this class" — distinct
  // from an empty string, which (for admin-loaded classes) means students
  // that genuinely have no section assigned.
  static const String _kAllSections = '__ALL_SECTIONS__';

  // --- Step 1: class / section / term ---
  // Always picked from EXISTING classes/sections (from the 'students'
  // collection, or from allowedClasses for a restricted teacher) — never
  // free-typed, so no new/misspelled classes get created here.
  Map<String, String>? _selectedClassSection;
  List<Map<String, String>> _availableClasses = []; // loaded from Firestore
  bool _loadingClasses = false;

  final TextEditingController _termController =
      TextEditingController(text: 'Weekly Test');
  final List<String> _termOptions = [
    'First Term',
    'Mid Term',
    'Final Term',
    'Monthly Test',
    'Weekly Test'
  ];

  // --- Step 2: subjects + total marks (entered once) ---
  final List<_SubjectSetup> _subjectSetup = [_SubjectSetup()];

  // --- Step 3: loaded students ---
  List<_StudentRow> _students = [];
  bool _loadingStudents = false;
  bool _loaded = false; // true once "Load Class" succeeded
  bool _submitting = false;

  // Same fixed academic order used in ClassDetailPage, so the dropdown
  // lists classes in a sensible order instead of alphabetically.
  static const List<String> _baseClassesOrder = [
    'Playgroup',
    'Nursery',
    'Prep',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten'
  ];

  int _compareClasses(String a, String b) {
    final ai = _baseClassesOrder.indexOf(a);
    final bi = _baseClassesOrder.indexOf(b);
    if (ai == -1 && bi == -1) return a.compareTo(b);
    if (ai == -1) return -1;
    if (bi == -1) return 1;
    return ai.compareTo(bi);
  }

  @override
  void initState() {
    super.initState();
    if (!_isRestricted) {
      _loadAvailableClasses();
    }
  }

  // Reads the existing class/section combinations straight from the
  // 'students' collection, so the admin can only pick a class/section
  // that already exists — never type a new one here.
  Future<void> _loadAvailableClasses() async {
    setState(() => _loadingClasses = true);
    try {
      final snap = await schoolCollection('students').get();

      // Group distinct sections per class first, so we know when a class
      // has more than one section (and therefore needs an "All Sections"
      // option) versus just a single section.
      final Map<String, Set<String>> sectionsByClass = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final cls = (data['class'] ?? '').toString().trim();
        final sec = (data['section'] ?? '').toString().trim();
        if (cls.isEmpty) continue;
        sectionsByClass.putIfAbsent(cls, () => {}).add(sec);
      }

      final classNames = sectionsByClass.keys.toList()..sort(_compareClasses);

      final List<Map<String, String>> list = [];
      for (final cls in classNames) {
        final sections = sectionsByClass[cls]!.toList()..sort();
        if (sections.length > 1) {
          list.add({'class': cls, 'section': _kAllSections});
        }
        for (final sec in sections) {
          list.add({'class': cls, 'section': sec});
        }
      }

      if (mounted) {
        setState(() {
          _availableClasses = list;
          _loadingClasses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingClasses = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Could not load classes: $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _termController.dispose();
    for (final s in _subjectSetup) {
      s.dispose();
    }
    for (final st in _students) {
      st.dispose();
    }
    super.dispose();
  }

  void _addSubjectSetupRow() {
    setState(() => _subjectSetup.add(_SubjectSetup()));
  }

  void _removeSubjectSetupRow(int index) {
    if (_subjectSetup.length > 1) {
      setState(() {
        _subjectSetup[index].dispose();
        _subjectSetup.removeAt(index);
      });
    }
  }

  List<Map<String, String>> get _classOptions =>
      _isRestricted ? widget.allowedClasses : _availableClasses;

  String get _className => _selectedClassSection?['class'] ?? '';

  String get _section => _selectedClassSection?['section'] ?? '';

  String get _sectionLabel {
    if (_section == _kAllSections) return ' - All Sections';
    if (_section.isNotEmpty) return ' - $_section';
    return '';
  }

  bool get _canLoad {
    if (_selectedClassSection == null) return false;
    for (final s in _subjectSetup) {
      if (s.nameCtrl.text.trim().isEmpty || s.totalCtrl.text.trim().isEmpty) {
        return false;
      }
      if (double.tryParse(s.totalCtrl.text.trim()) == null) return false;
    }
    return true;
  }

  Future<void> _loadClassStudents() async {
    if (!_canLoad) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Please select a class and fill in every subject's name and total marks.")),
      );
      return;
    }

    setState(() => _loadingStudents = true);

    try {
      Query query =
          schoolCollection('students').where('class', isEqualTo: _className);
      if (_section.isNotEmpty && _section != _kAllSections) {
        query = query.where('section', isEqualTo: _section);
      }
      final snap = await query.get();

      final rows = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return _StudentRow(
          id: doc.id,
          name: (data['name'] ?? '').toString(),
          fatherName: (data['fName'] ?? data['fatherName'] ?? '').toString(),
          rollNo: (data['rollNo'] ?? data['rollNumber'] ?? '').toString(),
          className: (data['class'] ?? '').toString(),
          section: (data['section'] ?? '').toString(),
          subjectCount: _subjectSetup.length,
        );
      }).toList();

      rows.sort((a, b) {
        final an = int.tryParse(a.rollNo);
        final bn = int.tryParse(b.rollNo);
        if (an != null && bn != null) return an.compareTo(bn);
        return a.name.compareTo(b.name);
      });

      for (final st in _students) {
        st.dispose();
      }

      setState(() {
        _students = rows;
        _loaded = true;
        _loadingStudents = false;
      });

      if (rows.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("No students found in this class/section.")),
        );
      }
    } catch (e) {
      setState(() => _loadingStudents = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _editSetupAgain() {
    setState(() {
      _loaded = false;
      for (final st in _students) {
        st.dispose();
      }
      _students = [];
    });
  }

  String _calculateGrade(double percentage) {
    if (percentage >= 80) return 'A+';
    if (percentage >= 70) return 'A';
    if (percentage >= 60) return 'B';
    if (percentage >= 50) return 'C';
    if (percentage >= 40) return 'D';
    return 'F';
  }

  Future<void> _submitAll() async {
    // Parse the shared subject/total-marks setup once.
    final List<Map<String, dynamic>> subjectDefs = [];
    for (final s in _subjectSetup) {
      subjectDefs.add({
        'subjectName': s.nameCtrl.text.trim(),
        'totalMarks': double.parse(s.totalCtrl.text.trim()),
      });
    }

    // Validate every filled-in student row before writing anything.
    final List<_StudentRow> toSubmit = [];
    for (final st in _students) {
      final bool anyFilled =
          st.obtainedCtrls.any((c) => c.text.trim().isNotEmpty);
      final bool anyAbsent = st.subjectAbsent.any((a) => a);
      if (!anyFilled && !anyAbsent) {
        continue; // skip students left blank (not done yet)
      }

      for (int i = 0; i < st.obtainedCtrls.length; i++) {
        if (st.subjectAbsent[i]) {
          continue; // absent in this subject — no marks needed
        }

        final text = st.obtainedCtrls[i].text.trim();
        if (text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "${st.name}: enter marks for '${subjectDefs[i]['subjectName']}', mark it Absent, or leave the whole row blank.")),
          );
          return;
        }
        final obtained = double.tryParse(text);
        if (obtained == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${st.name}: marks must be a number.")),
          );
          return;
        }
        final total = subjectDefs[i]['totalMarks'] as double;
        if (obtained > total) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "${st.name}: obtained marks for '${subjectDefs[i]['subjectName']}' exceed the total.")),
          );
          return;
        }
      }
      toSubmit.add(st);
    }

    if (toSubmit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please enter marks for at least one student.")),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final now = Timestamp.now();
      final futures = <Future>[];

      for (final st in toSubmit) {
        double grandTotal = 0;
        double grandObtained = 0;
        final List<Map<String, dynamic>> subjectsData = [];

        for (int i = 0; i < subjectDefs.length; i++) {
          final total = subjectDefs[i]['totalMarks'] as double;

          if (st.subjectAbsent[i]) {
            // Recorded but excluded from the grand total/percentage, so
            // missing one paper doesn't unfairly drag down the result.
            subjectsData.add({
              'subjectName': subjectDefs[i]['subjectName'],
              'totalMarks': total,
              'obtainedMarks': null,
              'isAbsent': true,
            });
            continue;
          }

          final obtained = double.parse(st.obtainedCtrls[i].text.trim());
          grandTotal += total;
          grandObtained += obtained;
          subjectsData.add({
            'subjectName': subjectDefs[i]['subjectName'],
            'totalMarks': total,
            'obtainedMarks': obtained,
            'isAbsent': false,
          });
        }

        final percentage =
            grandTotal > 0 ? (grandObtained / grandTotal) * 100 : 0;
        final grade =
            st.allAbsent ? 'Absent' : _calculateGrade(percentage.toDouble());

        futures.add(schoolCollection('results').add({
          'studentId': st.id,
          'name': st.name,
          'fName': st.fatherName,
          'class': st.className,
          'section': st.section,
          'rollNo': st.rollNo,
          'term': _termController.text.trim(),
          'subjects': subjectsData,
          'grandTotal': grandTotal,
          'grandObtained': grandObtained,
          'percentage': percentage.toStringAsFixed(2),
          'grade': grade,
          'date': now,
        }));
      }

      await Future.wait(futures);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Results saved for ${toSubmit.length} students!"),
              backgroundColor: Colors.green),
        );
        setState(() {
          for (final st in _students) {
            for (final c in st.obtainedCtrls) {
              c.clear();
            }
            st.setAllAbsent(false);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Enter Result (Whole Class)"),
        backgroundColor: Colors.teal[800],
        actions: [
          if (_loaded)
            IconButton(
              tooltip: "Edit class/subjects setup",
              icon: const Icon(Icons.edit),
              onPressed: _editSetupAgain,
            ),
        ],
      ),
      body: SafeArea(
        child: _loaded ? _buildMarksGrid() : _buildSetupForm(),
      ),
    );
  }

  // ---------------- STEP 1 + 2: SETUP FORM ----------------
  Widget _buildSetupForm() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text("Class & Term",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[800],
                  fontSize: 16)),
          const SizedBox(height: 8),
          if (_loadingClasses)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text("Loading classes..."),
                ],
              ),
            )
          else if (_classOptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                "No classes found yet. Add students to a class first.",
                style: TextStyle(color: Colors.red),
              ),
            )
          else
            DropdownButtonFormField<Map<String, String>>(
              initialValue: _selectedClassSection,
              decoration: InputDecoration(
                labelText: "Class - Section",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              items: _classOptions.map((a) {
                final sec = a['section'] ?? '';
                final label = sec == _kAllSections
                    ? "${a['class']} — All Sections"
                    : sec.isNotEmpty
                        ? "${a['class']} - $sec"
                        : "${a['class']} (whole class)";
                return DropdownMenuItem(value: a, child: Text(label));
              }).toList(),
              onChanged: (val) => setState(() => _selectedClassSection = val),
              validator: (v) => v == null ? 'Please select a class' : null,
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _termOptions.contains(_termController.text)
                ? _termController.text
                : null,
            decoration: InputDecoration(
              labelText: "Exam Term",
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.grey[100],
            ),
            items: _termOptions
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _termController.text = val);
            },
          ),
          const SizedBox(height: 24),
          const Divider(thickness: 2),
          Text(
              "Subjects & Total Marks (entered once, applies to the whole class)",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[800],
                  fontSize: 16)),
          const SizedBox(height: 10),
          ...List.generate(_subjectSetup.length, (index) {
            final s = _subjectSetup[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: s.nameCtrl,
                      decoration: const InputDecoration(
                          labelText: "Subject Name",
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: s.totalCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: "Total Marks",
                          border: OutlineInputBorder()),
                    ),
                  ),
                  if (_subjectSetup.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _removeSubjectSetupRow(index),
                    ),
                ],
              ),
            );
          }),
          OutlinedButton.icon(
            style:
                OutlinedButton.styleFrom(foregroundColor: Colors.teal.shade800),
            onPressed: _addSubjectSetupRow,
            icon: const Icon(Icons.add),
            label: const Text("Add Subject"),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal[800],
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _loadingStudents ? null : _loadClassStudents,
            icon: _loadingStudents
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.groups, color: Colors.white),
            label: const Text("Load Class Students",
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ---------------- STEP 3: MARKS GRID ----------------
  Widget _buildMarksGrid() {
    if (_students.isEmpty) {
      return const Center(
          child: Text("No students found in this class/section."));
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.teal.shade50,
          padding: const EdgeInsets.all(10),
          child: Text(
            "Class: $_className$_sectionLabel  |  "
            "Term: ${_termController.text}  |  ${_students.length} students",
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[800]),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.teal.shade100),
                // Default row height (48) is too short for a marks field
                // PLUS an "Absent" checkbox stacked underneath it — bump
                // both up so nothing overflows.
                dataRowMinHeight: 78,
                dataRowMaxHeight: 86,
                columns: [
                  const DataColumn(label: Text("Roll")),
                  const DataColumn(label: Text("Name")),
                  ..._subjectSetup.map((s) => DataColumn(
                      label: Text("${s.nameCtrl.text}\n(/${s.totalCtrl.text})",
                          textAlign: TextAlign.center))),
                  const DataColumn(
                      label:
                          Text("Absent\n(All)", textAlign: TextAlign.center)),
                ],
                rows: _students.map((st) {
                  return DataRow(cells: [
                    DataCell(Text(st.rollNo)),
                    DataCell(SizedBox(width: 130, child: Text(st.name))),
                    ...List.generate(st.obtainedCtrls.length, (i) {
                      return DataCell(SizedBox(
                        width: 78,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: st.obtainedCtrls[i],
                              enabled: !st.subjectAbsent[i],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  border: OutlineInputBorder()),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.scale(
                                  scale: 0.75,
                                  child: Checkbox(
                                    value: st.subjectAbsent[i],
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    // Absent for THIS subject only — other
                                    // subjects for the same student are
                                    // unaffected and can still be entered.
                                    onChanged: (val) => setState(() {
                                      st.subjectAbsent[i] = val ?? false;
                                      if (st.subjectAbsent[i]) {
                                        st.obtainedCtrls[i].clear();
                                      }
                                    }),
                                  ),
                                ),
                                const Text("Absent",
                                    style: TextStyle(fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ));
                    }),
                    DataCell(Checkbox(
                      // Convenience toggle: marks/unmarks EVERY subject
                      // absent for this student in one tap.
                      value: st.allAbsent,
                      onChanged: (val) =>
                          setState(() => st.setAllAbsent(val ?? false)),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal[800],
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size(double.infinity, 48),
            ),
            onPressed: _submitting ? null : _submitAll,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, color: Colors.white),
            label: const Text("Save Results for Whole Class",
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
