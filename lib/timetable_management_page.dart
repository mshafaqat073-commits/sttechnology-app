import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'class_section_service.dart';
import 'school_context.dart';

// Admin side page: set/edit the class timetable here. Classes and sections
// are read live from ClassSectionService (app_settings/academic_structure),
// and teacher names are read live from the 'staff' collection (Teaching
// category only) — nothing is typed by hand.
//
// Each period is saved to Firestore collection 'timetable'. Document id:
// "<class>-<section>_<day>_p<period>" (deterministic, so re-saving the
// same period overwrites instead of creating a duplicate).
//
// The "available X minutes before/after" buffer is a single school-wide
// setting stored at app_settings/timetable_settings.bufferMinutes, so it
// only has to be set once here and both this page and the teacher's
// timetable page read the same value.
class TimetableManagementPage extends StatefulWidget {
  const TimetableManagementPage({super.key});

  @override
  State<TimetableManagementPage> createState() =>
      _TimetableManagementPageState();
}

class _TimetableManagementPageState extends State<TimetableManagementPage> {
  static const List<String> _days = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];

  static DocumentReference<Map<String, dynamic>> get _settingsRef =>
      schoolCollection('app_settings')
          .doc('timetable_settings');

  String? _selectedClass;
  String? _selectedSection;
  String? _activeClass;
  String? _activeSection;
  String _selectedDay = _days.first;

  AcademicStructure _structure = AcademicStructure.empty;
  StreamSubscription<AcademicStructure>? _structureSub;

  List<String> _teacherNames = [];
  StreamSubscription<QuerySnapshot>? _staffSub;

  int _bufferMinutes = 15;
  final TextEditingController _bufferController =
      TextEditingController(text: '15');
  bool _savingBuffer = false;

  // If no section is selected/active, the timetable is being set for the
  // whole class (every section under it) rather than one specific section.
  bool get _appliesToAllSections =>
      _activeSection == null || _activeSection!.isEmpty;

  String get _classKey =>
      _appliesToAllSections ? "$_activeClass-ALL" : "$_activeClass-$_activeSection";

  @override
  void initState() {
    super.initState();

    _structureSub = ClassSectionService.watch().listen((structure) {
      setState(() => _structure = structure);
    });

    _staffSub = schoolCollection('staff')
        .where('category', isEqualTo: 'Teaching')
        .snapshots()
        .listen((snap) {
      final names = snap.docs
          .map((d) => (d.data()['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      setState(() => _teacherNames = names);
    });

    _loadBufferSetting();
  }

  Future<void> _loadBufferSetting() async {
    final doc = await _settingsRef.get();
    final minutes = doc.data()?['bufferMinutes'];
    if (minutes != null) {
      setState(() {
        _bufferMinutes = int.tryParse(minutes.toString()) ?? 15;
        _bufferController.text = _bufferMinutes.toString();
      });
    }
  }

  Future<void> _saveBufferSetting() async {
    final minutes = int.tryParse(_bufferController.text.trim());
    if (minutes == null || minutes < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid number of minutes")),
      );
      return;
    }
    setState(() => _savingBuffer = true);
    await _settingsRef.set({'bufferMinutes': minutes}, SetOptions(merge: true));
    if (!mounted) return;
    setState(() {
      _bufferMinutes = minutes;
      _savingBuffer = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Timing instruction updated")),
    );
  }

  @override
  void dispose() {
    _structureSub?.cancel();
    _staffSub?.cancel();
    _bufferController.dispose();
    super.dispose();
  }

  List<String> get _sectionsForSelectedClass =>
      _structure.sectionsFor(_selectedClass);

  void _loadTimetable() {
    if (_selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a class first")),
      );
      return;
    }
    setState(() {
      _activeClass = _selectedClass;
      _activeSection = _selectedSection;
    });
  }

  Future<void> _openPeriodDialog({DocumentSnapshot? existing}) async {
    final data = existing?.data() as Map<String, dynamic>?;
    final periodController =
        TextEditingController(text: data?['period']?.toString() ?? '');
    final subjectController =
        TextEditingController(text: data?['subject']?.toString() ?? '');

    String? selectedTeacher = data?['teacherName']?.toString();
    final teacherOptions = List<String>.from(_teacherNames);
    if (selectedTeacher != null &&
        selectedTeacher.isNotEmpty &&
        !teacherOptions.contains(selectedTeacher)) {
      teacherOptions.add(selectedTeacher);
    }

    TimeOfDay startTime = _parseTime(data?['startTime']) ??
        const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime =
        _parseTime(data?['endTime']) ?? const TimeOfDay(hour: 9, minute: 0);

    // When true, saving this period writes it to every day of the week
    // instead of just the currently selected day, so the same period
    // doesn't have to be re-entered for each day separately.
    bool applyToAllDays = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? "New Period" : "Edit Period"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: periodController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Period No."),
                    ),
                    TextField(
                      controller: subjectController,
                      decoration: const InputDecoration(labelText: "Subject"),
                    ),
                    const SizedBox(height: 8),
                    teacherOptions.isEmpty
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "No teaching staff found. Add staff first.",
                              style: TextStyle(color: Colors.red),
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            decoration:
                                const InputDecoration(labelText: "Teacher"),
                            initialValue: selectedTeacher,
                            items: teacherOptions
                                .map((t) =>
                                    DropdownMenuItem(value: t, child: Text(t)))
                                .toList(),
                            onChanged: (v) =>
                                setDialogState(() => selectedTeacher = v),
                          ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                  context: ctx, initialTime: startTime);
                              if (picked != null) {
                                setDialogState(() => startTime = picked);
                              }
                            },
                            child: Text("Start: ${startTime.format(ctx)}"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                  context: ctx, initialTime: endTime);
                              if (picked != null) {
                                setDialogState(() => endTime = picked);
                              }
                            },
                            child: Text("End: ${endTime.format(ctx)}"),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: applyToAllDays,
                      onChanged: (v) =>
                          setDialogState(() => applyToAllDays = v ?? false),
                      title: const Text("Apply to all days"),
                      subtitle: const Text(
                        "Saves this period for every day of the week instead of just the selected day",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final period = periodController.text.trim();
                    if (period.isEmpty || subjectController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content:
                                Text("Period no. and subject are required")),
                      );
                      return;
                    }

                    final periodData = {
                      'classKey': _classKey,
                      'className': _activeClass,
                      'section': _activeSection,
                      'appliesToAllSections': _appliesToAllSections,
                      'period': period,
                      'subject': subjectController.text.trim(),
                      'teacherName': selectedTeacher ?? '',
                      'startTime': _formatTime(startTime),
                      'endTime': _formatTime(endTime),
                    };

                    if (applyToAllDays) {
                      // Write the same period to every day in one batch so
                      // it doesn't have to be added separately per day.
                      final batch = FirebaseFirestore.instance.batch();
                      for (final day in _days) {
                        final docId = "${_classKey}_${day}_p$period";
                        final ref =
                            schoolCollection('timetable').doc(docId);
                        batch.set(ref, {...periodData, 'day': day});
                      }
                      await batch.commit();
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  "Period saved to all days")),
                        );
                      }
                    } else {
                      final docId = "${_classKey}_${_selectedDay}_p$period";
                      await schoolCollection('timetable')
                          .doc(docId)
                          .set({...periodData, 'day': _selectedDay});
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deletePeriod(String docId) async {
    await schoolCollection('timetable').doc(docId).delete();
  }

  TimeOfDay? _parseTime(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?', caseSensitive: false)
        .firstMatch(str);
    if (match == null) return null;
    int hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)?.toUpperCase();
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return "$hour:$minute $period";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Timetable"),
        backgroundColor: Colors.teal[800],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.amber[100],
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Teachers must be available $_bufferMinutes minutes before "
                  "and $_bufferMinutes minutes after each period.",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text("Buffer:"),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: _bufferController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          suffixText: "min",
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _savingBuffer ? null : _saveBufferSetting,
                      child: _savingBuffer
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Save"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                        labelText: "Class", border: OutlineInputBorder()),
                    initialValue: _selectedClass,
                    items: _structure.classes
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedClass = v;
                      _selectedSection = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                        labelText: "Section", border: OutlineInputBorder()),
                    initialValue: _selectedSection,
                    items: _sectionsForSelectedClass
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: _sectionsForSelectedClass.isEmpty
                        ? null
                        : (v) => setState(() => _selectedSection = v),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loadTimetable,
                  child: const Text("Load"),
                ),
              ],
            ),
          ),
          if (_activeClass != null) ...[
            if (_appliesToAllSections)
              Container(
                width: double.infinity,
                color: Colors.blue[50],
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  "No section selected — this timetable applies to all sections of $_activeClass.",
                  style: TextStyle(
                      color: Colors.blue[900],
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _days.map((day) {
                  final selected = day == _selectedDay;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(day),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedDay = day),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: schoolCollection('timetable')
                    .where('classKey', isEqualTo: _classKey)
                    .where('day', isEqualTo: _selectedDay)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  docs.sort((a, b) {
                    final pa = int.tryParse(
                            (a.data() as Map)['period'].toString()) ??
                        0;
                    final pb = int.tryParse(
                            (b.data() as Map)['period'].toString()) ??
                        0;
                    return pa.compareTo(pb);
                  });
                  if (docs.isEmpty) {
                    return const Center(
                        child: Text("No periods set for this day yet"));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final d = doc.data() as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                              child: Text(d['period'].toString())),
                          title: Text(d['subject'] ?? ''),
                          subtitle: Text(
                              "${d['teacherName'] ?? ''}  •  ${d['startTime'] ?? ''} - ${d['endTime'] ?? ''}"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () =>
                                    _openPeriodDialog(existing: doc),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    size: 20, color: Colors.red),
                                onPressed: () => _deletePeriod(doc.id),
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
          ] else
            const Expanded(
              child: Center(
                child: Text("Select a class and tap 'Load' to continue"),
              ),
            ),
        ],
      ),
      floatingActionButton: _activeClass == null
          ? null
          : FloatingActionButton(
              backgroundColor: Colors.teal[800],
              onPressed: () => _openPeriodDialog(),
              child: const Icon(Icons.add),
            ),
    );
  }
}

