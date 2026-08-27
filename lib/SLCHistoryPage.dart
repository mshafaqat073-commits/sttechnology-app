import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

class SLCHistoryPage extends StatelessWidget {
  const SLCHistoryPage({super.key});

  // Record Restore karne ka function
  Future<void> _restoreStudent(BuildContext context, DocumentSnapshot doc) async {
  // 1. SLC record se student ka original ID dhundo (agar store kiya hai)
  // Ya agar humne pura data SLC mein copy kiya hai:
  String studentName = doc['name'];

  // 2. Wapas status 'active' kar dein
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