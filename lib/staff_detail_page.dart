import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'auth_service.dart';
import 'subscription_gate.dart';

class StaffDetailPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const StaffDetailPage({super.key, required this.docId, required this.data});

  @override
  State<StaffDetailPage> createState() => _StaffDetailPageState();
}

class _StaffDetailPageState extends State<StaffDetailPage> {
  late TextEditingController _name, _designation, _salary, _contact, _contact2, _email, _address;
  String? _selectedGender;
  String? _selectedCategory;

  // Multiple class/section assignments for a Teaching staff member.
  // Each entry looks like: {'class': '6', 'section': 'A'}
  List<Map<String, String>> _assignedClasses = [];

  // Values currently picked in the "add assignment" row (not yet added).
  String? _pickerClass;
  String? _pickerSection;

  // Loaded once from app_settings/academic_structure
  List<String> _allClasses = [];
  Map<String, dynamic> _sectionsByClass = {};
  bool _loadingStructure = true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.data['name']?.toString() ?? '');
    _designation = TextEditingController(
        text: widget.data['designation']?.toString() ?? '');
    _salary =
        TextEditingController(text: widget.data['salary']?.toString() ?? '');
    _contact =
        TextEditingController(text: widget.data['contact']?.toString() ?? '');
    _contact2 = TextEditingController(
        text: widget.data['contact2']?.toString() ?? '');
    _email =
        TextEditingController(text: widget.data['email']?.toString() ?? '');
    _address =
        TextEditingController(text: widget.data['address']?.toString() ?? '');
    _selectedGender = widget.data['gender']?.toString();
    _selectedCategory = widget.data['category']?.toString();

    // New format: a list of {class, section} maps.
    final data = widget.data;
    if (data['assignedClasses'] is List) {
      _assignedClasses =
          List<dynamic>.from(data['assignedClasses'] as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return {
          'class': m['class']?.toString() ?? '',
          'section': m['section']?.toString() ?? '',
        };
      }).toList();
    } else if (data['assignedClass'] != null) {
      // Backward compatibility with old single-assignment records.
      _assignedClasses = [
        {
          'class': data['assignedClass'].toString(),
          'section': data['assignedSection']?.toString() ?? '',
        }
      ];
    }

    _loadAcademicStructure();
  }

  Future<void> _loadAcademicStructure() async {
    final doc =
        await schoolCollection('app_settings').doc('academic_structure').get();

    final data = doc.data() ?? {};

    setState(() {
      _allClasses = List<String>.from(data['classes'] ?? []);
      _sectionsByClass =
          Map<String, dynamic>.from(data['sectionsByClass'] ?? {});
      _loadingStructure = false;
    });
  }

  List<String> get _sectionsForPickerClass {
    if (_pickerClass == null) return [];
    final sections = _sectionsByClass[_pickerClass];
    if (sections == null) return [];
    return List<String>.from(sections);
  }

  void _addAssignment() {
    if (_pickerClass == null) return;

    final entry = {
      'class': _pickerClass!,
      'section': _pickerSection ?? '',
    };

    final alreadyAdded = _assignedClasses.any((e) =>
        e['class'] == entry['class'] && e['section'] == entry['section']);

    if (alreadyAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This class/section is already added.')),
      );
      return;
    }

    setState(() {
      _assignedClasses.add(entry);
      _pickerClass = null;
      _pickerSection = null;
    });
  }

  void _removeAssignment(int index) {
    setState(() => _assignedClasses.removeAt(index));
  }

  /// Assigns every class (and every section within each class, if the
  /// class has sections) to this teacher in one click, skipping anything
  /// that's already in the list.
  void _assignAllClasses() {
    final List<Map<String, String>> newEntries = [];

    for (final c in _allClasses) {
      final rawSections = _sectionsByClass[c];
      final sections = (rawSections is List && rawSections.isNotEmpty)
          ? List<String>.from(rawSections.map((s) => s.toString()))
          : <String>[''];

      for (final s in sections) {
        final alreadyAdded = _assignedClasses.any(
                (e) => e['class'] == c && e['section'] == s) ||
            newEntries.any((e) => e['class'] == c && e['section'] == s);
        if (!alreadyAdded) {
          newEntries.add({'class': c, 'section': s});
        }
      }
    }

    if (newEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All classes are already assigned.')),
      );
      return;
    }

    setState(() {
      _assignedClasses.addAll(newEntries);
      _pickerClass = null;
      _pickerSection = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _designation.dispose();
    _salary.dispose();
    _contact.dispose();
    _contact2.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _updateStaff() async {
    if (!await SubscriptionGuard.ensureActive(context)) return;
    final isTeaching = _selectedCategory == 'Teaching';

    await schoolCollection('staff').doc(widget.docId).update({
      'name': _name.text.trim(),
      'designation': _designation.text.trim(),
      'salary': _salary.text.trim(),
      'contact': _contact.text.trim(),
      'contact2': _contact2.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'gender': _selectedGender,
      'category': _selectedCategory,
      // Only Teaching staff keep classes/sections assigned; Non-Teaching stays empty.
      'assignedClasses': isTeaching ? _assignedClasses : [],
      // Kept for backward compatibility with any older screens/reports that
      // still read a single assignedClass/assignedSection field. This just
      // mirrors the first entry of assignedClasses.
      'assignedClass': isTeaching && _assignedClasses.isNotEmpty
          ? _assignedClasses.first['class']
          : null,
      'assignedSection': isTeaching && _assignedClasses.isNotEmpty
          ? _assignedClasses.first['section']
          : null,
    });
    if (mounted) Navigator.pop(context);
  }

  /// If staff/parent forgets their PIN, office can view it here, or
  /// generate a new one with "Reset PIN" (Login ID stays the same, only
  /// the PIN changes). Only applicable to Teaching staff — Non-Teaching
  /// staff don't get login credentials.
  Future<void> _showLoginCredentials() async {
    if (_selectedCategory != 'Teaching') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Login credentials are only used by Teaching staff.")));
      return;
    }

    String loginId = widget.data['staffLoginId']?.toString() ?? '';
    String pin = widget.data['staffPin']?.toString() ?? '';

    if (loginId.isEmpty) {
      // Old record that didn't have these fields yet — create them now.
      loginId = generateLoginId('T');
      pin = generatePin();
      await schoolCollection('staff').doc(widget.docId).set(
        {'staffLoginId': loginId, 'staffPin': pin},
        SetOptions(merge: true),
      );
      setState(() {
        widget.data['staffLoginId'] = loginId;
        widget.data['staffPin'] = pin;
      });
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Login Credentials"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                  "Login ID: ${widget.data['staffLoginId']}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              SelectableText("PIN: ${widget.data['staffPin']}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final newPin = generatePin();
                await schoolCollection('staff')
                    .doc(widget.docId)
                    .set({'staffPin': newPin}, SetOptions(merge: true));
                widget.data['staffPin'] = newPin;
                setDialogState(() {});
                if (mounted) setState(() {});
              },
              child: const Text("Reset PIN"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Close"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Staff Details"),
        actions: [
          if (_selectedCategory == 'Teaching')
            IconButton(
              tooltip: "Login Credentials",
              icon: const Icon(Icons.key),
              onPressed: _showLoginCredentials,
            ),
        ],
      ),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: "Name")),
            TextField(
                controller: _designation,
                decoration: const InputDecoration(labelText: "Designation")),
            TextField(
                controller: _salary,
                decoration: const InputDecoration(labelText: "Salary")),
            TextField(
                controller: _contact,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: "Contact")),
            TextField(
                controller: _contact2,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: "Contact No 2 (Optional)")),
            TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: "Email")),
            TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: "Address")),
            DropdownButtonFormField(
              decoration: const InputDecoration(labelText: "Gender"),
              initialValue: _selectedGender,
              items: ['Male', 'Female']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedGender = v),
            ),
            DropdownButtonFormField(
              decoration: const InputDecoration(labelText: "Category"),
              initialValue: _selectedCategory,
              items: ['Teaching', 'Non-Teaching']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedCategory = v;
                if (v != 'Teaching') {
                  _assignedClasses = [];
                  _pickerClass = null;
                  _pickerSection = null;
                }
              }),
            ),
            if (_selectedCategory == 'Teaching') ...[
              const SizedBox(height: 10),
              if (_loadingStructure)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_allClasses.isEmpty)
                const Text("No classes found in academic structure.")
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Assigned Classes",
                        style: Theme.of(context).textTheme.titleSmall),
                    TextButton.icon(
                      onPressed: _assignAllClasses,
                      icon: const Icon(Icons.playlist_add_check, size: 18),
                      label: const Text("Assign All Classes"),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Chips for already-added class/section assignments.
                if (_assignedClasses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text("No classes assigned yet.",
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(_assignedClasses.length, (i) {
                      final a = _assignedClasses[i];
                      final label = a['section']!.isNotEmpty
                          ? "${a['class']} - ${a['section']}"
                          : a['class']!;
                      return Chip(
                        label: Text(label),
                        onDeleted: () => _removeAssignment(i),
                      );
                    }),
                  ),
                const SizedBox(height: 10),
                // Row to pick a new class/section and add it to the list.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: "Class"),
                        initialValue: _pickerClass,
                        items: _allClasses
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _pickerClass = v;
                          _pickerSection = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _sectionsForPickerClass.isEmpty
                          ? DropdownButtonFormField<String>(
                              decoration:
                                  const InputDecoration(labelText: "Section"),
                              items: const [],
                              onChanged: null,
                            )
                          : DropdownButtonFormField<String>(
                              decoration:
                                  const InputDecoration(labelText: "Section"),
                              initialValue: _pickerSection,
                              items: _sectionsForPickerClass
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _pickerSection = v),
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      tooltip: "Add class",
                      onPressed: _pickerClass == null ? null : _addAssignment,
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: _updateStaff, child: const Text("UPDATE STAFF"))
          ])),
    );
  }
}
