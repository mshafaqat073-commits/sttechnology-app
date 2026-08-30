import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'school_context.dart';

/// Admin can use this page to see which Parents and Staff members have
/// opened the app (and when last), and who hasn't used the app at all yet
/// (authUid missing = never logged in/used the app).
///
/// Data source: the 'authUid' and 'lastLoginAt' fields on the 'students'
/// (parent side) and 'staff' collections — updated by main.dart's
/// _RoleRouter on every successful login.
class AppUsagePage extends StatefulWidget {
  const AppUsagePage({super.key});

  @override
  State<AppUsagePage> createState() => _AppUsagePageState();
}

class _AppUsagePageState extends State<AppUsagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Streams are created once in initState — previously these were
  // created directly inside build(), which caused Firestore to
  // reconnect (a new listener) on every tab switch or any rebuild.
  late final Stream<QuerySnapshot> _parentsStream = schoolCollection('students')
      .where('status', isEqualTo: 'active')
      .snapshots();
  late final Stream<QuerySnapshot> _staffStream =
      schoolCollection('staff').snapshots();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatLastLogin(Timestamp? ts) {
    if (ts == null) return 'Never used the app';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Active just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Usage', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal[800],
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.yellowAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Parents'),
            Tab(text: 'Staff'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildParentsList(),
          _buildStaffList(),
        ],
      ),
    );
  }

  Widget _buildParentsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _parentsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snapshot.data!.docs.toList();
        // Show those who have used the app (have lastLoginAt) at the top,
        // most recent first. Those who never used it go below.
        docs.sort((a, b) {
          final aTs =
              (a.data() as Map<String, dynamic>)['lastLoginAt'] as Timestamp?;
          final bTs =
              (b.data() as Map<String, dynamic>)['lastLoginAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });

        final usedCount = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['lastLoginAt'] != null;
        }).length;

        return Column(
          children: [
            _summaryBar('$usedCount / ${docs.length} parents have used the app'),
            Expanded(
              child: ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final Timestamp? lastLogin = data['lastLoginAt'];
                  final bool hasAuth =
                      (data['authUid'] as String?)?.isNotEmpty == true;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          hasAuth ? Colors.green[100] : Colors.grey[300],
                      child: Icon(
                        hasAuth ? Icons.check_circle : Icons.person_off,
                        color: hasAuth ? Colors.green[800] : Colors.grey[600],
                      ),
                    ),
                    title: Text(data['name'] ?? 'Unnamed'),
                    subtitle: Text(
                        '${data['class'] ?? ''} - ${data['section'] ?? ''} | Father: ${data['fName'] ?? '-'}'),
                    trailing: Text(
                      _formatLastLogin(lastLogin),
                      style: TextStyle(
                        fontSize: 12,
                        color: lastLogin != null
                            ? Colors.green[800]
                            : Colors.grey,
                        fontWeight: lastLogin != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStaffList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _staffStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snapshot.data!.docs.toList();
        docs.sort((a, b) {
          final aTs =
              (a.data() as Map<String, dynamic>)['lastLoginAt'] as Timestamp?;
          final bTs =
              (b.data() as Map<String, dynamic>)['lastLoginAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });

        final usedCount = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['lastLoginAt'] != null;
        }).length;

        return Column(
          children: [
            _summaryBar('$usedCount / ${docs.length} staff members have used the app'),
            Expanded(
              child: ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final Timestamp? lastLogin = data['lastLoginAt'];
                  final bool hasAuth =
                      (data['authUid'] as String?)?.isNotEmpty == true;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          hasAuth ? Colors.green[100] : Colors.grey[300],
                      child: Icon(
                        hasAuth ? Icons.check_circle : Icons.person_off,
                        color: hasAuth ? Colors.green[800] : Colors.grey[600],
                      ),
                    ),
                    title: Text(data['name'] ?? 'Unnamed'),
                    subtitle: Text(data['designation'] ??
                        data['role'] ??
                        'Staff'),
                    trailing: Text(
                      _formatLastLogin(lastLogin),
                      style: TextStyle(
                        fontSize: 12,
                        color: lastLogin != null
                            ? Colors.green[800]
                            : Colors.grey,
                        fontWeight: lastLogin != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryBar(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        color: Colors.teal[50],
        child: Text(text,
            style: TextStyle(
                color: Colors.teal[800], fontWeight: FontWeight.bold)),
      );
}
