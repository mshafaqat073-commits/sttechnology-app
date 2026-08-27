import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';

/// Parent ke liye read-only Documents page.
///
/// Do tarah ke documents ek sath dikhata hai:
///  1. Is bache ke apne documents (jo admin ne DocumentManagementPage ke
///     "Students" tab se is student ke liye upload kiye hain —
///     ownerType == 'student', ownerId == studentId).
///  2. Is bache ki class ke liye bheje gaye "Class Notices" (jo admin ne
///     "Class Notices" tab se poori class ko bheje — ownerType == 'class',
///     ownerId == className).
///
/// Jo document upload karte waqt "Important" mark kiya gaya ho (jese
/// B-Form, CNIC) wo hamesha list mein sab se upar dikhta hai — baaki
/// latest-upload-first order mein.
///
/// Sirf dekhne/khol'ne ke liye hai — parent yahan se koi document
/// upload ya delete nahi kar sakta (wo sirf admin kar sakta hai).
class ParentDocumentsPage extends StatelessWidget {
  final String studentId;
  final String studentName;
  final String className;

  const ParentDocumentsPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.className,
  });

  // "important" docs pehle, phir latest upload pehle.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sorted(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final list = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    list.sort((a, b) {
      final da = a.data();
      final db = b.data();
      final ia = da['important'] == true;
      final ib = db['important'] == true;
      if (ia != ib) return ia ? -1 : 1; // important pehle

      final ta = da['uploadedAt'];
      final tb = db['uploadedAt'];
      if (ta == null || tb == null) return 0;
      return (tb as Timestamp).compareTo(ta as Timestamp); // latest pehle
    });
    return list;
  }

  void _viewDocument(BuildContext context, String url, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title),
              backgroundColor: Colors.deepPurple[800],
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        "Preview available nahi — document link se open karein."),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docCard(BuildContext context, Map<String, dynamic> data,
      {required bool isClassNotice}) {
    String title = data['title'] ?? 'Document';
    String url = data['url'] ?? '';
    bool important = data['important'] == true;
    String date = "N/A";
    if (data['uploadedAt'] != null) {
      date = DateFormat('dd-MM-yyyy')
          .format((data['uploadedAt'] as Timestamp).toDate());
    }
    bool isPdf = url.toLowerCase().contains('.pdf');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: important ? 3 : 1,
      shape: important
          ? RoundedRectangleBorder(
              side: BorderSide(color: Colors.amber.shade600, width: 1.4),
              borderRadius: BorderRadius.circular(8))
          : null,
      child: ListTile(
        leading: Icon(
          isPdf ? Icons.picture_as_pdf : Icons.image,
          color: Colors.deepPurple,
        ),
        title: Row(
          children: [
            if (important) ...[
              const Icon(Icons.star, color: Colors.amber, size: 16),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Text(
          isClassNotice ? "Class Notice  •  $date" : "Uploaded: $date",
          style: TextStyle(
              color: isClassNotice ? Colors.indigo : Colors.grey[700]),
        ),
        onTap: () => _viewDocument(context, url, title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$studentName — Documents"),
        backgroundColor: Colors.deepPurple[800],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: schoolCollection('documents')
            .where('ownerType', isEqualTo: 'student')
            .where('ownerId', isEqualTo: studentId)
            .snapshots(),
        builder: (context, studentSnap) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: schoolCollection('documents')
                .where('ownerType', isEqualTo: 'class')
                .where('ownerId', isEqualTo: className)
                .snapshots(),
            builder: (context, classSnap) {
              if (studentSnap.connectionState == ConnectionState.waiting ||
                  classSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (studentSnap.hasError || classSnap.hasError) {
                return Center(
                  child: Text(
                    "Error: ${studentSnap.error ?? classSnap.error}",
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }

              final studentDocs = _sorted(studentSnap.data?.docs ?? []);
              final classDocs = _sorted(classSnap.data?.docs ?? []);

              if (studentDocs.isEmpty && classDocs.isEmpty) {
                return const Center(
                  child: Text(
                    "Abhi koi document upload nahi hua.",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  if (classDocs.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text("Class Notices",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.indigo)),
                    ),
                    ...classDocs.map((d) =>
                        _docCard(context, d.data(), isClassNotice: true)),
                    const Divider(height: 24),
                  ],
                  if (studentDocs.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text("My Documents",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.deepPurple)),
                    ),
                    ...studentDocs.map((d) =>
                        _docCard(context, d.data(), isClassNotice: false)),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
