import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';
import 'class_section_service.dart';

/// File extensions that should be uploaded to Cloudinary under its
/// "image" resource type. PDFs are intentionally NOT included here:
/// Cloudinary can technically accept a PDF as an "image" resource, but
/// by default it blocks public delivery of PDFs (and ZIPs) uploaded
/// that way for security reasons — the URL comes back with a 401 even
/// though the upload itself succeeds. Uploading PDFs as "raw" instead
/// (same as Word/Excel/PowerPoint/txt) avoids that restriction entirely
/// and lets them be viewed/downloaded normally.
const List<String> _imageLikeExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
];

/// Extensions the admin is allowed to pick under "Choose Document".
const List<String> _pickableDocumentExtensions = [
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt'
];

bool _looksLikeImage(String url) {
  final lower = url.toLowerCase();
  return ['.jpg', '.jpeg', '.png', '.gif', '.webp']
      .any((ext) => lower.contains(ext));
}

Future<void> _openOrDownload(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Could not open the document link.")),
    );
  }
}

/// Admin-only Document Management.
///
/// Three tabs:
///  - Student Documents: search/select a student, then upload/view their
///    important documents (CNIC, B-Form, certificates, etc.) — each
///    document has its own name/type entered.
///  - Staff Documents: same idea, select a staff member and
///    upload/view their documents (CNIC, contract, certificates).
///  - School Documents: not linked to any student/staff — the school's
///    own general important documents (registration, licenses, etc.).
///
/// All documents are saved in the 'documents' collection:
///   ownerType: 'student' | 'staff' | 'school'
///   ownerId: student/staff doc id (null for school documents)
///   ownerName: student/staff name for display (denormalized)
///   title: document name entered by the admin (e.g. "CNIC Copy")
///   url: secure link of the file uploaded to Cloudinary
///   uploadedAt: server timestamp
///
/// This page only opens from DashboardPage (admin) — the teacher/parent
/// dashboards have no button/route to it, so no one but the admin can
/// reach it.
class DocumentManagementPage extends StatefulWidget {
  const DocumentManagementPage({super.key});

  @override
  State<DocumentManagementPage> createState() => _DocumentManagementPageState();
}

class _DocumentManagementPageState extends State<DocumentManagementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Document Management",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.deepPurple[800],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabs: const [
            Tab(text: "Students", icon: Icon(Icons.school, size: 20)),
            Tab(text: "Staff", icon: Icon(Icons.badge, size: 20)),
            Tab(text: "School", icon: Icon(Icons.account_balance, size: 20)),
            Tab(text: "Class Notices", icon: Icon(Icons.groups, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _OwnerDocumentsTab(ownerType: 'student'),
          _OwnerDocumentsTab(ownerType: 'staff'),
          _SchoolDocumentsTab(),
          _ClassDocumentsTab(),
        ],
      ),
    );
  }
}

/// Common tab for a Student's or Staff's documents: search and select an
/// owner first, then their documents list + upload button.
class _OwnerDocumentsTab extends StatefulWidget {
  final String ownerType; // 'student' or 'staff'
  const _OwnerDocumentsTab({required this.ownerType});

  @override
  State<_OwnerDocumentsTab> createState() => _OwnerDocumentsTabState();
}

class _OwnerDocumentsTabState extends State<_OwnerDocumentsTab> {
  final TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot> _searchResults = [];
  bool _isSearching = false;

  String? _selectedOwnerId;
  String _selectedOwnerName = '';
  String _selectedOwnerSubtitle = '';

  String get _collectionName =>
      widget.ownerType == 'student' ? 'students' : 'staff';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    query = query.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      String queryLower = query.toLowerCase();

      // Firestore's range query (isGreaterThanOrEqualTo/isLessThanOrEqualTo)
      // is case-sensitive, so instead we fetch everyone and do a
      // case-insensitive "contains" match on the client — this way even a
      // single letter (uppercase or lowercase) shows the match right away.
      var snapshot = await schoolCollection(_collectionName).get();

      List<QueryDocumentSnapshot> results = snapshot.docs.where((d) {
        var data = d.data();
        String name = (data['name'] ?? '').toString().toLowerCase();
        return name.contains(queryLower);
      }).toList();

