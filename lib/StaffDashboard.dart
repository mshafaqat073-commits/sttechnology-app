import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_staff_page.dart'; // Nayi file banani hogi
import 'staff_detail_page.dart';
import 'school_context.dart';
import 'app_update_checker.dart';

class StaffDashboard extends StatelessWidget {
  const StaffDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Staff Management"),
          backgroundColor: Colors.brown,
          actions: [
            IconButton(
              icon: const Icon(Icons.system_update_alt, color: Colors.white),
              tooltip: "Check for Update",
              onPressed: () => AppUpdateChecker.of(context)
                  ?.checkForUpdate(showResult: true),
            ),
          ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (context) => AddStaffPage())),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(child: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('staff').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data!.docs;

          // Stats
          int total = docs.length;
          int male =
              docs.where((d) => (d.data() as Map)['gender'] == 'Male').length;
          int female =
              docs.where((d) => (d.data() as Map)['gender'] == 'Female').length;
          int nonTeaching = docs
              .where((d) => (d.data() as Map)['category'] == 'Non-Teaching')
              .length;

          return Column(
            children: [
              Container(
                  padding: const EdgeInsets.all(15),
                  color: Colors.brown[50],
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text("Total: $total"),
                        Text("M: $male | F: $female"),
                        Text("Non-T: $nonTeaching")
                      ])),
              Expanded(
                  child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var doc = docs[index];
                  var data = doc.data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(data['name']),
                    subtitle:
                        Text("${data['designation']} | ${data['category']}"),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                StaffDetailPage(docId: doc.id, data: data))),
                    onLongPress: () => _deleteStaff(context, doc.id),
                  );
                },
              ))
            ],
          );
        },
      )),
    );
  }

  void _deleteStaff(BuildContext context, String docId) async {
    bool? confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text("Delete Staff"),
                content: const Text("Confirm delete?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Cancel")),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Delete",
                          style: TextStyle(color: Colors.red))),
                ]));
    if (confirm == true) {
      await schoolCollection('staff').doc(docId).delete();
    }
  }
}
