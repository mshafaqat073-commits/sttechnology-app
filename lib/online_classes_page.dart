import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'school_context.dart';
import 'class_section_service.dart';
import 'notification_helper.dart';

/// Online Classes module — Teacher selects a class/section and schedules
/// an online class link (Zoom/Google Meet/YouTube/etc.) along with a date
/// & time. Parents can see it under their child's "Online Classes" menu
/// and tap the link to join.
///
/// If [isAdmin] is true, all classes across the school are shown
/// (not just the teacher's own) — used from the Admin dashboard.
/// Both Admin and Teacher can create/schedule an online class.
///
/// Class & Section are always picked from [ClassSectionService] (the same
/// structure used everywhere else in the app) — no free-typed class names,
/// so an online class can never be scheduled against a class/section that
/// doesn't actually exist.
///
/// A Teacher (isAdmin == false) can only pick from [assignedClasses] — the
/// class(es)/section(s) they are actually assigned to. If an entry in
/// [assignedClasses] also carries a 'section' key, the teacher is locked to
/// that exact section; otherwise they can pick any section that exists for
/// that class.
///
/// Firestore: schools/{schoolId}/online_classes/{autoId}
///   title, subject, className, section, platform, link,
///   scheduledAt (Timestamp), createdByName, createdByRole, createdAt
///
/// Notifications: same pattern already used in AttendancePage
/// (_notifyAbsentStudents) and DefaultersPage — after the class is saved,
/// we look up the fcmToken of every active student in that className
/// (and section, if one was picked) and call
/// [NotificationHelper.sendToMultiple], which both writes the in-app
/// notification history and relays the push via the Apps Script FCM relay.
class OnlineClassesPage extends StatefulWidget {
  final bool isAdmin;
  final String? createdByName;
  final List<Map<String, String>>? assignedClasses;

  const OnlineClassesPage({
    super.key,
    this.isAdmin = false,
    this.createdByName,
    this.assignedClasses,
  });

  @override
  State<OnlineClassesPage> createState() => _OnlineClassesPageState();
}

class _OnlineClassesPageState extends State<OnlineClassesPage> {
  final _titleController = TextEditingController();
  final _subjectController = TextEditingController();
  final _linkController = TextEditingController();
  String? _selectedClass;
  String? _selectedSection;
  String _platform = 'Zoom';
  DateTime? _scheduledAt;
  bool _isSubmitting = false;

  final _platforms = const ['Zoom', 'Google Meet', 'YouTube Live', 'Other'];

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  /// Classes this user (Admin or Teacher) is allowed to schedule an online
  /// class for, based on the real class/section structure.
  List<String> _allowedClasses(AcademicStructure structure) {
    if (widget.isAdmin) return structure.classes;
    if (widget.assignedClasses == null || widget.assignedClasses!.isEmpty) {
      return [];
    }
    final set = <String>{};
    for (final c in widget.assignedClasses!) {
      final cls = c['class'];
      // Only offer classes that still exist in the current structure —
      // keeps things in sync if Admin later removes/renames a class.
      if (cls != null && cls.isNotEmpty && structure.classes.contains(cls)) {
        set.add(cls);
      }
    }
    return set.toList();
  }

  /// Sections this user is allowed to pick for [className].
  List<String> _allowedSections(AcademicStructure structure, String? className) {
    if (className == null) return [];
    final allSections = structure.sectionsFor(className);
    if (widget.isAdmin) return allSections;

    // Teacher: if their assignment names a specific section for this
    // class, lock them to just that (they may be assigned "One" - "A"
    // only, not the whole class). If no section was specified for this
    // class in their assignment, let them pick from any section that
    // exists for it.
    final assignedSections = (widget.assignedClasses ?? [])
        .where((c) => c['class'] == className)
        .map((c) => c['section'])
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    if (assignedSections.isEmpty) return allSections;
    return assignedSections.where(allSections.contains).toList();
  }

