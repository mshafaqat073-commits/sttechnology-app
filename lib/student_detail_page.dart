import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'school_context.dart';
import 'auth_service.dart';
import 'subscription_gate.dart';
import 'admission_form_pdf.dart';

class StudentDetailPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const StudentDetailPage({super.key, required this.docId, required this.data});

  @override
  State<StudentDetailPage> createState() => _StudentDetailPageState();
}

class _StudentDetailPageState extends State<StudentDetailPage> {
  // Controllers for all fields
  final TextEditingController _formNoController = TextEditingController();
  final TextEditingController _rollNoController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sCNICController = TextEditingController();
  final TextEditingController _fNameController = TextEditingController();
  final TextEditingController _fCNICController = TextEditingController();
  final TextEditingController _pAddressController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _religionController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _contactController2 = TextEditingController();
  final TextEditingController _preSchoolController = TextEditingController();
  final TextEditingController _addFeeController = TextEditingController();
  final TextEditingController _leavingReasonController =
      TextEditingController();

  String? _selectedGender;
  String? _selectedClass;
  String? _selectedSection;
  String _ageDisplay = "";

  // Image handling variables
  File? _selectedImage;
  String _currentImageUrl = "";
  final ImagePicker _picker = ImagePicker();
  bool _isUpdating = false;

