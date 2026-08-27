import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'auth_service.dart';
import 'subscription_gate.dart';

class AddStaffPage extends StatefulWidget {
  // Pass staffId + staffData when opening this page to EDIT an existing
  // staff member. Leave both null to ADD a new staff member.
  final String? staffId;
  final Map<String, dynamic>? staffData;

  const AddStaffPage({super.key, this.staffId, this.staffData});

  @override
  State<AddStaffPage> createState() => _AddStaffPageState();
}

class _AddStaffPageState extends State<AddStaffPage> {
  final _nameController = TextEditingController();
  final _designationController = TextEditingController();
  final _salaryController = TextEditingController();
  final _contactController = TextEditingController();
  final _contactController2 = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  String? _selectedCategory; // Teaching or Non-Teaching
  String? _selectedGender;

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

  bool get _isEditing => widget.staffId != null;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final data = widget.staffData;
    if (data != null) {
      _nameController.text = data['name']?.toString() ?? '';
      _designationController.text = data['designation']?.toString() ?? '';
      _salaryController.text = data['salary']?.toString() ?? '';
      _contactController.text = data['contact']?.toString() ?? '';
      _contactController2.text = data['contact2']?.toString() ?? '';
      _emailController.text = data['email']?.toString() ?? '';
      _addressController.text = data['address']?.toString() ?? '';
      _selectedCategory = data['category']?.toString();
      _selectedGender = data['gender']?.toString();

      // New format: a list of {class, section} maps.
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
    }

    _loadAcademicStructure();
  }

  Future<void> _loadAcademicStructure() async {
    final doc =
        await schoolCollection('app_settings').doc('academic_structure').get();

    final data = doc.data() ?? {};

    setState(() {
      // NOTE: change 'classes' below to match your actual field name
      // if the top-level classes array is called something else.
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
    _nameController.dispose();
    _designationController.dispose();
    _salaryController.dispose();
    _contactController.dispose();
    _contactController2.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// Generates a new, globally-unique Staff Login ID (checks the
  /// collectionGroup to make sure it's unique across all schools, since
  /// login happens with this ID). While editing, if the staff member
  /// already has an ID it isn't regenerated (see _saveStaff).
  Future<String> _generateUniqueStaffLoginId() async {
    String newId = generateLoginId('T');
    int attempts = 0;
    while (attempts < 5) {
      final clash = await FirebaseFirestore.instance
          .collectionGroup('staff')
          .where('staffLoginId', isEqualTo: newId)
          .limit(1)
          .get();
      if (clash.docs.isEmpty) break;
      newId = generateLoginId('T');
      attempts++;
    }
    return newId;
  }

  Future<void> _showStaffCredentialsDialog(String loginId, String pin) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Staff Login Details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Share this Login ID and PIN with the staff member:"),
            const SizedBox(height: 12),
            SelectableText("Login ID: $loginId",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SelectableText("PIN: $pin",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            const Text(
              "The staff member will enter this ID and PIN on the "
              "'Teacher Login' screen in the app.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK, Noted")),
        ],
      ),
    );
  }

  Future<void> _saveStaff() async {
    if (_isSaving) return;
    if (!await SubscriptionGuard.ensureActive(context)) return;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please enter the staff name."),
          backgroundColor: Colors.red));
      return;
    }
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select a Category (Teaching / Non-Teaching)."),
          backgroundColor: Colors.red));
      return;
    }
    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select a Gender."),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final isTeaching = _selectedCategory == 'Teaching';

      final staffData = {
        'name': _nameController.text.trim(),
        'designation': _designationController.text.trim(),
        'salary': _salaryController.text.trim(),
        'contact': _contactController.text.trim(),
        'contact2': _contactController2.text.trim(),
        'email': _emailController.text.trim(),
        'address': _addressController.text.trim(),
        'category': _selectedCategory,
        'gender': _selectedGender,
        // Only Teaching staff get classes/sections assigned; Non-Teaching stays empty.
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
      };

      // Staff Login ID + PIN (instead of OTP/SMS) — only relevant for
      // Teaching staff, since only teachers use the "Teacher Login" screen.
      // Non-Teaching staff never get login credentials generated.
      String? newLoginId;
      String? newPin;
      final existingLoginId = widget.staffData?['staffLoginId']?.toString();

      if (isTeaching) {
        if (_isEditing &&
            existingLoginId != null &&
            existingLoginId.isNotEmpty) {
          // Credentials already exist — leave them untouched.
        } else {
          newLoginId = await _generateUniqueStaffLoginId();
          newPin = generatePin();
          staffData['staffLoginId'] = newLoginId;
          staffData['staffPin'] = newPin;
        }
      } else if (_isEditing &&
          existingLoginId != null &&
          existingLoginId.isNotEmpty) {
        // Category changed away from Teaching — remove any previously
        // generated login credentials, since Non-Teaching staff shouldn't
        // have them.
        staffData['staffLoginId'] = FieldValue.delete();
        staffData['staffPin'] = FieldValue.delete();
      }

      if (_isEditing) {
        await schoolCollection('staff').doc(widget.staffId).update(staffData);
      } else {
        await schoolCollection('staff').add(staffData);
      }

      if (newLoginId != null && newPin != null) {
        await _showStaffCredentialsDialog(newLoginId, newPin);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error saving staff: $e"),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? "Edit Staff" : "Add New Staff")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Staff Name")),
            TextField(
                controller: _designationController,
                decoration: const InputDecoration(labelText: "Designation")),
            TextField(
                controller: _salaryController,
                decoration: const InputDecoration(labelText: "Salary")),
            TextField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: "Contact No")),
            TextField(
                controller: _contactController2,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: "Contact No 2 (Optional)")),
            TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: "Email")),
            TextField(
                controller: _addressController,
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
                onPressed: _isSaving ? null : _saveStaff,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? "UPDATE STAFF" : "SAVE STAFF")),
            const SizedBox(height: 24), // So it doesn't hide behind the gesture nav bar
          ]),
        ),
      ),
    );
  }
}
