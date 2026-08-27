import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'login_page.dart';
import 'auth_settings.dart';
import 'class_section_service.dart';
import 'manage_classes_sections_dialog.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'subscription_service.dart';

// Backup, Reset, and Import all share this one collection list so a
// collection can never accidentally be left out of one of them.
// Add new collections here only.
const List<String> _managedCollections = [
  'students',
  'fee_structures',
  'fee_history',
  'fee_payments',
  'results',
  'expenses',
  'SLC',
  'staff',
  'teachers',
  'attendance',
  'counters',
  'other_incomes',
  'school_diary',
  'school_events',
  'school_homework',
  'special_messages',
  'teacher_attendance',
  'notifications',
  'app_settings',
  'bulk_fee_operations',
  'settings',
  'teacher_notifications',
  'notification_queue',
  'timetable',
  'documents',
  'complaints',
  'fine_history',
  'leave_applications',
  'online_classes',
  'push_notifications',
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _tsMarkerKey = '__ts__';

  // Auto-backup: every 24 hours a backup is silently saved to the device's
  // permanent storage (the app's documents folder), so there's always a
  // recent recovery point without needing to remember to back up manually
  // — restore it any time from "Restore from Auto Backup". Only the most
  // recent _maxAutoBackups files are kept; older ones are deleted
  // automatically.
  static const String _autoBackupDirName = 'auto_backups';
  static const int _autoBackupIntervalHours = 24;
  static const int _maxAutoBackups = 5;

  DateTime? _lastAutoBackupAt;

  @override
  void initState() {
    super.initState();
    // Runs silently in the background — no dialog or progress shown to
    // the user, it only actually does anything once 24 hours have passed
    // since the last one.
    // Auto-backup relies on a persistent local filesystem, which web
    // browsers don't provide the same way native platforms do — skip it
    // entirely on web (Restore from Auto Backup will explain this too).
    if (!kIsWeb) {
      _maybeRunAutoBackup();
      _loadLastAutoBackupTime();
    }
  }

  // Sanitized filename fragment from the current school's display name
  // (so backup files are easy to tell apart when a device has more than
  // one export saved).
  String _fileNameSafeSchoolName() {
    final name = currentSchoolDisplayName();
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return cleaned.isEmpty ? 'School' : cleaned;
  }

  // Makes Firestore doc data JSON-safe. Timestamp fields are wrapped in a
  // recognizable marker map ({'__ts__': iso-string}) instead of being
  // turned into a plain string, so on import we can tell with certainty
  // that a field was a Timestamp rather than a normal string field that
  // merely looks similar.
  dynamic _encodeForBackup(dynamic value) {
    if (value is Timestamp) {
      return {_tsMarkerKey: value.toDate().toIso8601String()};
    } else if (value is Map) {
      // `value is Map` only narrows to `Map<dynamic, dynamic>`, so
      // `.map()` on it also produces a raw `Map<dynamic, dynamic>` —
      // which later fails an `as Map<String, dynamic>` cast (whenever any
      // field contains a nested map, e.g. an address). Building the map
      // explicitly with `Map<String, dynamic>.from(...)` keeps the cast
      // safe everywhere.
      return Map<String, dynamic>.from(
        value.map((k, v) => MapEntry(k.toString(), _encodeForBackup(v))),
      );
    } else if (value is List) {
      return value.map(_encodeForBackup).toList();
    }
    return value;
  }

  // Turns backed-up data back into Firestore-ready data — any marker map
  // is converted back into a Timestamp, everything else is left as-is.
  dynamic _decodeFromBackup(dynamic value) {
    if (value is Map) {
      if (value.length == 1 && value.containsKey(_tsMarkerKey)) {
        return Timestamp.fromDate(DateTime.parse(value[_tsMarkerKey]));
      }
      // Same Map<String, dynamic> type-safety note as in
      // _encodeForBackup applies here too, for nested maps on import.
      return Map<String, dynamic>.from(
        value.map((k, v) => MapEntry(k.toString(), _decodeFromBackup(v))),
      );
    } else if (value is List) {
      return value.map(_decodeFromBackup).toList();
    }
    return value;
  }

  // ---- Excel cell encoding helpers -----------------------------------
  // Excel cells only really hold plain text/numbers, so to round-trip
  // Firestore's richer types (Timestamp, number vs. string, bool, nested
  // maps/lists) through a spreadsheet cell we tag the cell text with a
  // short, unambiguous prefix. This is used for EXPORT only — Import
  // still only accepts the JSON backup file, which preserves everything
  // exactly and needs no such tagging (see the note on _pickAndImportFile
  // for why).
  String _excelCellString(dynamic value) {
    if (value == null) return '';
    if (value is Timestamp) {
      return '__TS__${value.toDate().toIso8601String()}';
    } else if (value is num) {
      return '__NUM__$value';
    } else if (value is bool) {
      return '__BOOL__$value';
    } else if (value is Map || value is List) {
      return '__JSON__${jsonEncode(_encodeForBackup(value))}';
    }
    return value.toString();
  }

  // 1. Logout
  Future<void> _logout() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Do you want to logout?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Logout")),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      SchoolContext.clear();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  // 2. Generic single-field editor (used for School Name / Address)
  Future<void> _editSetting(String title, String fieldName) async {
    TextEditingController controller = TextEditingController();
    var doc = await schoolCollection('settings').doc('global').get();
    if (doc.exists && doc.data() != null) {
      controller.text = doc.data()![fieldName] ?? "";
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $title"),
        content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: "Enter new $title")),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              await schoolCollection('settings')
                  .doc('global')
                  .set({fieldName: controller.text}, SetOptions(merge: true));
              if (fieldName == 'schoolName' ||
                  fieldName == 'contactNumber' ||
                  fieldName == 'contactEmail' ||
                  fieldName == 'easypaisaNumber' ||
                  fieldName == 'easypaisaAccountName' ||
                  fieldName == 'ublIban' ||
                  fieldName == 'ublAccountName') {
                // Refresh the cache immediately so the Dashboard/AI Chat/
                // PDFs/Pay Fee Online show the new name/number/email/
                // payment-account right away, without an app restart.
                await SchoolContext.loadBranding();
              }
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text("$title updated!")));
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // 2b. School Logo upload — same pattern as the image upload in
  // student_detail_page.dart (Cloudinary), just a different folder:
  // 'school_logos'.
  Future<void> _editSchoolLogo() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return; // user cancelled

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final cloudinary = CloudinaryPublic('niilo9ek', 'shafi073', cache: false);
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          picked.path,
          resourceType: CloudinaryResourceType.Image,
          folder: 'school_logos',
        ),
      );

      await schoolCollection('settings')
          .doc('global')
          .set({'logoUrl': response.secureUrl}, SetOptions(merge: true));

      // Refresh the cache immediately so the new logo shows up everywhere
      // (Dashboard, Settings, Login screen, PDFs) without an app restart.
      await SchoolContext.loadBranding();

      if (mounted) {
        Navigator.pop(context); // close the loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("School Logo updated!")));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close the loading dialog
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Logo upload failed: $e")));
      }
    }
  }

  // Same shared dialog as the Admission page
  // (manage_classes_sections_dialog.dart) — current classes and each
  // class's sections are pre-filled from ClassSectionService, so classes/
  // sections can be added or edited any time from Settings (not just
  // during the first admission).
  Future<void> _manageClassesSections() async {
    var current = await ClassSectionService.getAll();
    if (!mounted) return;
    final result = await showManageClassesSectionsDialog(
      context,
      current: current,
      barrierDismissible: true,
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Classes & Sections updated!"),
          backgroundColor: Colors.teal));
    }
  }

  // Fetches every document from every managed Firestore collection into
  // one JSON-safe Map. Manual backup (_backupAsJson), the Excel export,
  // and auto-backup (_runAutoBackup) all reuse this so every export is
  // built from exactly the same underlying data.
  Future<Map<String, dynamic>> _buildBackupJson() async {
    Map<String, dynamic> fullBackup = {
      // Lets a backup file identify which collection list it was built
      // from — useful for import in the future.
      '_meta': {
        'app': currentSchoolDisplayName(),
        'exportedAt': DateTime.now().toIso8601String(),
        'collections': _managedCollections,
      },
    };

    // Fetch all collections in PARALLEL — same reasoning as reset: 28
    // sequential round-trips add several seconds of pure network wait
    // regardless of how little data each collection has.
    final allSnapshots = await Future.wait(
      _managedCollections.map((coll) => schoolCollection(coll).get()),
    );

    for (var i = 0; i < _managedCollections.length; i++) {
      var snapshot = allSnapshots[i];
      List<Map<String, dynamic>> collectionData = snapshot.docs.map((doc) {
        Map<String, dynamic> d = Map<String, dynamic>.from(doc.data());
        d['id'] = doc.id; // the document ID must be preserved
        return _encodeForBackup(d) as Map<String, dynamic>;
      }).toList();

      fullBackup[_managedCollections[i]] = collectionData;
    }

    return fullBackup;
  }

  // Builds an .xlsx workbook with one sheet per non-empty collection —
  // handy for viewing/analyzing/sharing data in Excel/Google Sheets. This
  // is a human-readable EXPORT format; restoring data back into the app
  // always uses the JSON backup (see _pickAndImportFile for why).
  Future<Uint8List> _buildBackupExcelBytes() async {
    final workbook = Excel.createExcel();
    final defaultSheetName = workbook.getDefaultSheet();

    final allSnapshots = await Future.wait(
      _managedCollections.map((coll) => schoolCollection(coll).get()),
    );

    for (var i = 0; i < _managedCollections.length; i++) {
      final coll = _managedCollections[i];
      var snapshot = allSnapshots[i];
      if (snapshot.docs.isEmpty) continue;

      final rows = <Map<String, dynamic>>[];
      final fieldNames = <String>{};
      for (var doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        fieldNames.addAll(data.keys);
        rows.add(data);
      }
      final otherFields = fieldNames.where((f) => f != 'id').toList()..sort();
      final columns = ['id', ...otherFields];

      final sheet = workbook[coll];
      sheet.appendRow(columns.map((c) => TextCellValue(c)).toList());
      for (var row in rows) {
        sheet.appendRow(
          columns.map((c) => TextCellValue(_excelCellString(row[c]))).toList(),
        );
      }
    }

    // Excel always creates one default empty sheet — drop it if we ended
    // up adding real sheets, so the file doesn't show a stray blank tab.
    if (defaultSheetName != null &&
        workbook.sheets.containsKey(defaultSheetName) &&
        workbook.sheets.length > 1 &&
        (workbook.sheets[defaultSheetName]?.rows.isEmpty ?? false)) {
      workbook.delete(defaultSheetName);
    }

    final bytes = workbook.save();
    if (bytes == null) {
      throw Exception('Excel file could not be generated');
    }
    return Uint8List.fromList(bytes);
  }

  // 3. Backup Data — asks which format first, then builds and shares it.
  Future<void> _backupData() async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Backup Format"),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'json'),
            child: const ListTile(
              leading: Icon(Icons.description, color: Colors.teal),
              title: Text("JSON (Full Backup)"),
              subtitle: Text("Recommended — can be restored back into the app"),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'excel'),
            child: const ListTile(
              leading: Icon(Icons.table_chart, color: Colors.green),
              title: Text("Excel (.xlsx)"),
              subtitle: Text("For viewing/printing — cannot be restored"),
            ),
          ),
        ],
      ),
    );

    if (format == null || !mounted) return;
    if (format == 'json') {
      await _backupAsJson();
    } else {
      await _backupAsExcel();
    }
  }

  Future<void> _backupAsJson() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text("Preparing backup...")),
          ],
        ),
      ),
    );

    try {
      Map<String, dynamic> fullBackup = await _buildBackupJson();
      String jsonString = jsonEncode(fullBackup);

      String dateStamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName =
          '${_fileNameSafeSchoolName()}_Backup_$dateStamp.json';
      // Built directly from in-memory bytes — no temp file/directory
      // needed, so this works the same on web, Android, and desktop.
      final xfile = XFile.fromData(
        Uint8List.fromList(utf8.encode(jsonString)),
        mimeType: 'application/json',
        name: fileName,
      );

      if (mounted) {
        Navigator.pop(context); // close the progress dialog
        await Share.shareXFiles([xfile],
            text: '${currentSchoolDisplayName()} Complete Backup (JSON)');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close the progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Backup Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _backupAsExcel() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text("Preparing Excel file...")),
          ],
        ),
      ),
    );

    try {
      final bytes = await _buildBackupExcelBytes();

      String dateStamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName =
          '${_fileNameSafeSchoolName()}_Backup_$dateStamp.xlsx';
      final xfile = XFile.fromData(
        bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: fileName,
      );

      if (mounted) {
        Navigator.pop(context); // close the progress dialog
        await Share.shareXFiles([xfile],
            text: '${currentSchoolDisplayName()} Complete Backup (Excel)');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close the progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Backup Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 4. Reset Data
  Future<void> _performReset({
    void Function(int done, int total)? onProgress,
  }) async {
    var db = FirebaseFirestore.instance;
    const batchSize = 450;
    final total = _managedCollections.length;
    int done = 0;

    // Fetch + delete each collection independently and run all 28 of
    // these jobs in PARALLEL. Previously only the fetch step ran in
    // parallel — the delete step looped over collections one at a time,
    // so a single collection with a lot of accumulated data (e.g.
    // attendance/notification logs, even if `students` itself only has
    // a handful of docs) made every other, mostly-empty collection wait
    // its turn before being cleared. Deleting all collections
    // concurrently removes that bottleneck.
    Future<void> deleteCollection(String coll) async {
      var snapshot = await schoolCollection(coll).get();
      // Batched delete (max 500 ops per batch) — faster and safer than
      // deleting one document at a time for large collections.
      for (var i = 0; i < snapshot.docs.length; i += batchSize) {
        final batch = db.batch();
        final chunk = snapshot.docs.skip(i).take(batchSize);
        for (var doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      done++;
      onProgress?.call(done, total);
    }

    await Future.wait(_managedCollections.map(deleteCollection));
  }

  // Resolves the app's permanent "documents" folder. On Windows this is
  // built manually from the APPDATA environment variable (a plain dart:io
  // call, no plugin channel involved) to work around a
  // path_provider_windows plugin-registration issue on this project; other
  // platforms keep using path_provider as before, where it already works.
  Future<Directory> _getAppDocumentsDir() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        final dir = Directory('$appData\\aep_school_system');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      }
    }
    return getApplicationDocumentsDirectory();
  }

  // Auto-backup files live in a dedicated subfolder inside the app's
  // permanent "documents" directory (not the temp folder — the OS can
  // clear that at any time, which would defeat the purpose).
  Future<Directory> _getAutoBackupDir() async {
    final docsDir = await _getAppDocumentsDir();
    final dir = Directory('${docsDir.path}/$_autoBackupDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<File>> _listAutoBackupFiles(Directory dir) async {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    // The filename encodes a yyyy-MM-dd_HHmmss timestamp, so a plain
    // lexical (string) sort is already a chronological sort.
    files.sort((a, b) => b.path.compareTo(a.path)); // newest first
    return files;
  }

  Future<void> _loadLastAutoBackupTime() async {
    try {
      final dir = await _getAutoBackupDir();
      final files = await _listAutoBackupFiles(dir);
      if (files.isNotEmpty && mounted) {
        setState(() {
          _lastAutoBackupAt = files.first.lastModifiedSync();
        });
      }
    } catch (_) {
      // Not critical — the tile just won't show a "last backup" subtitle.
    }
  }

  // Checked on app open/Settings page load: how long ago was the last
  // auto-backup? If more than _autoBackupIntervalHours have passed (or
  // there's no backup yet), a new one is created silently — no dialog or
  // loading UI, so opening Settings never feels slow or interrupted.
  Future<void> _maybeRunAutoBackup() async {
    try {
      final dir = await _getAutoBackupDir();
      final files = await _listAutoBackupFiles(dir);

      if (files.isNotEmpty) {
        final lastModified = await files.first.lastModified();
        final hoursSinceLast = DateTime.now().difference(lastModified).inHours;
        if (hoursSinceLast < _autoBackupIntervalHours) {
          return; // not due yet
        }
      }

      await _runAutoBackup(dir);
      await _loadLastAutoBackupTime();
    } catch (e) {
      // Auto-backup should never interrupt normal app use, so no error UI
      // is shown — but it's still logged so a developer can diagnose a
      // recurring failure (e.g. low storage) from device logs.
      debugPrint('Auto-backup failed: $e');
    }
  }

  Future<void> _runAutoBackup(Directory dir) async {
    Map<String, dynamic> fullBackup = await _buildBackupJson();
    String jsonString = jsonEncode(fullBackup);
    String dateStamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/AutoBackup_$dateStamp.json');
    await file.writeAsString(jsonString);
    await _pruneOldAutoBackups(dir);
  }

  // Keeps only the most recent _maxAutoBackups backups, deleting older
  // ones automatically so device storage doesn't fill up over time.
  Future<void> _pruneOldAutoBackups(Directory dir) async {
    final files = await _listAutoBackupFiles(dir);
    if (files.length > _maxAutoBackups) {
      for (var f in files.skip(_maxAutoBackups)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  String _formatAutoBackupLabel(String fileName) {
    try {
      final stamp =
          fileName.replaceAll('AutoBackup_', '').replaceAll('.json', '');
      final parsed = DateFormat('yyyy-MM-dd_HHmmss').parse(stamp);
      return DateFormat('dd MMM yyyy, hh:mm a').format(parsed);
    } catch (_) {
      return fileName;
    }
  }

  String? _lastAutoBackupSubtitle() {
    if (_lastAutoBackupAt == null) return null;
    return 'Last auto backup: ${DateFormat('dd MMM yyyy, hh:mm a').format(_lastAutoBackupAt!)}';
  }

  // "Restore from Auto Backup" — shows the list of automatic backups
  // already on the device, so recovering from data loss doesn't require
  // hunting for a file; just pick one from the list.
  Future<void> _showRestoreFromAutoBackupDialog() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Auto Backup isn't available on Web. Use 'Import Data' with a JSON backup file instead.")),
        );
      }
      return;
    }

    final dir = await _getAutoBackupDir();
    final files = await _listAutoBackupFiles(dir);

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No automatic backup exists yet.")),
        );
      }
      return;
    }

    if (!mounted) return;
    File? selected = await showDialog<File>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Restore from Auto Backup"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: files.length,
            itemBuilder: (context, index) {
              final f = files[index];
              final label = _formatAutoBackupLabel(f.path.split('/').last);
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(label),
                subtitle: index == 0 ? const Text("Most recent") : null,
                onTap: () => Navigator.pop(context, f),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
        ],
      ),
    );

    if (selected == null) return;
    if (!mounted) return;
    await _confirmModeAndImport(selected);
  }

  // 5. Import Data — restores all data from a JSON backup file back into
  // Firestore.
  //
  // Import intentionally only accepts the JSON backup, not Excel: JSON
  // preserves every field's exact type (Timestamp vs. string vs. number,
  // nested maps/lists) with no ambiguity, while a spreadsheet is a
  // human/print-friendly VIEW of the data best suited for browsing or
  // sharing outside the app — not a reliable source to rebuild Firestore
  // documents from. Two modes:
  //  - Merge: only adds/updates documents; anything already there that
  //    isn't in the backup is left alone (not deleted).
  //  - Replace: first deletes each collection's existing data, then
  //    imports fresh from the backup — this makes the app's data match
  //    the backup exactly.
  Future<void> _pickAndImportFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    if (!mounted) return;
    await _confirmModeAndImport(File(result.files.single.path!));
  }

  // Asks Merge/Replace All, then imports the chosen file via
  // _importFromJsonFile. Both the manual file picker and "Restore from
  // Auto Backup" go through this same method so behavior is identical
  // regardless of where the file came from.
  Future<void> _confirmModeAndImport(File file) async {
    String? mode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Import Data", style: TextStyle(color: Colors.red)),
        content: const Text(
            "Warning: this will change your current data. How would you like to import?\n\n"
            "• Merge: adds/updates data, nothing gets deleted.\n\n"
            "• Replace All: deletes existing data first, then restores fully from the backup (recommended when restoring an older backup)."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, 'merge'),
              child: const Text("Merge")),
          TextButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text("Replace All",
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (mode == null) return;
    if (!mounted) return;
    await _importFromJsonFile(file, mode);
  }

  // Core import logic — parses the backup JSON and writes it back into
  // Firestore. The progress dialog and success/error snackbar are also
  // handled here, so both callers (file picker and auto-backup restore)
  // get exactly the same experience.
  Future<void> _importFromJsonFile(File file, String mode) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text("Importing data...")),
          ],
        ),
      ),
    );

    try {
      String jsonString = await file.readAsString();
      Map<String, dynamic> backup = jsonDecode(jsonString);
      var db = FirebaseFirestore.instance;
      const batchSize = 450;

      for (String coll in _managedCollections) {
        if (!backup.containsKey(coll)) continue;
        List<dynamic> docsRaw = backup[coll] ?? [];
        if (docsRaw.isEmpty && mode != 'replace') continue;

        // Replace mode: first wipe this collection's existing data.
        if (mode == 'replace') {
          var existing = await schoolCollection(coll).get();
          for (var i = 0; i < existing.docs.length; i += batchSize) {
            final batch = db.batch();
            final chunk = existing.docs.skip(i).take(batchSize);
            for (var doc in chunk) {
              batch.delete(doc.reference);
            }
            await batch.commit();
          }
        }

        // Write the backed-up documents back in.
        for (var i = 0; i < docsRaw.length; i += batchSize) {
          final batch = db.batch();
          final chunk = docsRaw.skip(i).take(batchSize);
          for (var raw in chunk) {
            Map<String, dynamic> data = Map<String, dynamic>.from(raw as Map);
            String? id = data.remove('id')?.toString();
            if (id == null || id.isEmpty) continue;
            Map<String, dynamic> decoded =
                _decodeFromBackup(data) as Map<String, dynamic>;
            batch.set(schoolCollection(coll).doc(id), decoded,
                SetOptions(merge: mode == 'merge'));
          }
          await batch.commit();
        }
      }

      if (mounted) {
        Navigator.pop(context); // close the progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Data Imported Successfully!"),
              backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close the progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Import Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showResetDialog() {
    // The State's own context — stays valid for as long as this widget
    // is mounted. Captured once here so the async work below (after the
    // confirm dialog is already popped) has a context that's guaranteed
    // to still be attached to the tree, instead of reusing a dialog's
    // own builder context after that dialog has closed.
    final rootContext = context;

    showDialog(
        context: rootContext,
        builder: (dialogContext) => AlertDialog(
              title: const Text("Reset Database",
                  style: TextStyle(color: Colors.red)),
              content: const Text(
                  "Warning: do you want to delete ALL data? This action cannot be undone."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text("Cancel")),
                TextButton(
                    onPressed: () async {
                      Navigator.pop(dialogContext); // close confirmation dialog

                      // Live progress ("N / total collections cleared")
                      // instead of a static spinner, so it's clear the
                      // reset is actually moving rather than stuck.
                      final progress = ValueNotifier<int>(0);
                      final total = _managedCollections.length;
                      // Capture the messenger up front, from the stable
                      // root context (see note on rootContext above) —
                      // avoids looking a context up again after the
                      // async gap below.
                      final messenger = ScaffoldMessenger.of(rootContext);

                      showDialog(
                        context: rootContext,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          content: ValueListenableBuilder<int>(
                            valueListenable: progress,
                            builder: (context, done, _) => Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(width: 20),
                                    Expanded(
                                        child: Text(
                                            "Resetting database... ($done/$total)")),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: total == 0 ? 0 : done / total,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      try {
                        await _performReset(
                          onProgress: (done, total) =>
                              progress.value = done,
                        );
                        if (mounted) {
                          // Pop via the stable rootContext's navigator —
                          // not a context tied to a dialog that's mid
                          // teardown, which is what let this silently
                          // fail to close before.
                          Navigator.of(rootContext, rootNavigator: true)
                              .pop(); // close progress dialog
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text("Database Reset Successfully!"),
                                backgroundColor: Colors.teal),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          Navigator.of(rootContext, rootNavigator: true)
                              .pop(); // close progress dialog
                          messenger.showSnackBar(
                            SnackBar(
                                content: Text("Reset Error: $e"),
                                backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        progress.dispose();
                      }
                    },
                    child: const Text("Delete All",
                        style: TextStyle(color: Colors.red))),
              ],
            ));
  }

  // Developer ke apne Easypaisa/UBL account (subscription renew karne ke
  // liye) — ye hardcoded he kyunke ye har school ka nahi, sirf developer
  // (Muhammad Shafaqat Ali Zafar) ka account he jahan customer subscription
  // ka payment bhejta he.
  static const String _devEasypaisaNumber = "0300-6585073";
  static const String _devEasypaisaName = "Muhammad Shafaqat Ali Zafar";
  static const String _devUblIban = "PK33 UNIL 0109 0003 2622 4775";
  static const String _devUblName = "Muhammad Shafaqat Ali Zafar";

  void _copyToClipboard(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("$label copied")));
  }

  Widget _devAccountRow(IconData icon, Color color, String title,
      String number, String accountName) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20)),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text("$number\n$accountName"),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 20),
        tooltip: "Copy",
        onPressed: () => _copyToClipboard(number, title),
      ),
    );
  }

  // Subscription renew karne ke liye developer ke account details dialog
  // mein dikhata he — sirf ek payment info screen he, koi payment gateway
  // integration nahi (customer khud Easypaisa/Bank app se bhej kar
  // developer ko screenshot/reference bhejta he).
  void _showPayDeveloperDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pay to Renew Subscription"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  "Subscription renew karne ke liye neeche diye gaye "
                  "account mein payment bhej kar developer ko screenshot/"
                  "reference number bhej dein.",
                  style: TextStyle(fontSize: 13),
                ),
              ),
              _devAccountRow(Icons.phone_android, Colors.green, "Easypaisa",
                  _devEasypaisaNumber, _devEasypaisaName),
              const Divider(),
              _devAccountRow(Icons.account_balance, Colors.indigo,
                  "UBL Bank", _devUblIban, _devUblName),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("System Settings")),
      body: ListView(
        children: [
          const ListTile(
              title: Text("SUBSCRIPTION",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue))),
          FutureBuilder<SubscriptionInfo>(
            future: SubscriptionInfo.fetch(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const ListTile(
                  leading: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text("Loading subscription status..."),
                );
              }
              final info = snapshot.data!;
              final statusLabel =
                  info.status == 'trial' ? "Trial" : "Active";
              final color = info.isExpired
                  ? Colors.red
                  : (info.isExpiringSoon ? Colors.orange : Colors.green);
              final subtitle = info.isExpired
                  ? "Expired on ${DateFormat('d MMM, yyyy').format(info.endDate)} — contact support to renew"
                  : "${info.daysLeft} day${info.daysLeft == 1 ? '' : 's'} remaining • valid until ${DateFormat('d MMM, yyyy').format(info.endDate)}";
              return ListTile(
                leading: Icon(Icons.verified,
                    color: color),
                title: Text("$statusLabel Plan"),
                subtitle: Text(subtitle),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.payments, color: Colors.teal),
            title: const Text("Pay to Renew Subscription"),
            subtitle: const Text("Developer's Easypaisa / UBL account"),
            onTap: _showPayDeveloperDialog,
          ),
          const ListTile(
              title: Text("GENERAL INFO",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue))),
          ListTile(
            leading: const Icon(Icons.vpn_key),
            title: const Text("Update Login Info"),
            subtitle: const Text("Change your username and/or password"),
            onTap: () => showUpdateCredentialsDialog(context),
          ),
          ListTile(
            leading: const SizedBox(
              height: 32,
              width: 32,
              child: SchoolLogo(fit: BoxFit.contain),
            ),
            title: const Text("School Logo"),
            subtitle: const Text("Tap to set your school's logo"),
            onTap: _editSchoolLogo,
          ),
          ListTile(
              leading: const Icon(Icons.school),
              title: const Text("School Name"),
              onTap: () => _editSetting("School Name", "schoolName")),
          ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text("Address"),
              onTap: () => _editSetting("Address", "address")),
          ListTile(
              leading: const Icon(Icons.chat),
              title: const Text("WhatsApp Number"),
              subtitle: const Text(
                  "This number will be shown in this school's AI Chat, SLC, and Letterhead"),
              onTap: () =>
                  _editSetting("WhatsApp Number", "contactNumber")),
          ListTile(
              leading: const Icon(Icons.email),
              title: const Text("Contact Email"),
              subtitle: const Text(
                  "This email will be used across the app (Reports, AI Chat, Letterhead, etc.)"),
              onTap: () => _editSetting("Contact Email", "contactEmail")),
          ListTile(
              leading: const Icon(Icons.class_),
              title: const Text("Manage Classes & Sections"),
              subtitle:
                  const Text("Add or edit classes and each class's sections"),
              onTap: _manageClassesSections),
          const Divider(),
          const ListTile(
              title: Text("ONLINE PAYMENT ACCOUNT (Parents ko dikhega)",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue))),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Ye aapka (school ka) apna Easypaisa/UBL account hai — jab "
              "parent app mein 'Pay Fee Online' se fee jama karwayega to "
              "usko yehi account number dikhega. Pehle isay yahan set kar "
              "lein.",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          ListTile(
              leading: const Icon(Icons.phone_android, color: Colors.green),
              title: const Text("Easypaisa Number"),
              onTap: () =>
                  _editSetting("Easypaisa Number", "easypaisaNumber")),
          ListTile(
              leading: const Icon(Icons.person, color: Colors.green),
              title: const Text("Easypaisa Account Name"),
              onTap: () => _editSetting(
                  "Easypaisa Account Name", "easypaisaAccountName")),
          ListTile(
              leading:
                  const Icon(Icons.account_balance, color: Colors.indigo),
              title: const Text("UBL Bank IBAN"),
              onTap: () => _editSetting("UBL Bank IBAN", "ublIban")),
          ListTile(
              leading: const Icon(Icons.person, color: Colors.indigo),
              title: const Text("UBL Account Name"),
              onTap: () =>
                  _editSetting("UBL Account Name", "ublAccountName")),
          const Divider(),
          const ListTile(
              title: Text("DATA MANAGEMENT",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue))),
          ListTile(
              leading: const Icon(Icons.backup),
              title: const Text("Backup Data"),
              subtitle: const Text("Choose JSON (restorable) or Excel"),
              onTap: _backupData),
          ListTile(
              leading: const Icon(Icons.restore, color: Colors.orange),
              title: const Text("Import Data",
                  style: TextStyle(color: Colors.orange)),
              subtitle: const Text("Restore from a JSON backup file"),
              onTap: _pickAndImportFile),
          ListTile(
              leading: const Icon(Icons.history, color: Colors.orange),
              title: const Text("Restore from Auto Backup",
                  style: TextStyle(color: Colors.orange)),
              subtitle: Text(_lastAutoBackupSubtitle() ??
                  "A backup is saved automatically every 24 hours"),
              onTap: _showRestoreFromAutoBackupDialog),
          ListTile(
              leading: const Icon(Icons.refresh, color: Colors.red),
              title: const Text("Reset All Data",
                  style: TextStyle(color: Colors.red)),
              onTap: _showResetDialog),
          const Divider(),
          ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout",
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: _logout),
        ],
      ),
    );
  }
}
