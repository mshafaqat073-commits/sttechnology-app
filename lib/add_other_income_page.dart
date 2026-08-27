import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'responsive_grid.dart';
import 'school_context.dart';
import 'subscription_gate.dart';

class AddIncomeOrFeePage extends StatefulWidget {
  const AddIncomeOrFeePage({super.key});

  @override
  State<AddIncomeOrFeePage> createState() => _AddIncomeOrFeePageState();
}

class _AddIncomeOrFeePageState extends State<AddIncomeOrFeePage> {
  final TextEditingController _searchController = TextEditingController();

  // These are "final value" fields — when a student is selected, they get
  // pre-filled with the current (existing) fee_structures value. On submit,
  // whatever value is written here becomes the final value
  // (overwrite/update — it does not add to the old value).
  final Map<String, TextEditingController> _controllers = {
    'admissionFee': TextEditingController(text: '0'),
    'monthlyFee': TextEditingController(text: '0'),
    'books': TextEditingController(text: '0'),
    'notebooks': TextEditingController(text: '0'),
    'diary': TextEditingController(text: '0'),
    'file': TextEditingController(text: '0'),
    'paperMoney': TextEditingController(text: '0'),
    'stationary': TextEditingController(text: '0'),
    'uniform': TextEditingController(text: '0'),
    'other': TextEditingController(text: '0'),
  };

  final Map<String, String> _fieldLabels = {
    'admissionFee': 'Admission Fee',
    'monthlyFee': 'Monthly Fee',
    'books': 'Books',
    'notebooks': 'Notebooks',
    'diary': 'Diary',
    'file': 'File',
    'paperMoney': 'Paper Money',
    'stationary': 'Stationary',
    'uniform': 'Uniform',
    'other': 'Other',
  };

  // These default fields cannot be deleted
  final Set<String> _defaultFieldKeys = {
    'admissionFee',
    'monthlyFee',
    'books',
    'notebooks',
    'diary',
    'file',
    'paperMoney',
    'stationary',
    'uniform',
    'other',
  };

  DocumentSnapshot? _selectedStudentDoc;
  bool _isSaving = false;

  // Live search variables
  List<QueryDocumentSnapshot> _searchResults = [];
  bool _isSearching = false;

  // Converts the name typed by the user into a Firestore-friendly camelCase key
  String _labelToKey(String label) {
    final words = label.trim().split(RegExp(r'\s+'));
    String key =
        words.first.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    for (int i = 1; i < words.length; i++) {
      String w = words[i].replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      if (w.isNotEmpty) {
        key += w[0].toUpperCase() + w.substring(1).toLowerCase();
      }
    }
    return key.isEmpty ? 'field${DateTime.now().millisecondsSinceEpoch}' : key;
  }

  // Converts a camelCase field name into a readable label (used as a fallback)
  String _formatFieldLabel(String key) {
    if (key.isEmpty) return key;
    String spaced =
        key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  Future<void> _showAddFieldDialog() async {
    final TextEditingController newFieldController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Add New Fee Field"),
        content: TextField(
          controller: newFieldController,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: "Field name (e.g. Exam Fee)"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              String label = newFieldController.text.trim();
              if (label.isEmpty) {
                Navigator.pop(dialogContext);
                return;
              }
              String key = _labelToKey(label);
              if (_controllers.containsKey(key)) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("this field is already set!"),
                    backgroundColor: Colors.red));
                return;
              }
              setState(() {
                _controllers[key] = TextEditingController(text: '0');
                _fieldLabels[key] = label;
              });
              Navigator.pop(dialogContext);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  void _removeField(String key) {
    setState(() {
      _controllers[key]?.dispose();
      _controllers.remove(key);
      _fieldLabels.remove(key);
    });
  }

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

