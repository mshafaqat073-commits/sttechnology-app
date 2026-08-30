import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'class_detail_page.dart';
import 'school_context.dart';

class ClassSelectionPage extends StatelessWidget {
  const ClassSelectionPage({super.key});

  // Fixed academic order (Playgroup through Ten)
  static const List<String> _baseClassesOrder = [
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

  // Keeps new/custom classes at the top (-1),
  // rest follow the fixed academic order.
  int _compareClasses(String? classA, String? classB) {
    final String a = classA ?? '';
    final String b = classB ?? '';

    final int ai = _baseClassesOrder.indexOf(a);
    final int bi = _baseClassesOrder.indexOf(b);

    if (ai == -1 && bi == -1) return a.compareTo(b);
    if (ai == -1) return -1;
    if (bi == -1) return 1;

    return ai.compareTo(bi);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Class"),
        backgroundColor: Colors.teal[800],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Listens to live active students from Firestore.
        stream: schoolCollection('students')
            .where('status', isEqualTo: 'active')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text("Error: ${snapshot.error}"),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // Build a unique list from all students' classes.
          final Set<String> classSet = {};

          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final String cls = data['class']?.toString() ?? '';

            if (cls.isNotEmpty && cls != 'Not Selected') {
              classSet.add(cls);
            }
          }

          final List<String> classes = classSet.toList()..sort(_compareClasses);

          if (classes.isEmpty) {
            return const Center(
              child: Text("No active students found."),
            );
          }

          // Responsive class grid
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 1100,
              ),
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  childAspectRatio: 2.4,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: classes.length + 1,
                itemBuilder: (context, index) {
                  // --------------------------------------------------
                  // ALL STUDENTS
                  // --------------------------------------------------
                  if (index == 0) {
                    return ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ClassDetailPage(
                              className: 'All',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[800],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        "All Students",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    );
                  }

                  // --------------------------------------------------
                  // NORMAL CLASS
                  // --------------------------------------------------
                  final String className = classes[index - 1];

                  return ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClassDetailPage(
                            className: className,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[600],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      className,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
