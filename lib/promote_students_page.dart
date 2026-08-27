import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'class_section_service.dart';
import 'subscription_gate.dart';

/// Promotes every active student to the next class in one go, based on
/// the class order defined in Class/Section management
/// (see class_section_service.dart — classes are stored in the order
/// they were set up, e.g. ['Playgroup','Nursery','One','Two',...]).
///
/// Students already in the last class in that list have no "next class"
/// to go to — they're left untouched and listed separately (e.g. as
/// graduating students who need a manual decision).
class PromoteStudentsPage extends StatefulWidget {
  const PromoteStudentsPage({super.key});

  @override
  State<PromoteStudentsPage> createState() => _PromoteStudentsPageState();
}

class _PromoteStudentsPageState extends State<PromoteStudentsPage> {
  AcademicStructure? _structure;
  bool _loading = true;
  bool _promoting = false;

  // classFrom -> classTo preview, plus counts
  Map<String, String> _promotionMap = {};
  Map<String, int> _countPerClass = {};
  List<String> _finalClassStudents = []; // names of students in the last class
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _finalClassDocs = [];
  bool _deactivating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final structure = await ClassSectionService.getAll();
    final snap = await schoolCollection('students')
        .where('status', isEqualTo: 'active')
        .get();

    final Map<String, int> counts = {};
    final List<String> finalClassStudents = [];
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> finalClassDocs = [];
    final Map<String, String> promotionMap = {};

    for (var i = 0; i < structure.classes.length; i++) {
      final current = structure.classes[i];
      if (i + 1 < structure.classes.length) {
        promotionMap[current] = structure.classes[i + 1];
      }
    }

    for (var doc in snap.docs) {
      final data = doc.data();
      final currentClass = (data['class'] ?? '').toString();
      if (!promotionMap.containsKey(currentClass)) {
        // Either an unrecognized class name, or the last class in the
        // list (nothing to promote to).
        if (structure.classes.isNotEmpty &&
            currentClass == structure.classes.last) {
          finalClassStudents.add((data['name'] ?? 'Unnamed').toString());
          finalClassDocs.add(doc);
        }
        continue;
      }
      counts[currentClass] = (counts[currentClass] ?? 0) + 1;
    }

    if (mounted) {
      setState(() {
        _structure = structure;
        _promotionMap = promotionMap;
        _countPerClass = counts;
        _finalClassStudents = finalClassStudents;
        _finalClassDocs = finalClassDocs;
        _loading = false;
      });
    }
  }

  int get _totalToPromote =>
      _countPerClass.values.fold(0, (a, b) => a + b);

  Future<void> _confirmAndPromote() async {
    if (!await SubscriptionGuard.ensureActive(context)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Promote All Active Students?"),
        content: Text(
            "$_totalToPromote active student(s) will be moved to their next class. "
            "This cannot be undone automatically — please make sure you have "
            "reviewed the list below before continuing."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, Promote All",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _promoting = true);
    try {
      final snap = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();

      // Firestore batches are capped at 500 writes — chunk if needed.
      var batch = FirebaseFirestore.instance.batch();
      int opCount = 0;
      int promoted = 0;

      for (var doc in snap.docs) {
        final data = doc.data();
        final currentClass = (data['class'] ?? '').toString();
        final nextClass = _promotionMap[currentClass];
        if (nextClass == null) continue; // last class / unrecognized

        batch.update(doc.reference, {'class': nextClass});
        promoted++;
        opCount++;

        if (opCount >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          opCount = 0;
        }
      }

      if (opCount > 0) {
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("$promoted student(s) promoted successfully!"),
          backgroundColor: Colors.green,
        ));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _promoting = false);
    }
  }

  // Class 10 (ya jo bhi list ki last class ho) ke wo students jo aage
  // promote nahi ho sakte (koi "next class" nahi hai) — unki active
  // status khatam kar deta hai (status: 'graduated'), taake wo baqi
  // active-student reports/lists mein na aayein. SLC/left ki tarah,
  // sirf status field update hota hai — record delete nahi hota.
  Future<void> _confirmAndDeactivateFinalClass() async {
    if (_finalClassDocs.isEmpty) return;
    if (!await SubscriptionGuard.ensureActive(context)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("End Active Status for These Students?"),
        content: Text(
            "${_finalClassDocs.length} student(s) in ${_structure!.classes.last} "
            "will no longer be promoted, so their active status will be ended "
            "(marked as graduated). They will stop showing up in active-student "
            "lists/reports. This cannot be undone automatically."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, End Active Status",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deactivating = true);
    try {
      var batch = FirebaseFirestore.instance.batch();
      int opCount = 0;

      for (var doc in _finalClassDocs) {
        batch.update(doc.reference, {'status': 'graduated'});
        opCount++;
        if (opCount >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          opCount = 0;
        }
      }
      if (opCount > 0) {
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text("${_finalClassDocs.length} student(s) marked as graduated."),
          backgroundColor: Colors.green,
        ));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _deactivating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Promote Students"),
        backgroundColor: Colors.teal[800],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_structure == null || _structure!.classes.isEmpty)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                        "No class list found. Please set up Classes first "
                        "(Manage Classes/Sections) before promoting students."),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: Colors.teal[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Promotion Preview",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                                "$_totalToPromote active student(s) will move up one class."),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._promotionMap.entries
                        .where((e) => (_countPerClass[e.key] ?? 0) > 0)
                        .map((e) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.arrow_upward,
                                    color: Colors.teal),
                                title:
                                    Text("${e.key}  →  ${e.value}"),
                                trailing: Text(
                                    "${_countPerClass[e.key]} student(s)",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                            )),
                    if (_finalClassStudents.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: Colors.orange[50],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  "${_finalClassStudents.length} student(s) are already in the "
                                  "last class (${_structure!.classes.last}) — they won't be "
                                  "promoted automatically. End their active status below "
                                  "once you've confirmed they're graduating:",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(_finalClassStudents.join(", ")),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red)),
                                  onPressed: _deactivating
                                      ? null
                                      : _confirmAndDeactivateFinalClass,
                                  icon: _deactivating
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                              color: Colors.red,
                                              strokeWidth: 2))
                                      : const Icon(Icons.person_off),
                                  label: Text(_deactivating
                                      ? "Ending Active Status..."
                                      : "End Active Status for ${_finalClassStudents.length} Student(s)"),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style:
                            ElevatedButton.styleFrom(backgroundColor: Colors.teal[800]),
                        onPressed: (_promoting || _totalToPromote == 0)
                            ? null
                            : _confirmAndPromote,
                        icon: _promoting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.upgrade, color: Colors.white),
                        label: Text(
                          _promoting
                              ? "Promoting..."
                              : "Promote $_totalToPromote Student(s)",
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