  final List<String> classesList = [
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
  static const String _addNewValue = '__add_new_class__';

  // Fixed academic (ascending) order — used to sort classesList in this order
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

  // Keeps known classes in their fixed ascending order,
  // and any custom/new class comes after them alphabetically
  void _sortClassesList() {
    classesList.sort((a, b) {
      final int ai = _baseClassesOrder.indexOf(a);
      final int bi = _baseClassesOrder.indexOf(b);
      if (ai == -1 && bi == -1) return a.compareTo(b);
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
  }

  // Section list is also mutable
  final List<String> sectionsList = [];
  static const String _addNewSectionValue = '__add_new_section__';

  @override
  void initState() {
    super.initState();
    // Set the old data into controllers and variables
    _formNoController.text = widget.data['formNo']?.toString() ?? "";
    _rollNoController.text = widget.data['rollNo']?.toString() ?? "";
    _dateController.text = widget.data['date']?.toString() ?? "";
    _dobController.text = widget.data['dob']?.toString() ?? "";
    _nameController.text = widget.data['name']?.toString() ?? "";
    _sCNICController.text = widget.data['sCNIC']?.toString() ?? "";
    _fNameController.text = widget.data['fName']?.toString() ?? "";
    _fCNICController.text = widget.data['fCNIC']?.toString() ?? "";
    _pAddressController.text = widget.data['pAddress']?.toString() ?? "";
    _districtController.text = widget.data['district']?.toString() ?? "";
    _religionController.text = widget.data['religion']?.toString() ?? "";
    _contactController.text = widget.data['contactNo']?.toString() ?? "";
    _contactController2.text = widget.data['contactNo2']?.toString() ?? "";
    _preSchoolController.text = widget.data['preSchool']?.toString() ?? "";
    _addFeeController.text = widget.data['monthlyFee']?.toString() ?? " ";
    _leavingReasonController.text =
        widget.data['leavingReason']?.toString() ?? "";

    _selectedGender =
        widget.data['gender'] != "Not Selected" ? widget.data['gender'] : null;

    // If the student's class is custom (newly added from the admission
    // form), include it in the list too so it shows correctly here
    String? existingClass = widget.data['class']?.toString();
    if (existingClass != null &&
        existingClass.isNotEmpty &&
        existingClass != "Not Selected" &&
        !classesList.contains(existingClass)) {
      classesList.add(existingClass);
    }
    _sortClassesList();
    _selectedClass = classesList.contains(existingClass) ? existingClass : null;

    // Same logic for the section — add it to the list if it's custom
    String? existingSection = widget.data['section']?.toString();
    if (existingSection != null &&
        existingSection.isNotEmpty &&
        existingSection != "Not Selected" &&
        !sectionsList.contains(existingSection)) {
      sectionsList.add(existingSection);
    }
    _selectedSection =
        sectionsList.contains(existingSection) ? existingSection : null;
    _ageDisplay = widget.data['age']?.toString() ?? "";
    _currentImageUrl = widget.data['imageUrl']?.toString() ?? "";
  }

  // Parses the old "d-m-yyyy" format date string into a DateTime,
  // so the date picker opens with the correct initial date
  DateTime? _parseStoredDate(String value) {
    try {
      final parts = value.trim().split('-');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  void _calculateAge(DateTime birthDate) {
    DateTime today = DateTime.now();
    int years = today.year - birthDate.year;
    int months = today.month - birthDate.month;
    if (months < 0) {
      years--;
      months += 12;
    }
    setState(() => _ageDisplay = "$years Years, $months Months");
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _parseStoredDate(_dateController.text) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2101));
    if (picked != null) {
      setState(() => _dateController.text =
          "${picked.day}-${picked.month}-${picked.year}");
    }
  }

  Future<void> _selectDOB(BuildContext context) async {
    DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _parseStoredDate(_dobController.text) ?? DateTime(2015),
        firstDate: DateTime(1990),
        lastDate: DateTime.now());
    if (picked != null) {
      setState(() {
        _dobController.text = "${picked.day}-${picked.month}-${picked.year}";
        _calculateAge(picked);
      });
    }
  }

  // Function to pick an image
  Future<void> _showAddClassDialog() async {
    final TextEditingController newClassController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Add New Class"),
        content: TextField(
          controller: newClassController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter class name"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              String newClass = newClassController.text.trim();
              if (newClass.isNotEmpty) {
                setState(() {
                  if (!classesList.contains(newClass)) {
                    classesList.add(newClass);
                  }
                  _sortClassesList();
                  _selectedClass = newClass;
                });
              }
              Navigator.pop(dialogContext);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddSectionDialog() async {
    final TextEditingController newSectionController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Add New Section"),
        content: TextField(
          controller: newSectionController,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: "Enter section name (e.g. A, B, Red)"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              String newSection = newSectionController.text.trim();
              if (newSection.isNotEmpty) {
                setState(() {
                  if (!sectionsList.contains(newSection)) {
                    sectionsList.add(newSection);
                  }
                  _selectedSection = newSection;
                });
              }
              Navigator.pop(dialogContext);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  /// If, after this update, the student's new familyId matches another
  /// sibling that already has a Login ID + PIN, that same ID/PIN is
  /// reused here (so, e.g., correcting a typo in Father's Name/Contact
  /// can merge this student into the right family's shared login). If no
  /// other sibling shares this familyId, this student's own existing
  /// credentials are kept as-is, or a new Login ID + PIN is generated if
  /// this student doesn't have any yet.
  Future<Map<String, String>> _resolveParentCredentialsForFamily(
      String familyId) async {
    final existing = await schoolCollection('students')
        .where('familyId', isEqualTo: familyId)
        .limit(5)
        .get();
    for (final doc in existing.docs) {
      if (doc.id == widget.docId) continue; // Skip this same student
      final data = doc.data();
      final id = (data['parentLoginId'] ?? '').toString();
      final pin = (data['parentPin'] ?? '').toString();
      if (id.isNotEmpty && pin.isNotEmpty) {
        return {'id': id, 'pin': pin};
      }
    }

    // No sibling found under this familyId — keep this student's own
    // existing credentials untouched.
    final ownId = widget.data['parentLoginId']?.toString() ?? '';
    final ownPin = widget.data['parentPin']?.toString() ?? '';
    if (ownId.isNotEmpty && ownPin.isNotEmpty) {
      return {'id': ownId, 'pin': ownPin};
    }

    // This student never had credentials before — generate new ones,
    // checking the collectionGroup so the ID is unique across all schools.
    String newId = generateLoginId('P');
    int attempts = 0;
    while (attempts < 5) {
      final clash = await FirebaseFirestore.instance
          .collectionGroup('students')
          .where('parentLoginId', isEqualTo: newId)
          .limit(1)
          .get();
      if (clash.docs.isEmpty) break;
      newId = generateLoginId('P');
      attempts++;
    }
    return {'id': newId, 'pin': generatePin()};
  }

  Future<void> _updateStudent() async {
    if (!await SubscriptionGuard.ensureActive(context)) return;
    if (_nameController.text.isEmpty || _contactController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Student Name and Contact No are required!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isUpdating = true);

    try {
      String finalImageUrl = _currentImageUrl;

      // If the user selected a new picture, upload it to Cloudinary
      if (_selectedImage != null) {
        final cloudinary =
            CloudinaryPublic('niilo9ek', 'shafi073', cache: false);
        CloudinaryResponse response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(_selectedImage!.path,
              resourceType: CloudinaryResourceType.Image,
              folder: 'student_admissions'),
        );
        finalImageUrl = response.secureUrl;
      }

      // Recalculate Family ID if father's name or contact has changed
      String fNameValue = _fNameController.text.trim().toLowerCase();
      String phoneNumber = _contactController.text.trim();
      String phoneSuffix = (phoneNumber.length >= 4)
          ? phoneNumber.substring(phoneNumber.length - 4)
          : "0000";
      String finalFamilyId = "${fNameValue}_$phoneSuffix";

      // Keep the parent Login ID + PIN in sync with the (possibly new)
      // family — if Father's Name/Contact changed enough to match a
      // different family, this student's login now matches that
      // family's shared credentials instead of its old ones.
      final parentCreds =
          await _resolveParentCredentialsForFamily(finalFamilyId);

      // Update Firestore database
      await schoolCollection('students').doc(widget.docId).update({
        'formNo': int.tryParse(_formNoController.text) ?? 1,
        'rollNo': _rollNoController.text.trim(),
        'familyId': finalFamilyId,
        'parentLoginId': parentCreds['id'],
        'parentPin': parentCreds['pin'],
        'date': _dateController.text.trim(),
        'dob': _dobController.text.trim(),
        'age': _ageDisplay,
        'name': _nameController.text.trim(),
        'sCNIC': _sCNICController.text.trim(),
        'fName': _fNameController.text.trim(),
        'fCNIC': _fCNICController.text.trim(),
        'pAddress': _pAddressController.text.trim(),
        'district': _districtController.text.trim(),
        'religion': _religionController.text.trim(),
        'gender': _selectedGender ?? "Not Selected",
        'contactNo': phoneNumber,
        'contactNo2': _contactController2.text.trim(),
        'preSchool': _preSchoolController.text.trim(),
        'class': _selectedClass ?? "Not Selected",
        'section': _selectedSection ?? "Not Selected",
        'addFee': _addFeeController.text.trim(),
        'monthlyFee': double.tryParse(_addFeeController.text.trim()) ?? 0,
        'leavingReason': _leavingReasonController.text.trim(),
        'imageUrl': finalImageUrl,
      });

      // Keep the in-memory copy in sync too, so if this page is reopened
      // in the same session (or the credentials dialog is opened next),
      // it reflects the possibly-changed family/login instantly.
      widget.data['familyId'] = finalFamilyId;
      widget.data['parentLoginId'] = parentCreds['id'];
      widget.data['parentPin'] = parentCreds['pin'];

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Student Record Updated Successfully!"),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Error updating: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  /// If a parent forgets their PIN, the office can look it up here, or
  /// generate a new one with "Reset PIN". Resetting also syncs every
  /// sibling in this family to THIS student's own Login ID (fixing any
  /// mismatch) together with the new PIN, so everyone's login keeps
  /// working together.
  Future<void> _showParentLoginCredentials() async {
    String loginId = widget.data['parentLoginId']?.toString() ?? '';
    String pin = widget.data['parentPin']?.toString() ?? '';
    final familyId = widget.data['familyId']?.toString() ?? '';

    if (loginId.isEmpty) {
      loginId = generateLoginId('P');
      pin = generatePin();
      await schoolCollection('students').doc(widget.docId).set(
        {'parentLoginId': loginId, 'parentPin': pin},
        SetOptions(merge: true),
      );
      widget.data['parentLoginId'] = loginId;
      widget.data['parentPin'] = pin;
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Parent Login Credentials"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                  "Login ID: ${widget.data['parentLoginId']}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              SelectableText("PIN: ${widget.data['parentPin']}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                "Note: Any siblings' Login ID and PIN will be synced to "
                "this one.",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final newPin = generatePin();
                // This student's own Login ID becomes the shared/canonical
                // ID for the whole family — every sibling is set to use
                // this same Login ID + the new PIN, so a mismatch (e.g.
                // from siblings admitted before their family details
                // matched) gets corrected here too.
                final canonicalLoginId = loginId;
                if (familyId.isNotEmpty) {
                  final siblings = await schoolCollection('students')
                      .where('familyId', isEqualTo: familyId)
                      .get();
                  final batch = FirebaseFirestore.instance.batch();
                  for (final doc in siblings.docs) {
                    batch.set(
                        doc.reference,
                        {
                          'parentLoginId': canonicalLoginId,
                          'parentPin': newPin,
                        },
                        SetOptions(merge: true));
                  }
                  await batch.commit();
                } else {
                  await schoolCollection('students').doc(widget.docId).set(
                      {
                        'parentLoginId': canonicalLoginId,
                        'parentPin': newPin,
                      },
                      SetOptions(merge: true));
                }
                widget.data['parentLoginId'] = canonicalLoginId;
                widget.data['parentPin'] = newPin;
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
          title: const Text("Edit Student Details"),
          backgroundColor: Colors.teal[800],
          actions: [
            IconButton(
              tooltip: "Parent Login Credentials",
              icon: const Icon(Icons.key),
              onPressed: _showParentLoginCredentials,
            ),
            IconButton(
              tooltip: "Preview / Print Admission Form",
              icon: const Icon(Icons.description_outlined),
              onPressed: () =>
                  showSavedAdmissionFormPreview(context, widget.data),
            ),
          ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Picture Selection & Preview Widget
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey[300],
                backgroundImage: _selectedImage != null
                    ? FileImage(_selectedImage!)
                    : (_currentImageUrl.isNotEmpty
                        ? NetworkImage(_currentImageUrl) as ImageProvider
                        : null),
                child: (_selectedImage == null && _currentImageUrl.isEmpty)
                    ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            const Text("Tap picture to change",
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),

            TextField(
                controller: _formNoController,
                decoration: const InputDecoration(labelText: "Form No")),
            TextField(
                controller: _rollNoController,
                decoration: const InputDecoration(labelText: "Roll No")),
            InkWell(
                onTap: () => _selectDate(context),
                child: TextField(
                    controller: _dateController,
                    enabled: false,
                    decoration: const InputDecoration(
                        labelText: "Admission Date",
                        suffixIcon: Icon(Icons.calendar_today)))),
            InkWell(
                onTap: () => _selectDOB(context),
                child: TextField(
                    controller: _dobController,
                    enabled: false,
                    decoration: const InputDecoration(
                        labelText: "Date of Birth",
                        suffixIcon: Icon(Icons.cake)))),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text("Age: $_ageDisplay",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.teal)),
            ),
            TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Student Name")),
            TextField(
                controller: _sCNICController,
                decoration: const InputDecoration(labelText: "Student CNIC")),
            TextField(
                controller: _fNameController,
                decoration: const InputDecoration(labelText: "Father Name")),
            TextField(
                controller: _fCNICController,
                decoration: const InputDecoration(labelText: "Father CNIC")),
            TextField(
                controller: _pAddressController,
                decoration:
                    const InputDecoration(labelText: "Permanent Address")),
            TextField(
                controller: _districtController,
                decoration: const InputDecoration(labelText: "District")),
            TextField(
                controller: _religionController,
                decoration: const InputDecoration(labelText: "Religion")),

            DropdownButtonFormField<String>(
              initialValue: _selectedGender,
              decoration: const InputDecoration(labelText: "Gender"),
              items: ['Male', 'Female']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedGender = v),
            ),

            TextField(
                controller: _contactController,
                decoration: const InputDecoration(labelText: "Contact No 1")),
            TextField(
                controller: _contactController2,
                decoration: const InputDecoration(
                    labelText: "Contact No 2 (Optional)")),
            TextField(
                controller: _preSchoolController,
                decoration:
                    const InputDecoration(labelText: "Pre School Name")),

            DropdownButtonFormField<String>(
              initialValue: _selectedClass,
              decoration: const InputDecoration(labelText: "Class"),
              items: [
                ...classesList
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))),
                const DropdownMenuItem(
                  value: _addNewValue,
                  child: Text("+ Add New Class",
                      style: TextStyle(
                          color: Colors.teal, fontWeight: FontWeight.bold)),
                ),
              ],
              onChanged: (v) {
                if (v == _addNewValue) {
                  _showAddClassDialog();
                } else {
                  setState(() => _selectedClass = v);
                }
              },
            ),

            DropdownButtonFormField<String>(
              initialValue: _selectedSection,
              decoration: const InputDecoration(labelText: "Section"),
              items: [
                ...sectionsList
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))),
                const DropdownMenuItem(
                  value: _addNewSectionValue,
                  child: Text("+ Add New Section",
                      style: TextStyle(
                          color: Colors.teal, fontWeight: FontWeight.bold)),
                ),
              ],
              onChanged: (v) {
                if (v == _addNewSectionValue) {
                  _showAddSectionDialog();
                } else {
                  setState(() => _selectedSection = v);
                }
              },
            ),

            TextField(
                controller: _addFeeController,
                decoration: const InputDecoration(labelText: "Monthly Fee"),
                keyboardType: TextInputType.number),
            TextField(
                controller: _leavingReasonController,
                decoration: const InputDecoration(
                    labelText: "Reason of School Leaving")),
          ],
        ),
      ),
      // The Update button is no longer inside the form (below, following
      // the scroll), but placed in the Scaffold's bottomNavigationBar —
      // this way it's always fixed/visible at the bottom of the screen,
      // no matter how long the form is or where the user has scrolled to.
      // Previously the button was after the form's last field, so you had
      // to scroll all the way down through the whole form just to reach
      // the button.
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isUpdating ? null : _updateStudent,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[800]),
              child: _isUpdating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text("Updating...",
                            style: TextStyle(color: Colors.white)),
                      ],
                    )
                  : const Text("UPDATE RECORD",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
    );
  }
}
