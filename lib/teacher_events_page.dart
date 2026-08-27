import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

// Read-only events page for teachers.
// Shows events added by admin from the same 'school_events' collection —
// teachers can only view, no add/delete controls here.
class TeacherEventsPage extends StatelessWidget {
  const TeacherEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("School Events"),
        backgroundColor: Colors.teal[800],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('school_events')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No Events."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading:
                      const Icon(Icons.event, color: Colors.teal, size: 30),
                  title: Text(data['title'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      "Date: ${data['eventDate'] ?? ''}\n${data['description'] ?? ''}"),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