      if (widget.ownerType == 'student') {
        results = results
            .where(
                (d) => (d.data() as Map<String, dynamic>)['status'] == 'active')
            .toList();
      }

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint("Search error: $e");
      setState(() => _isSearching = false);
    }
  }

  void _selectOwner(QueryDocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    setState(() {
      _selectedOwnerId = doc.id;
      _selectedOwnerName = data['name'] ?? 'Unknown';
      _selectedOwnerSubtitle = widget.ownerType == 'student'
          ? "Class: ${data['class'] ?? 'N/A'}  •  Father: ${data['fName'] ?? 'N/A'}"
          : "${data['designation'] ?? 'Staff'}";
      _searchController.text = _selectedOwnerName;
      _searchResults = [];
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedOwnerId = null;
      _selectedOwnerName = '';
      _selectedOwnerSubtitle = '';
      _searchController.clear();
      _searchResults = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                enabled: _selectedOwnerId == null,
                decoration: InputDecoration(
                  labelText: widget.ownerType == 'student'
                      ? "Search student by name"
                      : "Search staff by name",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _selectedOwnerId != null
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _clearSelection,
                        )
                      : null,
                ),
                onChanged: _onSearchChanged,
              ),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_searchResults.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      var data =
                          _searchResults[index].data() as Map<String, dynamic>;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person,
                            color: Colors.deepPurple, size: 20),
                        title: Text(data['name'] ?? "No Name"),
                        subtitle: Text(widget.ownerType == 'student'
                            ? "Class: ${data['class'] ?? 'N/A'}"
                            : "${data['designation'] ?? ''}"),
                        onTap: () => _selectOwner(_searchResults[index]),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        if (_selectedOwnerId != null)
          Expanded(
            child: _DocumentListPanel(
              ownerType: widget.ownerType,
              ownerId: _selectedOwnerId!,
              ownerName: _selectedOwnerName,
              headerSubtitle: _selectedOwnerSubtitle,
            ),
          )
        else
          Expanded(
            child: Center(
              child: Text(
                widget.ownerType == 'student'
                    ? "Search for a student first to view/upload documents."
                    : "Search for a staff member first to view/upload documents.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ),
      ],
    );
  }
}

/// The school's own general documents — not linked to any student/staff.
class _SchoolDocumentsTab extends StatelessWidget {
  const _SchoolDocumentsTab();

  @override
  Widget build(BuildContext context) {
    return const _DocumentListPanel(
      ownerType: 'school',
      ownerId: 'school',
      ownerName: 'School Documents',
      headerSubtitle: 'Admin only — general school records',
    );
  }
}

/// Class-wide notices/documents: the admin can select a class and send
/// a document/paper to that entire class (including all sections) — that
/// document shows up in the Documents list of every student's parent in
/// that class, and can also be deleted from here. This is different from
/// students'/staff's individual documents — instead of being linked to
/// one student, it's linked to the whole class.
class _ClassDocumentsTab extends StatefulWidget {
  const _ClassDocumentsTab();

  @override
  State<_ClassDocumentsTab> createState() => _ClassDocumentsTabState();
}

