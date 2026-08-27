import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

class TeacherEnterResultPage extends StatefulWidget {
  // Teacher's assigned class/section list. Each entry looks like
  // {'class': '6', 'section': 'A'} — an empty section means the whole
  // class is allowed. Student search + result entry is restricted to
  // only these classes.
  final List<Map<String, String>> allowedClasses;

  const TeacherEnterResultPage({super.key, required this.allowedClasses});

  @override
  State<TeacherEnterResultPage> createState() => _TeacherEnterResultPageState();
}

class _TeacherEnterResultPageState extends State<TeacherEnterResultPage> {
  final _formKey = GlobalKey<FormState>();

  // Selected Student Info
  String? _selectedStudentId;
  String _studentName = '';
  String _fatherName = '';
  String _className = '';
  String _section = '';
  String _rollNo = '';

  // Term / Exam Controller or Selected Value
  final TextEditingController _termController =
      TextEditingController(text: 'Weekly Test');
  final List<String> _termOptions = [
    'First Term',
    'Mid Term',
    'Final Term',
    'Monthly Test',
    'Weekly Test'
  ];

  // Search Controller
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // Subjects Dynamic List
  final List<Map<String, TextEditingController>> _subjectRows = [];

  @override
  void initState() {
    super.initState();
    _addSubjectRow(); // Start with at least one subject row
  }

  void _addSubjectRow() {
    setState(() {
      _subjectRows.add({
        'subject': TextEditingController(),
        'total': TextEditingController(),
        'obtained': TextEditingController(),
      });
    });
  }

  bool get _isRestricted => widget.allowedClasses.isNotEmpty;

  bool _isAllowedStudent(Map<String, dynamic> data) {
    if (!_isRestricted) return true;
    String cls = (data['class'] ?? '').toString();
    String sec = (data['section'] ?? '').toString();
    return widget.allowedClasses.any((a) {
      final aClass = a['class'] ?? '';
      final aSection = a['section'] ?? '';
      if (aClass != cls) return false;
      if (aSection.isEmpty) return true; // whole class assigned, any section
      return aSection == sec;
    });
  }

  String get _allowedClassesLabel => widget.allowedClasses
      .map((a) => a['section']!.isNotEmpty
          ? "${a['class']} - ${a['section']}"
          : a['class']!)
      .join(", ");

