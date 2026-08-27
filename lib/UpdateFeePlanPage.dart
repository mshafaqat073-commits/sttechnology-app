import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';
import 'subscription_gate.dart';

class UpdateFeePlanPage extends StatefulWidget {
  const UpdateFeePlanPage({super.key});

  @override
  State<UpdateFeePlanPage> createState() => _UpdateFeePlanPageState();
}

class _UpdateFeePlanPageState extends State<UpdateFeePlanPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _feeController = TextEditingController();
  DocumentSnapshot? _studentDoc;
  bool _isLoading = false;

  // Live search variables
  List<QueryDocumentSnapshot> _searchResults = [];
  bool _isSearching = false;

  // Live search function for student name or family ID
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
      // is case-sensitive, so instead we fetch all active students and do a
      // case-insensitive "contains" match on the client — this way even a
      // single letter (uppercase or lowercase) shows the student right away.
      var activeSnapshot = await schoolCollection('students')
          .where('status', isEqualTo: 'active')
          .get();

      List<QueryDocumentSnapshot> results = activeSnapshot.docs.where((doc) {
        var data = doc.data();
        String name = (data['name'] ?? '').toString().toLowerCase();
        return name.contains(queryLower);
      }).toList();

      if (results.isEmpty) {
        results = activeSnapshot.docs.where((doc) {
          var data = doc.data();
          String familyId = (data['familyId'] ?? '').toString().toLowerCase();
          return familyId.contains(queryLower);
        }).toList();
      }

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint("Live Search Error: $e");
      setState(() => _isSearching = false);
    }
  }

  // Function to load fee data
  // The 'students' collection is always treated as the source of truth —
  // no override is taken from fee_structures.
  void _loadFeeData(QueryDocumentSnapshot student) {
    setState(() {
      _studentDoc = student;
      var data = student.data() as Map<String, dynamic>;
      _searchController.text = data['name'] ?? "";
      _feeController.text =
          data.containsKey('monthlyFee') ? data['monthlyFee'].toString() : "0";
      _searchResults = []; // Hide search results after selection
      _isLoading = false;
    });
  }

  Future<void> _updateFeePlan() async {
    if (_studentDoc == null) return;
    if (!await SubscriptionGuard.ensureActive(context)) return;

    setState(() => _isLoading = true);

    try {
      int newFee = int.tryParse(_feeController.text.trim()) ?? 0;

      // Only update the 'students' collection — this is the same collection
      // student_detail_page also reads/writes monthlyFee from.
      var studentRef = schoolCollection('students').doc(_studentDoc!.id);
      await studentRef.update({'monthlyFee': newFee});

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Fee Successfully Updated!")),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Update Fee Plan"),
        backgroundColor: Colors.teal[800],
      ),
      body: SafeArea(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Live Search TextField & Suggestions List
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: "Search Student Name or Family ID",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                        if (_isSearching)
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        if (_searchResults.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                  spreadRadius: 2,
                                  blurRadius: 5,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                var data = _searchResults[index].data()
                                    as Map<String, dynamic>;
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.person,
                                      color: Colors.teal, size: 20),
                                  title: Text(data['name'] ?? "No Name",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                      "Father: ${data['fName'] ?? 'N/A'} | Class: ${data['class'] ?? 'N/A'}"),
                                  onTap: () {
                                    _loadFeeData(_searchResults[index]);
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // Student Fee Edit Section
                    if (_studentDoc != null) ...[
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Student: ${_studentDoc!['name']}",
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal)),
                              const SizedBox(height: 4),
                              Text(
                                  "Father: ${_studentDoc!['fName'] ?? 'N/A'} | Class: ${_studentDoc!['class'] ?? 'N/A'}",
                                  style:
                                      const TextStyle(color: Colors.black54)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _feeController,
                        decoration: const InputDecoration(
                          labelText: "Monthly Fee",
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                            onPressed: _updateFeePlan,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal[800],
                                foregroundColor: Colors.white),
                            child: const Text("SAVE NEW FEE",
                                style: TextStyle(fontWeight: FontWeight.bold))),
                      )
                    ]
                  ],
                ),
              ),
            )),
    );
  }
}