  Future<void> _createClass(AcademicStructure structure) async {
    if (_titleController.text.trim().isEmpty ||
        _linkController.text.trim().isEmpty ||
        _selectedClass == null ||
        _scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Title, Class, Link and Time are required!"),
          backgroundColor: Colors.red));
      return;
    }

    // Defensive re-check: never let a class outside this user's allowed
    // list slip through, even if the dropdown state was stale.
    final allowedClasses = _allowedClasses(structure);
    if (!widget.isAdmin && !allowedClasses.contains(_selectedClass)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("You can only schedule a class you are assigned to."),
          backgroundColor: Colors.red));
      return;
    }
    if (_selectedSection != null &&
        !_allowedSections(structure, _selectedClass).contains(_selectedSection)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select a valid section for this class."),
          backgroundColor: Colors.red));
      return;
    }

    final title = _titleController.text.trim();
    final subject = _subjectController.text.trim();
    final className = _selectedClass!;
    final section = _selectedSection ?? '';

    setState(() => _isSubmitting = true);
    try {
      await schoolCollection('online_classes').add({
        'title': title,
        'subject': subject,
        'className': className,
        // Empty section = whole class (all sections), matching how
        // ParentOnlineClassesPage already treats an empty section.
        'section': section,
        'platform': _platform,
        'link': _linkController.text.trim(),
        'scheduledAt': Timestamp.fromDate(_scheduledAt!),
        'createdByName': widget.createdByName ?? 'Admin',
        'createdByRole': widget.isAdmin ? 'admin' : 'teacher',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Notify the parents of this class/section — same pattern as
      // AttendancePage's _notifyAbsentStudents.
      await _notifyClassStudents(
        className: className,
        section: section,
        title: title,
        subject: subject,
      );

      _titleController.clear();
      _subjectController.clear();
      _linkController.clear();
      setState(() {
        _scheduledAt = null;
        _selectedSection = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "Online class scheduled — parents of this class will be notified."),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Looks up every active student in [className] (and [section], if one
  /// was picked) and pushes a notification to their parent via
  /// [NotificationHelper.sendToMultiple] — mirrors
  /// AttendancePage._notifyAbsentStudents.
  Future<void> _notifyClassStudents({
    required String className,
    required String section,
    required String title,
    required String subject,
  }) async {
    try {
      Query<Map<String, dynamic>> query = schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .where('class', isEqualTo: className);
      if (section.isNotEmpty) {
        query = query.where('section', isEqualTo: section);
      }
      final snap = await query.get();
      if (snap.docs.isEmpty) return;

      final targets = snap.docs
          .map((d) => {
                'id': d.id,
                'token': d.data()['fcmToken'] as String?,
              })
          .toList();

      await NotificationHelper.sendToMultiple(
        targets: targets,
        toRole: 'student',
        title: 'Online Class: $title',
        body: subject.isNotEmpty
            ? '$subject • $_platform • starting soon'
            : '$_platform • starting soon',
        type: 'online_class',
        data: {'className': className, 'section': section},
      );
    } catch (e) {
      debugPrint('Notify class students (online class) failed: $e');
    }
  }

  Future<void> _joinLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Could not open the link."), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _confirmDelete(DocumentReference ref, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete Online Class"),
        content: Text('Delete "$title"? Parents will no longer see it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Online class deleted."), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error deleting: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildForm(AcademicStructure structure) {
    final allowedClasses = _allowedClasses(structure);
    final allowedSections = _allowedSections(structure, _selectedClass);

    if (allowedClasses.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            widget.isAdmin
                ? "No classes have been set up yet. Go to Settings → Manage Classes & Sections first."
                : "You don't have any class assigned to you yet. Please contact the Admin.",
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Schedule a New Online Class",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                  labelText: "Title (e.g. Math Chapter 5)",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(
                  labelText: "Subject", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: allowedClasses.contains(_selectedClass) ? _selectedClass : null,
              decoration: const InputDecoration(
                  labelText: "Class", border: OutlineInputBorder()),
              items: allowedClasses
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedClass = v;
                // Section belongs to the previous class — always reset it.
                _selectedSection = null;
              }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: allowedSections.contains(_selectedSection) ? _selectedSection : null,
              decoration: InputDecoration(
                labelText: allowedSections.isEmpty
                    ? "Section (all sections of this class)"
                    : "Section (optional — leave empty for whole class)",
                border: const OutlineInputBorder(),
              ),
              items: allowedSections
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: allowedSections.isEmpty
                  ? null
                  : (v) => setState(() => _selectedSection = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _platform,
              decoration: const InputDecoration(
                  labelText: "Platform", border: OutlineInputBorder()),
              items: _platforms
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => _platform = v!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _linkController,
              decoration: const InputDecoration(
                  labelText: "Meeting Link (Zoom/Meet/YouTube URL)",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickDateTime,
              icon: const Icon(Icons.schedule),
              label: Text(_scheduledAt == null
                  ? "Select Date & Time"
                  : DateFormat('dd-MM-yyyy hh:mm a').format(_scheduledAt!)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : () => _createClass(structure),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.video_call),
                label: const Text("Schedule Class"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd-MM-yyyy hh:mm a');
    return Scaffold(
      appBar: AppBar(
        title: const Text("Online Classes"),
        backgroundColor: Colors.teal[800],
      ),
      body: SafeArea(child: StreamBuilder<AcademicStructure>(
        stream: ClassSectionService.watch(),
        builder: (context, structureSnap) {
          final structure = structureSnap.data ?? AcademicStructure.empty;
          final allowedClasses = _allowedClasses(structure);

          return Column(
            children: [
              // Both Admin and Teacher get the "create a new online class"
              // form — but Teacher only ever sees the class(es)/section(s)
              // they are actually assigned to.
              _buildForm(structure),
              const Divider(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: schoolCollection('online_classes')
                      .orderBy('scheduledAt', descending: true)
                      .limit(100)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var docs = snapshot.data?.docs ?? [];

                    // Teacher only sees online classes for the class(es)
                    // they're assigned to; Admin sees everything.
                    if (!widget.isAdmin) {
                      docs = docs.where((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        return allowedClasses.contains(d['className']);
                      }).toList();
                    }

                    if (docs.isEmpty) {
                      return const Center(child: Text("No online classes yet."));
                    }
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data() as Map<String, dynamic>;
                        final ts = (d['scheduledAt'] as Timestamp?)?.toDate();
                        final title = d['title'] ?? '';
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          child: ListTile(
                            leading: const Icon(Icons.video_camera_front,
                                color: Colors.teal),
                            title: Text(title),
                            subtitle: Text(
                                "${d['className']} ${(d['section'] ?? '').toString().isEmpty ? '(all sections)' : d['section']} • ${d['platform']}\n"
                                "${ts != null ? fmt.format(ts) : ''} • By ${d['createdByName'] ?? ''}"),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton(
                                  onPressed: () => _joinLink(d['link'] ?? ''),
                                  child: const Text("Join"),
                                ),
                                if (widget.isAdmin)
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: "Delete",
                                    onPressed: () =>
                                        _confirmDelete(doc.reference, title),
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
            ],
          );
        },
      )),
    );
  }
}
