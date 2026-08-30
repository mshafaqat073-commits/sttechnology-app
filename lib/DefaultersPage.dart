import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notification_helper.dart';
import 'school_context.dart';
import 'school_branding.dart';

class DefaultersPage extends StatefulWidget {
  const DefaultersPage({super.key});

  @override
  State<DefaultersPage> createState() => _DefaultersPageState();
}

class _DefaultersPageState extends State<DefaultersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Word-by-word search: splits the query on spaces and looks for each
  // word in the student's name, father's name, and class. All the
  // words that were typed must match (in any order) — this makes
  // searches like "ali 5th" or "khan ali" work too.
  bool _matchesSearch(Map<String, dynamic> studentData) {
    if (_searchQuery.trim().isEmpty) return true;

    final haystack = [
      (studentData['name'] ?? '').toString(),
      (studentData['fName'] ?? '').toString(),
      (studentData['class'] ?? '').toString(),
      (studentData['section'] ?? '').toString(),
    ].join(' ').toLowerCase();

    final words = _searchQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);

    return words.every((word) => haystack.contains(word));
  }

  // These are the default fields — they are shown in this order first.
  // Any new custom field (added from set_fee_page) is automatically
  // listed after these.
  static const List<String> _defaultFieldOrder = [
    'monthlyFee',
    'admissionFee',
    'books',
    'notebooks',
    'diary',
    'file',
    'stationary',
    'paperMoney',
    'uniform',
    'other',
  ];

  // These keys exist in the fee_structures document but are not actual
  // fee amounts — never include them in the fee list/total.
  static const Set<String> _nonFeeKeys = {
    'studentId',
    'name',
    'fName',
    'class',
    'section',
    'updatedAt',
    'docId',
  };

  List<String> _orderedFeeFields(Map<String, dynamic> feeData) {
    List<String> known =
        _defaultFieldOrder.where((f) => feeData.containsKey(f)).toList();
    List<String> extra = feeData.keys
        .where(
            (f) => !_defaultFieldOrder.contains(f) && !_nonFeeKeys.contains(f))
        .toList()
      ..sort();
    return [...known, ...extra];
  }

  // Converts a camelCase field name into a readable label
  String _formatFieldLabel(String key) {
    if (key.isEmpty) return key;
    String spaced =
        key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: schoolCollection('students').snapshots(),
      builder: (context, studentSnapshot) {
        if (!studentSnapshot.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: const Text("Defaulter Students"),
              backgroundColor: Colors.redAccent,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

          var studentDocs = studentSnapshot.data!.docs;

          return StreamBuilder<QuerySnapshot>(
            stream: schoolCollection('fee_structures')
                .snapshots(),
            builder: (context, feeSnapshot) {
              if (!feeSnapshot.hasData) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text("Defaulter Students"),
                    backgroundColor: Colors.redAccent,
                  ),
                  body: const Center(child: CircularProgressIndicator()),
                );
              }

              // Convert fee structures into a Map so data is instantly available by ID
              Map<String, Map<String, dynamic>> feeMap = {};
              for (var feeDoc in feeSnapshot.data!.docs) {
                feeMap[feeDoc.id] = feeDoc.data() as Map<String, dynamic>;
              }

              List<Map<String, dynamic>> defaultersList = [];

              for (var studentDoc in studentDocs) {
                var studentData = studentDoc.data() as Map<String, dynamic>;
                var feeData = feeMap[studentDoc.id] ?? {};

                // Sum up whatever fields exist in the fee document (default
                // or custom) — no need for a hardcoded list
                double totalFeeStruct = 0;
                for (var entry in feeData.entries) {
                  if (_nonFeeKeys.contains(entry.key)) continue;
                  totalFeeStruct +=
                      double.tryParse(entry.value?.toString() ?? '0') ?? 0;
                }

                // Previous dues from student document
                double previousDues =
                    double.tryParse(studentData['dues']?.toString() ?? '0') ??
                        0;

                double grandTotal = totalFeeStruct + previousDues;

                // Only include those whose total dues are greater than 0
                if (grandTotal > 0) {
                  defaultersList.add({
                    'studentDoc': studentDoc,
                    'studentData': studentData,
                    'feeData': feeData,
                    'grandTotal': grandTotal,
                  });
                }
              }

              if (defaultersList.isEmpty) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text("Defaulter Students"),
                    backgroundColor: Colors.redAccent,
                  ),
                  body: const Center(
                    child: Text(
                      "No defaulters!",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }

              // Filter by whatever is typed in the search box.
              final filteredList = defaultersList
                  .where((d) => _matchesSearch(
                      d['studentData'] as Map<String, dynamic>))
                  .toList();

              return Scaffold(
                appBar: AppBar(
                  title: const Text("Defaulter Students"),
                  backgroundColor: Colors.redAccent,
                ),
                body: Column(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: "Search by name, father name or class...",
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filteredList.isEmpty
                          ? const Center(
                              child: Text("No matching defaulters found."))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: filteredList.length,
                              itemBuilder: (context, index) {
                                var defaulter = filteredList[index];
                                var studentData = defaulter['studentData'];
                                double grandTotal = defaulter['grandTotal'];

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  elevation: 3,
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Colors.red,
                                      child: Icon(Icons.warning,
                                          color: Colors.white),
                                    ),
                                    title: Text(
                                      studentData['name'] ?? 'N/A',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      "Father: ${studentData['fName'] ?? 'N/A'} | Class: ${studentData['class'] ?? 'N/A'}",
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "Rs. ${grandTotal.toStringAsFixed(0)}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: Icon(Icons.message,
                                              color: Colors.green[700]),
                                          tooltip: "WhatsApp Message",
                                          onPressed: () => _openWhatsApp(
                                              context,
                                              defaulter['studentDoc'].id,
                                              studentData,
                                              defaulter['feeData'],
                                              grandTotal),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      // Tapping opens the detail popup
                                      _showDefaulterDetailDialog(
                                          context, defaulter);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                // A real Scaffold floatingActionButton — Flutter positions
                // this correctly above the system nav bar / gesture area
                // automatically on every device, unlike a manually
                // Positioned widget inside the body which could end up
                // partly hidden behind the phone's bottom bar.
                floatingActionButton: filteredList.isEmpty
                    ? null
                    : FloatingActionButton.extended(
                        backgroundColor: Colors.green[700],
                        icon: const Icon(Icons.forward_to_inbox,
                            color: Colors.white),
                        label: Text(
                          "Message All (${filteredList.length})",
                          style: const TextStyle(color: Colors.white),
                        ),
                        onPressed: () =>
                            _showBulkMessageOptions(context, filteredList),
                      ),
              );
            },
          );
        },
      );
  }

  // Defaulter details popup/dialog that shows the breakdown of every field
  void _showDefaulterDetailDialog(
      BuildContext context, Map<String, dynamic> defaulter) {
    var studentData = defaulter['studentData'];
    var feeData = defaulter['feeData'];
    double grandTotal = defaulter['grandTotal'];
    double previousDues =
        double.tryParse(studentData['dues']?.toString() ?? '0') ?? 0;

    List<String> fields = _orderedFeeFields(feeData);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(studentData['name'] ?? 'Student Details'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Father Name: ${studentData['fName'] ?? 'N/A'}",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text("Class: ${studentData['class'] ?? 'N/A'}",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(thickness: 2),
                  const Text("Fee Breakdown:",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 5),
                  ...fields.map((f) {
                    var val = feeData[f]?.toString() ?? '0';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatFieldLabel(f),
                              style: const TextStyle(color: Colors.black54)),
                          Text("Rs. $val",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Previous Dues",
                          style: TextStyle(color: Colors.black54)),
                      Text("Rs. $previousDues",
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const Divider(thickness: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("GRAND TOTAL",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.red)),
                      Text("Rs. ${grandTotal.toStringAsFixed(0)}",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                              fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // WHATSAPP / SMS MESSAGING HELPERS
  // ============================================================

  /// Finds the phone number from the student's document
  /// (whichever field name is being used).
  String? _extractPhone(Map<String, dynamic> studentData) {
    const possibleKeys = [
      'contactNo',
      'phone',
      'phoneNumber',
      'contact',
      'contactNumber',
      'mobile',
      'whatsapp',
      'fatherPhone',
      'parentPhone',
    ];
    for (var key in possibleKeys) {
      final value = studentData[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return null;
  }

  /// Converts a local number (0300...) into WhatsApp's international
  /// format (923...).
  String _toWhatsAppFormat(String raw) {
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      digits = '92${digits.substring(1)}';
    } else if (!digits.startsWith('92')) {
      digits = '92$digits';
    }
    return digits;
  }

  String _buildMessage(Map<String, dynamic> studentData,
      Map<String, dynamic> feeData, double grandTotal) {
    final name = studentData['name'] ?? 'Student';
    final studentClass = studentData['class'] ?? '';

    double previousDues =
        double.tryParse(studentData['dues']?.toString() ?? '0') ?? 0;

    // Only fields whose value is greater than 0 (i.e. still pending)
    List<String> fields = _orderedFeeFields(feeData);
    StringBuffer details = StringBuffer();
    for (var field in fields) {
      double amount = double.tryParse(feeData[field]?.toString() ?? '0') ?? 0;
      if (amount <= 0) continue;
      details.writeln(
          "${_formatFieldLabel(field)}: Rs. ${amount.toStringAsFixed(0)}");
    }
    if (previousDues > 0) {
      details.writeln("Previous Dues: Rs. ${previousDues.toStringAsFixed(0)}");
    }

    return "Assalam o Alaikum!\n"
        "your child $name (Class: $studentClass) pending fee details:\n\n"
        "${details.toString()}\n"
        "Total: Rs. ${grandTotal.toStringAsFixed(0)}\n"
        "pay as soon as possible. Thank you - ${currentSchoolDisplayName()}";
  }

  /// Opens a WhatsApp chat for one defaulter (message pre-written)
  /// and also sends a push + in-app notification.
  Future<void> _openWhatsApp(
      BuildContext context,
      String studentId,
      Map<String, dynamic> studentData,
      Map<String, dynamic> feeData,
      double grandTotal) async {
    final phone = _extractPhone(studentData);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Phone number not found!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    final waNumber = _toWhatsAppFormat(phone);
    final message = _buildMessage(studentData, feeData, grandTotal);
    final uri = Uri.parse(
        "https://wa.me/$waNumber?text=${Uri.encodeComponent(message)}");

    // Fee reminder push + in-app notification (if this student's fcmToken
    // is known, a push notification is also sent; otherwise only in-app history is created).
    NotificationHelper.sendToUser(
      toId: studentId,
      toRole: 'student',
      title: 'Fee Reminder',
      body:
          'A fee payment of Rs. ${grandTotal.toStringAsFixed(0)} is pending. Please pay as soon as possible.',
      type: 'fee',
      fcmToken: studentData['fcmToken'] as String?,
    );

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("WhatsApp not open : $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Shows options when the "Message All" button is pressed.
  void _showBulkMessageOptions(
      BuildContext context, List<Map<String, dynamic>> defaultersList) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.sms, color: Colors.blue),
              title: Text("Send SMS to All (${defaultersList.length})"),
              subtitle: const Text("SMS compose in one click for defaulters"),
              onTap: () {
                Navigator.pop(context);
                _sendBulkSms(context, defaultersList);
              },
            ),
            ListTile(
              leading: const Icon(Icons.message, color: Colors.green),
              title: const Text("Send WhatsApp (one-by-one)"),
              subtitle: const Text(
                  "WhatsApp automatic bulk-send not support , so chat open one by one"),
              onTap: () {
                Navigator.pop(context);
                _startWhatsAppQueue(context, defaultersList);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the SMS compose screen for all defaulters' numbers at once.
  Future<void> _sendBulkSms(
      BuildContext context, List<Map<String, dynamic>> defaultersList) async {
    List<String> numbers = [];
    for (var d in defaultersList) {
      final phone = _extractPhone(d['studentData']);
      if (phone != null) numbers.add(phone);
    }

    if (numbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("No defaulter number found!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    final message = "Assalam o Alaikum! your child school fee is due. "
        "please deposit it as soon as possible. Thank you - ${currentSchoolDisplayName()}";

    final uri = Uri(
      scheme: 'sms',
      path: numbers.join(','),
      queryParameters: {'body': message},
    );

    try {
      await launchUrl(uri);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("SMS app not open : $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Flow that opens a WhatsApp chat one-by-one for each defaulter.
  void _startWhatsAppQueue(
      BuildContext context, List<Map<String, dynamic>> defaultersList) {
    int index = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          if (index >= defaultersList.length) {
            return AlertDialog(
              title: const Text("Done!"),
              content: const Text("All defaulter done."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Close"),
                ),
              ],
            );
          }

          final studentDoc = defaultersList[index]['studentDoc'];
          final studentData = defaultersList[index]['studentData'];
          final feeData = defaultersList[index]['feeData'];
          final grandTotal = defaultersList[index]['grandTotal'];
          final name = studentData['name'] ?? 'Student';

          return AlertDialog(
            title: Text("${index + 1} / ${defaultersList.length}"),
            content: Text("Send a WhatsApp message to '$name's parents.\n\n"
                "1) For 'Open WhatsApp' \n"
                "2) For Message send \n"
                "3) then go back from whatsapp and click 'Next' "),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Stop"),
              ),
              OutlinedButton(
                onPressed: () => _openWhatsApp(dialogContext, studentDoc.id,
                    studentData, feeData, grandTotal),
                child: const Text("Open WhatsApp"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () => setDialogState(() => index++),
                child:
                    const Text("Next", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}
