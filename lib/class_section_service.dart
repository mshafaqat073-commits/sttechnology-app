import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

// ============================================================================
// ClassSectionService
// ----------------------------------------------------------------------------
// Used throughout the project for Classes and their (per-class) Sections
// (admission_page, set_fee_page, pay_fee_page, reports, filters, online
// classes, etc). Data is stored in Firestore in a single document
// ('app_settings/academic_structure'):
//
//   {
//     classes: ['Playgroup', 'Nursery', 'One', ...],
//     sectionsByClass: {
//       'Playgroup': ['A', 'B'],
//       'Nursery': ['A'],
//       'One': ['A', 'B', 'C'],
//       ...
//     }
//   }
//
// Each class has its own sections — 'One' can have sections A/B/C while
// 'Playgroup' only has A. Whenever the class changes, load that class's
// own sections — never reuse the previous class's sections.
//
// How to use anywhere:
//   final structure = await ClassSectionService.getAll();
//   List<String> classes = structure.classes;
//   List<String> sectionsForThisClass = structure.sectionsFor('One');
//
// To add a new class:
//   await ClassSectionService.addClass("Eleven");
//
// To add a new section to a specific class:
//   await ClassSectionService.addSectionToClass("One", "D");
//
// Live updates (with a StreamBuilder, if you need an instant refresh when
// something is added from elsewhere or another session):
//   ClassSectionService.watch()
// ============================================================================

class AcademicStructure {
  final List<String> classes;
  final Map<String, List<String>> sectionsByClass;

  const AcademicStructure({required this.classes, required this.sectionsByClass});

  /// Sections for the given class — returns an empty list if nothing has
  /// been set for that class.
  List<String> sectionsFor(String? className) {
    if (className == null) return [];
    return sectionsByClass[className] ?? [];
  }

  static const empty = AcademicStructure(classes: [], sectionsByClass: {});
}

class ClassSectionService {
  static const String _collection = 'app_settings';
  static const String _docId = 'academic_structure';

  static DocumentReference<Map<String, dynamic>> get _docRef =>
      schoolCollection(_collection).doc(_docId);

  static AcademicStructure _parse(Map<String, dynamic> data) {
    List<String> classes = List<String>.from(data['classes'] ?? []);
    Map<String, dynamic> rawSections =
        Map<String, dynamic>.from(data['sectionsByClass'] ?? {});
    Map<String, List<String>> sectionsByClass = {
      for (var entry in rawSections.entries)
        entry.key: List<String>.from(entry.value ?? []),
    };
    return AcademicStructure(classes: classes, sectionsByClass: sectionsByClass);
  }

  /// One-time fetch — the full structure (classes + each class's sections).
  /// If setup hasn't happened yet (before the very first admission), an
  /// empty structure is returned.
  static Future<AcademicStructure> getAll() async {
    try {
      var doc = await _docRef.get();
      if (!doc.exists) return AcademicStructure.empty;
      return _parse(doc.data() ?? {});
    } catch (e) {
      return AcademicStructure.empty;
    }
  }

  /// Live stream — for use with a StreamBuilder on any page to keep the
  /// class/section dropdown instantly up to date.
  static Stream<AcademicStructure> watch() {
    return _docRef.snapshots().map((doc) {
      if (!doc.exists) return AcademicStructure.empty;
      return _parse(doc.data() ?? {});
    });
  }

  /// Saves/overwrites the whole structure at once (when the first-time
  /// setup dialog is completed).
  static Future<void> saveAll({
    required List<String> classes,
    required Map<String, List<String>> sectionsByClass,
  }) async {
    await _docRef.set({
      'classes': classes,
      'sectionsByClass': sectionsByClass,
    }, SetOptions(merge: true));
  }

  /// Adds a new class to the list (skipped if it's a duplicate).
  static Future<void> addClass(String className) async {
    className = className.trim();
    if (className.isEmpty) return;
    await _docRef.set({
      'classes': FieldValue.arrayUnion([className]),
    }, SetOptions(merge: true));
  }

  /// Adds a new section to a specific class only — other classes' sections
  /// stay untouched (using the nested field path
  /// 'sectionsByClass.<className>').
  static Future<void> addSectionToClass(String className, String section) async {
    className = className.trim();
    section = section.trim();
    if (className.isEmpty || section.isEmpty) return;
    await _docRef.set({
      'sectionsByClass': {
        className: FieldValue.arrayUnion([section]),
      },
    }, SetOptions(merge: true));
  }
}
