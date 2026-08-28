import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'set_fee_page.dart';
import 'class_section_service.dart';
import 'manage_classes_sections_dialog.dart';
import 'package:flutter/foundation.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'auth_service.dart';
import 'subscription_gate.dart';
import 'pdf_preview_helper.dart';

class AdmissionPage extends StatefulWidget {
  const AdmissionPage({super.key});

  @override
  State<AdmissionPage> createState() => _AdmissionPageState();
}

class _AdmissionPageState extends State<AdmissionPage> {
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

  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  String? _selectedGender;
  String? _selectedClass;
  String? _selectedSection;
  String _ageDisplay = "";

  // The class list is no longer hardcoded — it now loads from
  // ClassSectionService (Firestore: app_settings/academic_structure), so
  // the same list is always used across the whole project (set_fee_page,
  // pay_fee_page, reports, filters, etc.). This is just a runtime cache.
  final List<String> _classList = [];
  static const String _addNewValue = '__add_new_class__';

  // Sections are no longer GLOBAL — each class has its own separate
  // sections (e.g. 'One' -> [A, B, C], 'Playgroup' -> [A]). Whenever the
  // class changes, this getter automatically shows that new class's
  // sections — so the previous class's section never carries over to the
  // next class.
  Map<String, List<String>> _sectionsByClass = {};
  List<String> get _sectionList => _sectionsByClass[_selectedClass] ?? [];
  static const String _addNewSectionValue = '__add_new_section__';

  bool _loadingAcademicStructure = true;

  @override
  void initState() {
    super.initState();
    _getLatestFormNo();
    _getLatestRollNo();
    _loadAcademicStructure();
  }