  // Load selected student — fetches current values from fee_structures and
  // fills them directly into the controllers, so staff can edit/update them
  // directly (whatever is written becomes the final value).
  Future<void> _loadStudentData(QueryDocumentSnapshot student) async {
    var data = student.data() as Map<String, dynamic>;
    setState(() {
      _selectedStudentDoc = student;
      _searchController.text = data['name'] ?? "";
      _searchResults = []; // Hide search results after selection
    });

    try {
      var feeDoc =
          await schoolCollection('fee_structures').doc(student.id).get();

      Map<String, dynamic> feeData =
          feeDoc.exists ? (feeDoc.data() as Map<String, dynamic>) : {};

      // If the student's fee doc has a custom field that isn't in this
      // form's list yet, include it in the list as well.
      feeData.forEach((key, value) {
        if (key == 'studentId' ||
            key == 'name' ||
            key == 'fName' ||
            key == 'class' ||
            key == 'section' ||
            key == 'updatedAt') {
          return; // meta fields, fee field nahi
        }
        if (!_controllers.containsKey(key)) {
          _controllers[key] = TextEditingController(text: '0');
          _fieldLabels[key] = _formatFieldLabel(key);
        }
      });

      if (mounted) {
        setState(() {
          // Fill each field with its current value — if the field doesn't
          // exist in the fee doc, it starts at 0.
          for (var key in _controllers.keys) {
            var existing = feeData[key];
            _controllers[key]!.text =
                existing != null ? existing.toString() : '0';
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading fee structure: $e");
    }
  }

  // Overwrites (updates) each field with whatever value is written in the
  // form — it does not add to the old value, it directly sets the final
  // value.
  Future<void> _submitEntry() async {
    if (!await SubscriptionGuard.ensureActive(context)) return;
    if (_selectedStudentDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select a student first!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      var studentData = _selectedStudentDoc!.data() as Map<String, dynamic>;

      Map<String, dynamic> updateData = {};
      _controllers.forEach((key, controller) {
        double amount = double.tryParse(controller.text.trim()) ?? 0.0;
        updateData[key] = amount;
      });

      await schoolCollection('fee_structures')
          .doc(_selectedStudentDoc!.id)
          .set({
        'studentId': _selectedStudentDoc!.id,
        'name': studentData['name'] ?? '',
        'fName': studentData['fName'] ?? '',
        'class': studentData['class'] ?? '',
        ...updateData,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Fee Structure Updated Successfully!"),
              backgroundColor: Colors.green),
        );
        setState(() {
          _selectedStudentDoc = null;
          _searchController.clear();
          for (var key in _controllers.keys) {
            _controllers[key]!.text = '0';
          }
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Income / Extra Fee"),
        backgroundColor: Colors.teal[800],
      ),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Live Search TextField and Suggestions List
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: "Search Student by Name or Family ID",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                  if (_isSearching)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
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
                              _loadStudentData(_searchResults[index]);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Selected Student Details Card (if selected)
              if (_selectedStudentDoc != null) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Selected Student",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.teal)),
                        const Divider(),
                        _infoTile(
                            "Name",
                            (_selectedStudentDoc!.data() as Map)['name'] ??
                                'N/A'),
                        _infoTile(
                            "Father Name",
                            (_selectedStudentDoc!.data() as Map)['fName'] ??
                                'N/A'),
                        _infoTile(
                            "Class",
                            (_selectedStudentDoc!.data() as Map)['class'] ??
                                'N/A'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Each field below is pre-filled with its current value — whatever value you type becomes that field's final value (overwrite).",
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Fee Structure Input Fields — ab dynamic list se, "amount to add"
              ResponsiveGrid(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossSpacing: 12,
                mainSpacing: 16,
                aspectRatio: 2.2,
                children: _controllers.keys.map((key) {
                  return _buildFeeTextField(
                    _fieldLabels[key] ?? _formatFieldLabel(key),
                    _controllers[key]!,
                    isCustom: !_defaultFieldKeys.contains(key),
                    onRemove: () => _removeField(key),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showAddFieldDialog,
                  icon: const Icon(Icons.add, color: Colors.teal),
                  label: const Text("Add New Field",
                      style: TextStyle(
                          color: Colors.teal, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[800]),
                  onPressed: _isSaving ? null : _submitEntry,
                  child: _isSaving
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text("Saving...",
                                style: TextStyle(color: Colors.white)),
                          ],
                        )
                      : const Text("UPDATE FEE STRUCTURE",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }

  Widget _buildFeeTextField(String label, TextEditingController controller,
      {bool isCustom = false, VoidCallback? onRemove}) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        suffixIcon: isCustom
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 18),
                tooltip: "Remove field",
                onPressed: onRemove,
              )
            : null,
      ),
    );
  }

  Widget _infoTile(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: Colors.black54)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
