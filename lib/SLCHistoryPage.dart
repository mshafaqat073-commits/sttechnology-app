import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

class SLCHistoryPage extends StatelessWidget {
  const SLCHistoryPage({super.key});

  // Function to restore a record
  Future<void> _restoreStudent(BuildContext context, DocumentSnapshot doc) async {
  // 1. Find the student's original ID from the SLC record (if it was stored)
  // Or, since we've copied the full data into SLC:
  String studentName = doc['name'];

  // 2. Set the status back to 'active'
  var studentRef = await schoolCollection('students')
      .where('name', isEqualTo: studentName)
      .get();
      
  if (studentRef.docs.isNotEmpty) {
    await studentRef.docs.first.reference.update({'status': 'active'});
  }

  // 3. SLC record delete kar dein
  await doc.reference.delete();
  
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Student reactivated!")));
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SLC History (Restore)")),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('SLC').orderBy('date', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              
              return ListTile(
                title: Text(data['name']),
                subtitle: Text("GR: ${data['grNumber']} | Class: ${data['class']}"),
                trailing: const Icon(Icons.restore, color: Colors.blue),
                onLongPress: () => _restoreStudent(context, doc), // LONG PRESS TO RESTORE
              );
            },
          );
        },
      ),
    );
  }
}