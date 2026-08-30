import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'student_issue_page.dart';

// Read-only view of Diary / Homework / Special Message for one student's
// class & section. Reads the same collections home_task_page.dart (admin)
// writes to: 'school_diary', 'school_homework', 'special_messages'.
// A record with no section set (whole-class) is shown to every section too.
//
// Also shows a 4th "Issues" tab — private messages posted for this exact
// child only (via StudentIssuesParentList), filtered strictly by
// studentId so siblings/classmates never see each other's messages.
class ParentHomeTaskPage extends StatefulWidget {
  final String className;
  final String section;
  // This child's own document id in the 'students' collection.
  final String studentId;

  const ParentHomeTaskPage({
    super.key,
    required this.className,
    required this.section,
    required this.studentId,
  });

  @override
  State<ParentHomeTaskPage> createState() => _ParentHomeTaskPageState();
}

class _ParentHomeTaskPageState extends State<ParentHomeTaskPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  bool _appliesToChild(Map<String, dynamic> data) {
    final section = (data['section'] ?? '').toString().trim().toLowerCase();
    final childSection = widget.section.trim().toLowerCase();
    if (section.isEmpty || section == 'not selected') return true;
    return section == childSection;
  }

  List<QueryDocumentSnapshot> _filterAndSort(List<QueryDocumentSnapshot> docs) {
    var filtered = docs
        .where((d) => _appliesToChild(d.data() as Map<String, dynamic>))
        .toList();
    filtered.sort((a, b) {
      final ta = (a.data() as Map)['date'] as Timestamp?;
      final tb = (b.data() as Map)['date'] as Timestamp?;
      if (ta == null || tb == null) return 0;
      return tb.compareTo(ta);
    });
    return filtered;
  }

  Widget _buildList(String collection, Widget Function(Map<String, dynamic>) cardBuilder) {
    return StreamBuilder<QuerySnapshot>(
      stream: schoolCollection(collection)
          .where('class', isEqualTo: widget.className)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = _filterAndSort(snapshot.data!.docs);
        if (docs.isEmpty) {
          return const Center(child: Text("Nothing posted yet."));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) =>
              cardBuilder(docs[index].data() as Map<String, dynamic>),
        );
      },
    );
  }

  Widget _card({required IconData icon, required Color color, required String title, required String body, required String dateString}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                ),
                Text(dateString,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home Task", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.indigo[700],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: "Diary"),
            Tab(text: "Homework"),
            Tab(text: "Message"),
            Tab(text: "Issues"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList('school_diary', (d) => _card(
                icon: Icons.menu_book,
                color: Colors.teal,
                title: "School Diary",
                body: d['diary']?.toString() ?? '',
                dateString: d['dateString']?.toString() ?? '',
              )),
          _buildList('school_homework', (d) => _card(
                icon: Icons.task_alt,
                color: Colors.deepOrange,
                title: d['subject']?.toString() ?? 'Homework',
                body: d['homework']?.toString() ?? '',
                dateString: d['dateString']?.toString() ?? '',
              )),
          _buildList('special_messages', (d) => _card(
                icon: Icons.campaign,
                color: Colors.purple,
                title: "Special Message",
                body: d['message']?.toString() ?? '',
                dateString: d['dateString']?.toString() ?? '',
              )),
          StudentIssuesParentList(studentId: widget.studentId),
        ],
      ),
    );
  }
}