class _ClassDocumentsTabState extends State<_ClassDocumentsTab> {
  String? _selectedClass;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: StreamBuilder<AcademicStructure>(
            stream: ClassSectionService.watch(),
            builder: (context, snapshot) {
              final classes = snapshot.data?.classes ?? [];
              if (classes.isEmpty) {
                return const Text(
                  "Please set up Classes & Sections in Settings first.",
                  style: TextStyle(color: Colors.grey),
                );
              }
              // If the previously selected class is no longer in the
              // list (it was deleted), clear the selection.
              if (_selectedClass != null &&
                  !classes.contains(_selectedClass)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _selectedClass = null);
                });
              }
              return DropdownButtonFormField<String>(
                initialValue: classes.contains(_selectedClass)
                    ? _selectedClass
                    : null,
                decoration: const InputDecoration(
                  labelText: "Select Class (sab sections)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.groups),
                ),
                items: classes
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedClass = val),
              );
            },
          ),
        ),
        if (_selectedClass != null)
          Expanded(
            child: _DocumentListPanel(
              key: ValueKey('class_$_selectedClass'),
              ownerType: 'class',
              ownerId: _selectedClass!,
              ownerName: "Class: $_selectedClass",
              headerSubtitle: "Sab students/parents (sab sections) ko dikhega",
            ),
          )
        else
          const Expanded(
            child: Center(
              child: Text(
                "Pehle koi class select karein document/paper bhejne ke liye.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }
}

/// Common panel: header (owner info) + documents list (Firestore
/// StreamBuilder, client-side sorted latest-first) + "Upload Document"
/// button that asks for a name/type and uploads to Cloudinary.
class _DocumentListPanel extends StatefulWidget {
  final String ownerType;
  final String ownerId;
  final String ownerName;
  final String headerSubtitle;

  const _DocumentListPanel({
    super.key,
    required this.ownerType,
    required this.ownerId,
    required this.ownerName,
    required this.headerSubtitle,
  });

  @override
  State<_DocumentListPanel> createState() => _DocumentListPanelState();
}

class _DocumentListPanelState extends State<_DocumentListPanel> {
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;

  Future<void> _uploadDocument() async {
    // Returns the picked file's local path, from whichever source the
    // admin chooses — camera/gallery give an image, "Choose Document"
    // lets the admin pick a PDF, Word, Excel, PowerPoint or text file.
    final String? pickedPath = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text("Take Photo"),
              onTap: () async {
                final f = await _picker.pickImage(source: ImageSource.camera);
                if (ctx.mounted) Navigator.pop(ctx, f?.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Choose from Gallery"),
              onTap: () async {
                final f = await _picker.pickImage(source: ImageSource.gallery);
                if (ctx.mounted) Navigator.pop(ctx, f?.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text("Choose Document"),
              subtitle: const Text("PDF, Word, Excel, PowerPoint, text"),
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: _pickableDocumentExtensions,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx, result?.files.single.path);
                }
              },
            ),
          ],
        ),
      ),
    );

    if (pickedPath == null) return;
    if (!mounted) return;

    final TextEditingController titleController = TextEditingController();
    bool markImportant = false;
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Document Name"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "e.g. CNIC Copy, B-Form, Certificate",
                  border: OutlineInputBorder(),
                ),
              ),
              // Important documents (B-Form, CNIC, etc.) show at the top
              // of the parent's documents list.
              CheckboxListTile(
                value: markImportant,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text("Mark as Important",
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text("Parents ko sab se upar dikhega",
                    style: TextStyle(fontSize: 12)),
                onChanged: (v) =>
                    setDialogState(() => markImportant = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'title': titleController.text.trim(),
                'important': markImportant,
              }),
              child: const Text("Upload"),
            ),
          ],
        ),
      ),
    );

    final String title = (result?['title'] as String?) ?? '';
    if (title.isEmpty) return;
    final bool important = (result?['important'] as bool?) ?? false;

    setState(() => _uploading = true);
    try {
      final cloudinary = CloudinaryPublic('niilo9ek', 'shafi073', cache: false);
      final String ext = pickedPath.split('.').last.toLowerCase();
      final resourceType = _imageLikeExtensions.contains(ext)
          ? CloudinaryResourceType.Auto
          : CloudinaryResourceType.Raw;
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          pickedPath,
          resourceType: resourceType,
          folder: 'documents/${widget.ownerType}/${widget.ownerId}',
        ),
      );

      await schoolCollection('documents').add({
        'ownerType': widget.ownerType,
        'ownerId': widget.ownerId,
        'ownerName': widget.ownerName,
        'title': title,
        'url': response.secureUrl,
        'important': important,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Document uploaded successfully."),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteDocument(DocumentSnapshot doc) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Document"),
        content: const Text("Are you sure you want to delete this document?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await doc.reference.delete();
    }
  }

  void _viewDocument(String url, String title) {
    // Only actual image files render inline; PDFs and other document
    // types (Word, Excel, PowerPoint, text) open/download externally
    // instead, since Image.network can't display them.
    if (!_looksLikeImage(url)) {
      _openOrDownload(context, url);
      return;
    }
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
                        "Preview not available — open the document via the link."),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: Colors.deepPurple[50],
          child: Row(
            children: [
              const Icon(Icons.folder_shared, color: Colors.deepPurple),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.ownerName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (widget.headerSubtitle.isNotEmpty)
                      Text(widget.headerSubtitle,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _uploading ? null : _uploadDocument,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file, size: 18),
                label: const Text("Upload"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple[700],
                    foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: schoolCollection('documents')
                .where('ownerType', isEqualTo: widget.ownerType)
                .where('ownerId', isEqualTo: widget.ownerId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text("Error: ${snapshot.error}",
                      style: const TextStyle(color: Colors.red)),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text("No documents uploaded yet.",
                      style: TextStyle(color: Colors.grey[600])),
                );
              }

              var docs = snapshot.data!.docs;
              // Client-side sort — latest upload first (without needing a
              // composite index).
              docs.sort((a, b) {
                var ta = (a.data() as Map<String, dynamic>)['uploadedAt'];
                var tb = (b.data() as Map<String, dynamic>)['uploadedAt'];
                if (ta == null || tb == null) return 0;
                return (tb as Timestamp).compareTo(ta as Timestamp);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var doc = docs[index];
                  var data = doc.data() as Map<String, dynamic>;
                  String title = data['title'] ?? 'Document';
                  String url = data['url'] ?? '';
                  bool important = data['important'] == true;
                  String date = "N/A";
                  if (data['uploadedAt'] != null) {
                    date = DateFormat('dd-MM-yyyy HH:mm')
                        .format((data['uploadedAt'] as Timestamp).toDate());
                  }
                  bool isImage = _looksLikeImage(url);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        isImage ? Icons.image : Icons.picture_as_pdf,
                        color: Colors.deepPurple,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (important) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.star,
                                color: Colors.amber, size: 16),
                          ],
                        ],
                      ),
                      subtitle: Text("Uploaded: $date"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.download,
                                color: Colors.deepPurple),
                            tooltip: "Open / Download",
                            onPressed: () => _openOrDownload(context, url),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            tooltip: "Delete",
                            onPressed: () => _deleteDocument(doc),
                          ),
                        ],
                      ),
                      onTap: () => _viewDocument(url, title),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