  // Loads the shared classes list and each class's own sections from
  // Firestore. If the classes list is completely empty (meaning this is
  // the app's first-ever admission and setup has never been done), it
  // forces the "Setup Classes & Sections" dialog before showing the
  // form — you can't proceed without it, so correct classes and each
  // class's sections are set up from the start and used across the whole
  // project.
  Future<void> _loadAcademicStructure() async {
    var structure = await ClassSectionService.getAll();
    if (!mounted) return;
    setState(() {
      _classList
        ..clear()
        ..addAll(structure.classes);
      _sectionsByClass = structure.sectionsByClass;
      _loadingAcademicStructure = false;
    });

    if (_classList.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showInitialSetupDialog();
      });
    }
  }

  // Called as soon as any class is selected/added from the class
  // dropdown. The section is always reset because each class has its own
  // separate sections — leaving the previous class's section selected
  // (which doesn't exist in the new class) would create an invalid
  // state. This is why the section list also automatically becomes
  // correct as soon as the class changes during a session.
  void _onClassChanged(String? newClass) {
    setState(() {
      _selectedClass = newClass;
      _selectedSection = null;
    });
    _getLatestRollNoForClass(newClass);
  }

  // The setup dialog shown before the admission form the first time (when
  // no Class/Section has been set up yet). This now just calls the shared
  // showManageClassesSectionsDialog() (manage_classes_sections_dialog.dart)
  // — the same dialog is also used from the Settings page's "Manage
  // Classes & Sections" button, so both places have exactly the same UI
  // and Firestore save logic. barrierDismissible: false is set here so
  // the user can't reach the admission form the first time without
  // completing setup.
  Future<void> _showInitialSetupDialog() async {
    final result = await showManageClassesSectionsDialog(
      context,
      current: AcademicStructure(
          classes: _classList, sectionsByClass: _sectionsByClass),
      barrierDismissible: false,
      description:
          "This is a one-time setup — the classes and their sections set here will be used throughout the app (fees, reports, admission, etc.).",
    );
    if (result == null || !mounted) return;
    setState(() {
      _classList
        ..clear()
        ..addAll(result.classes);
      _sectionsByClass = result.sectionsByClass;
    });
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

  Future<void> _getLatestFormNo() async {
    try {
      var doc = await schoolCollection('counters').doc('admission').get();
      int lastNo = (doc.exists) ? (doc.get('lastFormNo') ?? 0) : 0;
      _formNoController.text = (lastNo + 1).toString();
    } catch (e) {
      _formNoController.text = "1";
    }
  }

  Future<void> _getLatestRollNo() async {
    // Roll No is no longer auto-incremented globally, but within the
    // SELECTED CLASS — so each class starts its own 1,2,3... Roll No
    // series (e.g. if the "Blue" class already has 5 students, the next
    // admission should get Roll No 6).
    await _getLatestRollNoForClass(_selectedClass);
  }

  Future<void> _getLatestRollNoForClass(String? className) async {
    if (className == null || className.isEmpty) {
      // Roll No stays empty until a Class is selected — because this
      // number only has meaning within that class.
      setState(() => _rollNoController.text = "");
      return;
    }
    try {
      var existing = await schoolCollection('students')
          .where('class', isEqualTo: className)
          .get();
      setState(() {
        _rollNoController.text = (existing.docs.length + 1).toString();
      });
    } catch (e) {
      setState(() => _rollNoController.text = "1");
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
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
        initialDate: DateTime(2015),
        firstDate: DateTime(1990),
        lastDate: DateTime.now());
    if (picked != null) {
      setState(() {
        _dobController.text = "${picked.day}-${picked.month}-${picked.year}";
        _calculateAge(picked);
      });
    }
  }

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
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              String newClass = newClassController.text.trim();
              if (newClass.isNotEmpty) {
                setState(() {
                  if (!_classList.contains(newClass)) {
                    _classList.add(newClass);
                  }
                  _sectionsByClass.putIfAbsent(newClass, () => []);
                  _selectedClass = newClass;
                  // A new class was just selected — the previous class's
                  // sections don't apply to it, so reset the section.
                  _selectedSection = null;
                });
                // The new class is still completely empty, so Roll No
                // will start from 1.
                _getLatestRollNoForClass(newClass);
                // Also save it to Firestore so this class is available
                // across the whole project (other pages too).
                ClassSectionService.addClass(newClass);
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
    // Sections now belong to each class individually, so a class must be
    // selected first — otherwise there's no way to know which class this
    // section belongs to.
    if (_selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "First select a Class, then add its Section.")));
      return;
    }
    final String className = _selectedClass!;
    final TextEditingController newSectionController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Add New Section for $className"),
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
                  List<String> current =
                      List<String>.from(_sectionsByClass[className] ?? []);
                  if (!current.contains(newSection)) current.add(newSection);
                  _sectionsByClass[className] = current;
                  _selectedSection = newSection;
                });
                // Also save it to Firestore for this same class — only
                // this class's sections get updated, other classes stay
                // untouched.
                ClassSectionService.addSectionToClass(className, newSection);
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
    if (image != null) setState(() => _selectedImage = File(image.path));
  }

  // Helper method for Table Rows in PDF
  pw.TableRow _buildPdfRow(String label, String value) {
    return pw.TableRow(children: [
      pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(label,
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
      pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 10))),
    ]);
  }

  Future<void> _generateAdmissionPDF() async {
      // Current school's logo (from Settings > School Logo, otherwise
      // default)
    Uint8List? logoBytes;
    try {
      logoBytes = await getSchoolLogoBytes();
    } catch (e) {
      logoBytes = null; // If the logo isn't found, the PDF is built without it
    }
    final pw.MemoryImage? logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    final pdf = pw.Document();
    pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 2)),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logoImage != null)
                        pw.Container(
                          margin: const pw.EdgeInsets.only(right: 12),
                          width: 55,
                          height: 55,
                          child: pw.Image(logoImage),
                        ),
                      pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text(currentSchoolDisplayName(),
                              style: pw.TextStyle(
                                  fontSize: 22,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.Text("(Admission form)",
                              style: const pw.TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.black),
                      children: [
                        _buildPdfRow("Name of candidate", _nameController.text),
                        _buildPdfRow("Student C.N.I.C.", _sCNICController.text),
                        _buildPdfRow("Father's Name", _fNameController.text),
                        _buildPdfRow(
                            "Father's C.N.I.C.", _fCNICController.text),
                        _buildPdfRow(
                            "Permanent Address", _pAddressController.text),
                        _buildPdfRow("Date of Birth",
                            "${_dobController.text} (Age: $_ageDisplay)"),
                        _buildPdfRow("District", _districtController.text),
                        _buildPdfRow("Religion", _religionController.text),
                        _buildPdfRow("Gender", _selectedGender ?? "N/A"),
                        _buildPdfRow("Contact no. 1", _contactController.text),
                        _buildPdfRow(
                            "Contact no. 2",
                            _contactController2.text.isEmpty
                                ? "N/A"
                                : _contactController2.text),
                      ]),
                  pw.SizedBox(height: 10),
                  pw.Text("Pervious Institute Information",
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.black),
                      children: [
                        _buildPdfRow("Section", _selectedSection ?? "N/A"),
                        _buildPdfRow("School Name", _preSchoolController.text),
                        _buildPdfRow("Reason of school leaving",
                            _leavingReasonController.text),
                      ]),
                  pw.SizedBox(height: 15),
                  pw.Text(
                      "1. Attached three passport size pictures.\n2. B form two copy.\n3. Father CNIC two copy.\n4. Previous School leaving certificate.",
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(height: 15),
                  pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(border: pw.Border.all()),
                      child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("For Office use",
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 12)),
                            pw.Text(
                                "Admission date: ${_dateController.text}    Admission fee: ${_addFeeController.text}    Class name: ${_selectedClass ?? 'N/A'}    Section: ${_selectedSection ?? 'N/A'}"),
                            pw.SizedBox(height: 20),
                            pw.Align(
                                alignment: pw.Alignment.bottomRight,
                                child: pw.Text("Principal signature ________")),
                          ])),
                ]),
          );
        }));

    final pdfBytes = await pdf.save();

    if (!mounted) return;

    if (kIsWeb) {
      // Don't use File / path_provider on Web
      await showPdfPreviewPage(
        context,
        title: "Admission Slip Preview",
        shareFileName: "admission_${_nameController.text}.pdf",
        build: (PdfPageFormat format) async => pdfBytes,
      );
    } else {
      // Old File-based method on Android/iOS/Desktop
      final output = await getTemporaryDirectory();
      final file = File(
        "${output.path}/admission_${_nameController.text}.pdf",
      );

      await file.writeAsBytes(pdfBytes);

      if (mounted) {
        await _showPdfActionSheet(
          file,
          "Admission Slip for ${_nameController.text}",
        );
      }
    }
  }

  // Preview and Send options both in one place
  Future<void> _showPdfActionSheet(File file, String shareText) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text("Preview"),
              onTap: () async {
                Navigator.pop(context);
                // showPdfPreviewPage opens an in-app preview SCREEN
                // (the PdfPreview widget) — on Windows/macOS/Linux
                // Desktop, Printing.layoutPdf() has no preview of its
                // own (it just opens the raw OS printer dialog), which
                // is why the preview "didn't show up" there before.
                // This widget gives a guaranteed, identical preview on
                // all three platforms.
                await showPdfPreviewPage(
                  context,
                  title: "Admission Slip Preview",
                  shareFileName: "admission_${_nameController.text}.pdf",
                  build: (format) async => file.readAsBytes(),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text("Send"),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await Share.shareXFiles([XFile(file.path)],
                      text: shareText);
                } catch (e) {
                  // On Windows (especially when not packaged as
                  // MSIX), share_plus's native "Share" sheet isn't
                  // available and this can fail. In that case, tell
                  // the user where the file was saved so they can
                  // attach it manually via WhatsApp/Email.
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          "Direct Send is not supported on this device. "
                          "File saved at:\n${file.path}"),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 6),
                    ));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendWhatsAppMessage(String phone, String name,
      {String? parentLoginId, String? parentPin}) async {
    String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '92${cleanPhone.substring(1)}';
    } else if (!cleanPhone.startsWith('92')) cleanPhone = '92$cleanPhone';
    String credsLine = (parentLoginId != null && parentPin != null)
        ? "\nApp Parent Login -> ID: $parentLoginId, PIN: $parentPin"
        : "";
    String message = Uri.encodeComponent(
        "Welcome, $name! Your admission (Form No: ${_formNoController.text}) is confirmed.$credsLine");
    final Uri whatsappUrl =
        Uri.parse("https://wa.me/$cleanPhone?text=$message");
    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    }
  }

  bool _isSaving = false;

  /// If this family (finalFamilyId) already has an active/inactive
  /// student with a parentLoginId, returns that same ID+PIN (so siblings
  /// log in with one shared ID). Otherwise generates and returns a new,
  /// globally-unique Login ID + random 4-digit PIN.
  Future<Map<String, String>> _getOrCreateParentCredentials(
      String familyId) async {
    final existing = await schoolCollection('students')
        .where('familyId', isEqualTo: familyId)
        .limit(5)
        .get();
    for (final doc in existing.docs) {
      final data = doc.data();
      final id = (data['parentLoginId'] ?? '').toString();
      final pin = (data['parentPin'] ?? '').toString();
      if (id.isNotEmpty && pin.isNotEmpty) {
        return {'id': id, 'pin': pin};
      }
    }

    // Generating a new ID — check the collectionGroup to make sure it
    // isn't already in use anywhere (very unlikely, but login IDs must be
    // unique across all schools).
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

  /// Shows the Login ID + PIN to the office/parent after saving, so they
  /// can pass it on to the parent. The dialog doesn't close until "OK,
  /// Noted" is pressed — this prevents the credentials from being missed
  /// by accident.
  Future<void> _showParentCredentialsDialog(
      String studentName, String loginId, String pin) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Parent Login Details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Give these Login ID and PIN to $studentName's parent:"),
            const SizedBox(height: 12),
            SelectableText("Login ID: $loginId",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SelectableText("PIN: $pin",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            const Text(
              "The parent will open the app and enter this same ID and "
              "PIN under 'Parent Login'. If a sibling is already admitted, "
              "this same ID/PIN will work for them too.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK, Noted"),
          ),
        ],
      ),
    );
  }

  // Checks the students collection for an existing ACTIVE student with
  // the same father's CNIC/ID card number, OR the same student name
  // together with the same father's name on the SAME record. Returns a
  // human-readable description of which field matched (e.g.
  // "student name"), or null if nothing matched.
  Future<String?> _findDuplicateStudent() async {
    final name = _nameController.text.trim();
    final fName = _fNameController.text.trim();
    final fCNIC = _fCNICController.text.trim();

    // Father's CNIC/ID card number is on its own a strong unique signal.
    if (fCNIC.isNotEmpty) {
      final cnicSnap = await schoolCollection('students')
          .where('fCNIC', isEqualTo: fCNIC)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (cnicSnap.docs.isNotEmpty) {
        return "father's CNIC/ID card number";
      }
    }

    // Student name AND father name must match on the SAME record to
    // count as a duplicate — this must be a single compound query,
    // not two separate existence checks, otherwise two different
    // students (one matching on name, another matching on father
    // name) would be wrongly flagged as a duplicate of each other.
    if (name.isNotEmpty && fName.isNotEmpty) {
      final nameFatherSnap = await schoolCollection('students')
          .where('name', isEqualTo: name)
          .where('fName', isEqualTo: fName)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (nameFatherSnap.docs.isNotEmpty) {
        return "student name and father name";
      }
    }

    return null;
  }

  Future<void> _addStudent() async {
    if (_isSaving) return;

    // Subscription Roadmap: if expired, block new admissions (view-only
    // mode) — see subscription_gate.dart.
    if (!await SubscriptionGuard.ensureActive(context)) return;

    if (_nameController.text.isEmpty ||
        _dateController.text.isEmpty ||
        _contactController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please fill all required fields!"),
          backgroundColor: Colors.red));
      return;
    }

    // Duplicate check — same student name, same father name, or same
    // father CNIC/ID card number already exists in the students
    // collection. Only checks students whose status is still 'active'
    // (a student marked 'left' shouldn't block a genuinely new admission
    // with the same name).
    setState(() => _isSaving = true);
    final duplicateField = await _findDuplicateStudent();
    if (duplicateField != null) {
      setState(() => _isSaving = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Duplicate Entry Found"),
            content: Text(
                "A student with the same $duplicateField already exists. "
                "Please check the existing record before adding a new one."),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Start loading (already true from the duplicate-check step above)

    // --- Calculate Family ID Logic outside the Map ---
    String fNameValue = _fNameController.text.trim().toLowerCase();
    String phoneNumber = _contactController.text.trim();
    String phoneSuffix = (phoneNumber.length >= 4)
        ? phoneNumber.substring(phoneNumber.length - 4)
        : "0000";
    String finalFamilyId = "${fNameValue}_$phoneSuffix";
    // ----------------------------------------------------

    final cloudinary = CloudinaryPublic('niilo9ek', 'shafi073', cache: false);
    try {
      // --- Parent Login ID + PIN (instead of OTP) ---
      // If a sibling from this same family (finalFamilyId) is already
      // admitted, reuse that same Login ID/PIN (so one parent can view
      // all their children's data with one ID). Otherwise generate a new
      // one.
      final parentCreds = await _getOrCreateParentCredentials(finalFamilyId);
      String imageUrl = "";
      if (_selectedImage != null) {
        CloudinaryResponse response = await cloudinary.uploadFile(
            CloudinaryFile.fromFile(_selectedImage!.path,
                resourceType: CloudinaryResourceType.Image,
                folder: 'student_admissions'));
        imageUrl = response.secureUrl;
      }

      // Map is now clean
      Map<String, dynamic> studentData = {
        'formNo': int.tryParse(_formNoController.text) ?? 1,
        'rollNo': _rollNoController.text.trim(),
        'familyId': finalFamilyId, // Using the variable here
        'date': _dateController.text,
        'dob': _dobController.text,
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
        'parentLoginId': parentCreds['id'],
        'parentPin': parentCreds['pin'],
        'preSchool': _preSchoolController.text.trim(),
        'class': _selectedClass ?? "Not Selected",
        'section': _selectedSection ?? "Not Selected",
        'addFee': _addFeeController.text.trim(),
        'leavingReason': _leavingReasonController.text.trim(),
        'dues': 0,
        'status': 'active',
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
      };

      var docRef = await schoolCollection('students').add(studentData);
      await schoolCollection('counters').doc('admission').set(
          {'lastFormNo': FieldValue.increment(1)}, SetOptions(merge: true));

      if (mounted) {
        await _sendWhatsAppMessage(
          _contactController.text,
          _nameController.text,
          parentLoginId: parentCreds['id'],
          parentPin: parentCreds['pin'],
        );
        await _generateAdmissionPDF();
        await _showParentCredentialsDialog(
          _nameController.text.trim(),
          parentCreds['id']!,
          parentCreds['pin']!,
        );
        if (!mounted) return;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => SetFeePage(
                    docId: docRef.id, studentName: _nameController.text)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      // Loading khatam
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text(
            "New Admission Form",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.teal[800]),
      body: _loadingAcademicStructure
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: _selectedImage != null
                                ? FileImage(_selectedImage!)
                                : null,
                            child: _selectedImage == null
                                ? const Icon(Icons.camera_alt, size: 50)
                                : null)),
                    TextField(
                        controller: _formNoController,
                        readOnly: true,
                        decoration:
                            const InputDecoration(labelText: "Form No")),
                    TextField(
                        controller: _rollNoController,
                        readOnly: true,
                        decoration:
                            const InputDecoration(labelText: "Roll No")),
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
                                fontWeight: FontWeight.bold,
                                color: Colors.teal))),
                    TextField(
                        controller: _nameController,
                        decoration:
                            const InputDecoration(labelText: "Student Name")),
                    TextField(
                        controller: _sCNICController,
                        decoration:
                            const InputDecoration(labelText: "Student CNIC")),
                    TextField(
                        controller: _fNameController,
                        decoration:
                            const InputDecoration(labelText: "Father Name")),
                    TextField(
                        controller: _fCNICController,
                        decoration:
                            const InputDecoration(labelText: "Father CNIC")),
                    TextField(
                        controller: _pAddressController,
                        decoration: const InputDecoration(
                            labelText: "Permanent Address")),
                    TextField(
                        controller: _districtController,
                        decoration:
                            const InputDecoration(labelText: "District")),
                    TextField(
                        controller: _religionController,
                        decoration:
                            const InputDecoration(labelText: "Religion")),
                    DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: "Gender"),
                        items: ['Male', 'Female']
                            .map((v) =>
                                DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedGender = v)),
                    TextField(
                        controller: _contactController,
                        decoration:
                            const InputDecoration(labelText: "Contact No 1")),
                    TextField(
                        controller: _contactController2,
                        decoration: const InputDecoration(
                            labelText: "Contact No 2 (Optional)")),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: "Class"),
                      initialValue: _selectedClass,
                      items: [
                        ..._classList.map(
                            (v) => DropdownMenuItem(value: v, child: Text(v))),
                        const DropdownMenuItem(
                          value: _addNewValue,
                          child: Text("+ Add New Class",
                              style: TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == _addNewValue) {
                          _showAddClassDialog();
                        } else {
                          // As soon as the class changes/is selected, its
                          // linked sections load and the previous class's
                          // section resets.
                          _onClassChanged(v);
                        }
                      },
                    ),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: "Section",
                        helperText: _selectedClass == null
                            ? "Please select a Class first"
                            : null,
                      ),
                      initialValue: _selectedSection,
                      items: [
                        ..._sectionList.map(
                            (v) => DropdownMenuItem(value: v, child: Text(v))),
                        DropdownMenuItem(
                          value: _addNewSectionValue,
                          enabled: _selectedClass != null,
                          child: Text("+ Add New Section",
                              style: TextStyle(
                                  color: _selectedClass == null
                                      ? Colors.grey
                                      : Colors.teal,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                      onChanged: _selectedClass == null
                          ? null
                          : (v) {
                              if (v == _addNewSectionValue) {
                                _showAddSectionDialog();
                              } else {
                                setState(() => _selectedSection = v);
                              }
                            },
                    ),
                    TextField(
                        controller: _addFeeController,
                        decoration:
                            const InputDecoration(labelText: "Add Fee")),
                    TextField(
                        controller: _preSchoolController,
                        decoration: const InputDecoration(
                            labelText: "Pre School Name")),
                    TextField(
                        controller: _leavingReasonController,
                        decoration: const InputDecoration(
                            labelText: "Reason of School Leaving")),
                    const SizedBox(height: 20),
                    // Submit Button Loading ke sath
                    ElevatedButton(
                      onPressed: _isSaving ? null : _addStudent,
                      child: _isSaving
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text(
                                    "Processing..."), // Yahan "Processing..." likha aayega
                              ],
                            )
                          : const Text("SUBMIT ADMISSION"),
                    ),
                    const SizedBox(
                        height: 24), // So it doesn't hide behind the gesture nav bar
                  ],
                ), // <--- Column band
              ), // <--- SingleChildScrollView band
            ), // <--- SafeArea band
    ); // <--- Scaffold band
  } // <--- build method band
} // <---
