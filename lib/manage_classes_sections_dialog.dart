import 'package:flutter/material.dart';
import 'class_section_service.dart';

// ============================================================================
// showManageClassesSectionsDialog
// ----------------------------------------------------------------------------
// This is the same "Setup Classes & Sections" dialog that used to live only
// inside admission_page (shown forcibly before the first admission if the
// structure was empty). It has now been pulled out here and made shared so
// that:
//
//   1. admission_page  -> shown forcibly the first time (when the structure
//                          is empty)
//   2. settings_page   -> available anytime via the "Manage Classes &
//                          Sections" button, to edit the existing
//                          classes/sections
//
// Both places use EXACTLY the same UI and Firestore save logic — no
// duplicated copies anywhere, so both stay in sync automatically.
//
// Usage:
//   final result = await showManageClassesSectionsDialog(
//     context,
//     current: existingStructure,       // used to pre-fill the dialog
//     barrierDismissible: true,         // from settings: true; from the
//                                       // first-time admission flow: false
//                                       // (forced)
//   );
//   if (result != null) {
//     // The user saved — result.classes / result.sectionsByClass contain
//     // the new structure (already saved to Firestore).
//   }
// ============================================================================

const List<String> kDefaultSuggestedClasses = [
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
  'Ten',
];

/// Shows the dialog for managing Classes & Sections. On save, it also
/// saves the new [AcademicStructure] to Firestore (via
/// [ClassSectionService.saveAll]) and returns that same structure. If the
/// user cancels or taps outside (when [barrierDismissible] is true),
/// `null` is returned and nothing is saved.
///
/// [current] - the existing structure, used to pre-fill the dialog.
///   If [current]'s classes are empty, suggested defaults
///   ([kDefaultSuggestedClasses], each with ['A','B']) are shown to help
///   the user fill it in the first time — they can remove/change them.
Future<AcademicStructure?> showManageClassesSectionsDialog(
  BuildContext context, {
  required AcademicStructure current,
  bool barrierDismissible = true,
  String title = "Manage Classes & Sections",
  String description =
      "The classes and their sections set here will be used throughout the app (fees, reports, admissions, etc.).",
}) async {
  List<String> tempClasses = List<String>.from(
      current.classes.isNotEmpty ? current.classes : kDefaultSuggestedClasses);
  Map<String, List<String>> tempSectionsByClass = {
    for (var c in tempClasses)
      c: List<String>.from(current.sectionsByClass[c] ?? ['A', 'B']),
  };
  final TextEditingController classInput = TextEditingController();
  final Map<String, TextEditingController> sectionInputControllers = {};

  TextEditingController sectionControllerFor(String className) =>
      sectionInputControllers.putIfAbsent(
          className, () => TextEditingController());

  return showDialog<AcademicStructure>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.6,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                const Text("Classes",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tempClasses
                      .map((c) => Chip(
                            label: Text(c),
                            onDeleted: () => setDialogState(() {
                              tempClasses.remove(c);
                              tempSectionsByClass.remove(c);
                            }),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: classInput,
                      decoration: const InputDecoration(
                          hintText: "Add class (e.g. Eleven)"),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.teal),
                    onPressed: () {
                      String v = classInput.text.trim();
                      if (v.isNotEmpty && !tempClasses.contains(v)) {
                        setDialogState(() {
                          tempClasses.add(v);
                          tempSectionsByClass[v] = ['A', 'B'];
                        });
                        classInput.clear();
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                const Divider(),
                const Text("Sections for each class:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                // A separate section editor for each class — this makes it
                // possible to give "One" sections A/B/C while "Playgroup"
                // only gets A.
                ...tempClasses.map((className) {
                  List<String> sections = tempSectionsByClass[className] ?? [];
                  TextEditingController ctrl = sectionControllerFor(className);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(className,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: sections
                                .map((s) => Chip(
                                      label: Text(s),
                                      onDeleted: () => setDialogState(
                                          () => sections.remove(s)),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                decoration: InputDecoration(
                                    hintText: "Add section for $className",
                                    isDense: true),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle,
                                  color: Colors.teal, size: 20),
                              onPressed: () {
                                String v = ctrl.text.trim();
                                if (v.isNotEmpty && !sections.contains(v)) {
                                  setDialogState(() => sections.add(v));
                                  ctrl.clear();
                                }
                              },
                            ),
                          ]),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          if (barrierDismissible)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
          ElevatedButton(
            onPressed: tempClasses.isEmpty
                ? null
                : () async {
                    await ClassSectionService.saveAll(
                        classes: tempClasses,
                        sectionsByClass: tempSectionsByClass);
                    if (dialogContext.mounted) {
                      Navigator.pop(
                        dialogContext,
                        AcademicStructure(
                          classes: List<String>.from(tempClasses),
                          sectionsByClass: {
                            for (var c in tempClasses)
                              c: List<String>.from(
                                  tempSectionsByClass[c] ?? []),
                          },
                        ),
                      );
                    }
                  },
            child: const Text("Save & Continue"),
          ),
        ],
      ),
    ),
  );
}
