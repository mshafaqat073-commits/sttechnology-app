import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

// Teacher side page: read-only view of whatever the admin has set on the
// Timetable Management page. Classes/sections come from the teacher's own
// assignedClasses list, so nothing needs to be picked here. The "minutes
// before/after" instruction is read from the same school-wide setting the
// admin controls (app_settings/timetable_settings.bufferMinutes).
class TeacherTimetablePage extends StatefulWidget {
  final List<Map<String, String>> assignedClasses;

  const TeacherTimetablePage({super.key, required this.assignedClasses});

  @override
  State<TeacherTimetablePage> createState() => _TeacherTimetablePageState();
}

class _TeacherTimetablePageState extends State<TeacherTimetablePage> {
  static const List<String> _days = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];

  late String _selectedDay;
  int _bufferMinutes = 15;

  @override
  void initState() {
    super.initState();
    final weekday = DateTime.now().weekday; // 1 = Monday ... 7 = Sunday
    _selectedDay = weekday >= 1 && weekday <= 6 ? _days[weekday - 1] : _days.first;
    _loadBufferSetting();
  }

  Future<void> _loadBufferSetting() async {
    final doc = await schoolCollection('app_settings')
        .doc('timetable_settings')
        .get();
    final minutes = doc.data()?['bufferMinutes'];
    if (minutes != null && mounted) {
      setState(() => _bufferMinutes = int.tryParse(minutes.toString()) ?? 15);
    }
  }

  List<String> get _classKeys => widget.assignedClasses
      .map((a) =>
          "${(a['class'] ?? '').trim()}-${(a['section'] ?? '').trim()}")
      .toSet()
      .toList();

  // Class names only (no section) — used to also match timetable entries
  // the admin set for a whole class (appliesToAllSections == true), which
  // apply regardless of which section this class/section combo is in.
  List<String> get _classNames => widget.assignedClasses
      .map((a) => (a['class'] ?? '').trim())
      .toSet()
      .toList();

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
            child: Text(
              "You must be available $_bufferMinutes minutes before and "
              "$_bufferMinutes minutes after each of your periods.",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            child: _classKeys.isEmpty
                ? const Center(child: Text("No class assigned"))
                : StreamBuilder<QuerySnapshot>(
                    // Only filter by 'day' on the server (a single equality
                    // filter never needs a composite index) and match the
                    // teacher/parent's classKey(s) locally below. The old
                    // query combined whereIn('classKey', ...) with
                    // where('day', ...), which needs a Firestore composite
                    // index — when that index wasn't created, Firestore
                    // silently failed the query, so the admin-set timetable
                    // never showed up here even though it saved correctly.
                    stream: schoolCollection('timetable')
                        .where('day', isEqualTo: _selectedDay)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "Could not load timetable:\n${snapshot.error}",
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final classKeySet = _classKeys.toSet();
                      final classNameSet = _classNames.toSet();
                      final docs = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        if (classKeySet.contains(data['classKey'])) {
                          return true;
                        }
                        // Whole-class entry (no section picked by admin) —
                        // applies to every section of that class.
                        return data['appliesToAllSections'] == true &&
                            classNameSet.contains(data['className']);
                      }).toList();
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
                            child: Text("No timetable set for this day yet"));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final d = docs[index].data() as Map<String, dynamic>;
                          return Card(
                            child: ListTile(
                              leading:
                                  CircleAvatar(child: Text(d['period'].toString())),
                              title: Text(d['subject'] ?? ''),
                              subtitle: Text(
                                  "${d['className'] ?? ''} - ${d['section'] ?? ''}  •  ${d['startTime'] ?? ''} - ${d['endTime'] ?? ''}"),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