  void _removeSubjectRow(int index) {
    if (_subjectRows.length > 1) {
      setState(() {
        _subjectRows[index]['subject']!.dispose();
        _subjectRows[index]['total']!.dispose();
        _subjectRows[index]['obtained']!.dispose();
        _subjectRows.removeAt(index);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _termController.dispose();
    for (var row in _subjectRows) {
      row['subject']!.dispose();
      row['total']!.dispose();
      row['obtained']!.dispose();
    }
    super.dispose();
  }

  Future<void> _submitResult() async {
    if (_selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select student first!")),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_isRestricted &&
        !_isAllowedStudent({'class': _className, 'section': _section})) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You only enter result to your asign class."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    List<Map<String, dynamic>> subjectsData = [];
    double grandTotal = 0;
    double grandObtained = 0;

    for (var row in _subjectRows) {
      String subName = row['subject']!.text.trim();
      double total = double.parse(row['total']!.text.trim());
      double obtained = double.parse(row['obtained']!.text.trim());

      if (obtained > total) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Subject '$subName' obtain marks not higher then total marks!")),
        );
        return;
      }

      grandTotal += total;
      grandObtained += obtained;

      subjectsData.add({
        'subjectName': subName,
        'totalMarks': total,
        'obtainedMarks': obtained,
      });
    }

    double percentage = grandTotal > 0 ? (grandObtained / grandTotal) * 100 : 0;
    String grade = _calculateGrade(percentage);

    try {
      await schoolCollection('results').add({
        'studentId': _selectedStudentId,
        'name': _studentName,
        'fName': _fatherName,
        'class': _className,
        'section': _section,
        'rollNo': _rollNo,
        'term': _termController.text.trim(),
        'subjects': subjectsData,
        'grandTotal': grandTotal,
        'grandObtained': grandObtained,
        'percentage': percentage.toStringAsFixed(2),
        'grade': grade,
        'date': Timestamp.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Result entered successfully!"),
              backgroundColor: Colors.green),
        );
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _calculateGrade(double percentage) {
    if (percentage >= 80) return 'A+';
    if (percentage >= 70) return 'A';
    if (percentage >= 60) return 'B';
    if (percentage >= 50) return 'C';
    if (percentage >= 40) return 'D';
    return 'F';
  }

  void _clearForm() {
    setState(() {
      _selectedStudentId = null;
      _studentName = '';
      _fatherName = '';
      _className = '';
      _section = '';
      _rollNo = '';
      _searchController.clear();
      _termController.text = 'Weekly Test';
      _isSearching = false;
      for (var row in _subjectRows) {
        row['subject']!.clear();
        row['total']!.clear();
        row['obtained']!.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Enter Student Result"),
        backgroundColor: Colors.teal[800],
      ),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (_isRestricted)
                Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.teal.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "You can only enter results for these classes: $_allowedClassesLabel",
                          style: TextStyle(
                              fontSize: 12, color: Colors.teal.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              // --- STUDENT SEARCH SECTION ---
              Text("Search Student",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800],
                      fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Enter student name",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (value) {
                  setState(() {
                    _isSearching = value.trim().isNotEmpty;
                  });
                },
              ),

              // Search Results Dropdown/List View
              if (_isSearching)
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: schoolCollection('students')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      var docs = snapshot.hasData ? snapshot.data!.docs : [];
                      var query = _searchController.text.toLowerCase();

                      var filteredDocs = docs.where((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        var name =
                            (data['name'] ?? '').toString().toLowerCase();
                        return name.contains(query) && _isAllowedStudent(data);
                      }).toList();

                      if (filteredDocs.isEmpty) {
                        return const Center(child: Text("Student not found"));
                      }

                      return ListView.builder(
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          var data = filteredDocs[index].data()
                              as Map<String, dynamic>;
                          return ListTile(
                            title: Text(data['name'] ?? 'N/A',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                "Class: ${data['class']} | Section: ${data['section'] ?? 'N/A'} | Father: ${data['fName'] ?? data['fatherName'] ?? 'N/A'}"),
                            onTap: () {
                              setState(() {
                                _selectedStudentId = filteredDocs[index].id;
                                _studentName = data['name'] ?? '';
                                _fatherName =
                                    data['fName'] ?? data['fatherName'] ?? '';
                                _className = data['class'] ?? '';
                                _section = data['section'] ?? '';
                                _rollNo =
                                    (data['rollNo'] ?? data['rollNumber'] ?? '')
                                        .toString();
                                _searchController.text = _studentName;
                                _isSearching = false;
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),

              const SizedBox(height: 15),

              // --- AUTO-FILLED DETAILS CARD ---
              if (_selectedStudentId != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    border: Border.all(color: Colors.teal.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Name: $_studentName",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text("Father Name: $_fatherName"),
                      Text(
                          "Class: $_className | Section: ${_section.isEmpty ? 'N/A' : _section} | Roll No: $_rollNo"),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // --- EXAM / TERM SELECTION SECTION ---
              Text("Exam Term / Title",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800],
                      fontSize: 16)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _termOptions.contains(_termController.text)
                    ? _termController.text
                    : null,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                hint: const Text("Select Exam Term"),
                items: _termOptions.map((String term) {
                  return DropdownMenuItem<String>(
                    value: term,
                    child: Text(term),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    if (newValue != null) {
                      _termController.text = newValue;
                    }
                  });
                },
                validator: (val) =>
                    val == null || val.isEmpty ? 'Please select a term' : null,
              ),

              const SizedBox(height: 20),
              const Divider(thickness: 2),
              const Text("Subjects & Marks",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),

              // --- DYNAMIC SUBJECT ROWS ---
              ...List.generate(_subjectRows.length, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _subjectRows[index]['subject'],
                          decoration: const InputDecoration(
                              labelText: "Subject Name",
                              border: OutlineInputBorder()),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _subjectRows[index]['total'],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: "Total", border: OutlineInputBorder()),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _subjectRows[index]['obtained'],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: "Obtained",
                              border: OutlineInputBorder()),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                        ),
                      ),
                      if (_subjectRows.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeSubjectRow(index),
                        ),
                    ],
                  ),
                );
              }),

              // Add Subject Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal.shade800),
                onPressed: _addSubjectRow,
                icon: const Icon(Icons.add),
                label: const Text("Add Subject"),
              ),

              const SizedBox(height: 25),

              // Submit Result Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal[800],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _submitResult,
                child: const Text("Enter Result",
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      )),
    );
  }
}
