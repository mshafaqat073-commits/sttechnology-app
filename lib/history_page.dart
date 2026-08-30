import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // null = "All" (no month filter). Otherwise the 1st of the selected
  // month/year — only records whose 'date' falls in that month are shown.
  DateTime? _selectedMonth;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: "Pick any date in the month to filter",
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
    }
  }

  // These are the default fields — they are shown in this order first.
  // Any new custom field is automatically listed after these.
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

  List<String> _orderedFeeFields(Map<String, dynamic> feeData) {
    List<String> known =
        _defaultFieldOrder.where((f) => feeData.containsKey(f)).toList();
    List<String> extra = feeData.keys
        .where((f) => !_defaultFieldOrder.contains(f))
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

  // Builds the "Fee Breakdown" section inside the detail dialog. For
  // new records, shows both Paid + Remaining for each field (matching
  // however the partial payment went). For old records (which only
  // have 'restoredFees'), only "Paid" is shown, since at that time
  // fields were always paid in full.
  List<Widget> _buildFeeBreakdownSection(Map<String, dynamic> data) {
    bool isNewSchema = data.containsKey('paidBreakdown');

    Map<String, dynamic> paidMap = isNewSchema
        ? Map<String, dynamic>.from(data['paidBreakdown'] ?? {})
        : Map<String, dynamic>.from(data['restoredFees'] ?? {});

    Map<String, dynamic> remainingMap = isNewSchema
        ? Map<String, dynamic>.from(data['remainingAfterPayment'] ?? {})
        : {};

    if (paidMap.isEmpty) return [];

    List<Widget> rows = [
      const SizedBox(height: 8),
      const Divider(),
      const Text("Fee Breakdown:",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
      const SizedBox(height: 4),
      if (isNewSchema)
        const Padding(
          padding: EdgeInsets.only(bottom: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  flex: 3,
                  child: Text("Field",
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text("Paid",
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text("Remaining",
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),
    ];

    for (var f in _orderedFeeFields(paidMap)) {
      var paidVal = paidMap[f];
      double paid = (paidVal is num) ? paidVal.toDouble() : 0.0;
      double remaining =
          isNewSchema && remainingMap[f] is num ? (remainingMap[f] as num).toDouble() : 0.0;

      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                flex: 3,
                child: Text(_formatFieldLabel(f),
                    style: const TextStyle(color: Colors.black54))),
            Expanded(
                flex: 2,
                child: Text("Rs. ${paid.toStringAsFixed(0)}",
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(
                flex: 2,
                child: Text(
                    isNewSchema ? "Rs. ${remaining.toStringAsFixed(0)}" : "-",
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: remaining > 0 ? Colors.red : Colors.grey))),
          ],
        ),
      ));
    }

    // Also show the Previous Dues row in the breakdown (if something
    // was paid toward it at that time)
    double duesPaid = (data['duesPaid'] ?? 0).toDouble();
    if (isNewSchema && duesPaid > 0) {
      double duesRemaining = (remainingMap['dues'] is num)
          ? (remainingMap['dues'] as num).toDouble()
          : 0.0;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
                flex: 3,
                child: Text("Previous Dues",
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold))),
            Expanded(
                flex: 2,
                child: Text("Rs. ${duesPaid.toStringAsFixed(0)}",
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(
                flex: 2,
                child: Text("Rs. ${duesRemaining.toStringAsFixed(0)}",
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: duesRemaining > 0 ? Colors.red : Colors.grey))),
          ],
        ),
      ));
    }

    return rows;
  }

  Future<void> _deleteRecord(
      BuildContext context, DocumentSnapshot doc, String collectionName) async {
    var data = doc.data() as Map<String, dynamic>;

    if (collectionName == 'fee_history') {
      String? studentId = data['studentId'];
      double amountPaid = (data['amountPaid'] ?? 0).toDouble();
      double discount = (data['discount'] ?? 0).toDouble();

      // New records have 'paidBreakdown' (how much was paid for each
      // field). Old records (from before this new system) only had
      // 'restoredFees' (from when every field was always paid in full)
      // — a fallback is kept to restore that old data too.
      bool isNewSchema = data.containsKey('paidBreakdown');
      Map<String, dynamic> paidBreakdown = isNewSchema
          ? Map<String, dynamic>.from(data['paidBreakdown'] ?? {})
          : Map<String, dynamic>.from(data['restoredFees'] ?? {});

      if (studentId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error: Student ID missing!")));
        return;
      }

      bool confirm = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Confirm Delete"),
          content: const Text(
              "Do you want to delete this record and add the fee back to its related fields?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel")),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Delete & Restore",
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        try {
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            DocumentReference feeRef = schoolCollection('fee_structures')
                .doc(studentId);
            DocumentReference studentRef = schoolCollection('students')
                .doc(studentId);

            DocumentSnapshot feeSnap = await transaction.get(feeRef);
            DocumentSnapshot studentSnap = await transaction.get(studentRef);

            double totalRestoredToStructure = 0;

            if (feeSnap.exists) {
              Map<String, dynamic> currentFeeData =
                  feeSnap.data() as Map<String, dynamic>;
              Map<String, dynamic> newFeeData =
                  Map<String, dynamic>.from(currentFeeData);

              paidBreakdown.forEach((key, value) {
                // Meta fields (studentId, name, class, etc.) aren't numbers
                // — skip them so toDouble() doesn't crash.
                if (value is! num) return;
                double historyVal = value.toDouble();
                if (historyVal > 0) {
                  var existing = currentFeeData[key];
                  double currentVal =
                      (existing is num) ? existing.toDouble() : 0.0;
                  newFeeData[key] = currentVal + historyVal;
                  totalRestoredToStructure += historyVal;
                }
              });

              transaction.update(feeRef, newFeeData);
            }

            if (studentSnap.exists) {
              double currentDues = (studentSnap.get('dues') ?? 0).toDouble();
              // Whatever 'discount' was given at the time of payment
              // must also be added back to dues — otherwise the discount
              // amount disappears entirely (neither in fee_structure,
              // nor in dues).
              double amountToDues;
              if (isNewSchema) {
                double duesPaid = (data['duesPaid'] ?? 0).toDouble();
                amountToDues = duesPaid + discount;
              } else {
                amountToDues =
                    (amountPaid + discount) - totalRestoredToStructure;
              }

              transaction
                  .update(studentRef, {'dues': currentDues + amountToDues});
            }

            transaction.delete(doc.reference);
          });

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    "Fee record deleted & amounts restored successfully!")));
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Transaction Failed: $e")));
          }
        }
      }
    } else {
      // For 'other_incomes' collection deletion confirmation
      bool confirm = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Confirm Delete"),
          content: const Text(
              "Do you want to delete this other-income record?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel")),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        try {
          await doc.reference.delete();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Other Income record deleted successfully!")));
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text("Deletion Failed: $e")));
          }
        }
      }
    }
  }

  // Generates a record's receipt PDF and opens it for sharing/printing
  Future<void> _generateReceiptPdf(
    BuildContext context, {
    required Map<String, dynamic> data,
    required bool isOtherIncome,
    required String name,
    required String className,
    required String formattedDate,
  }) async {
    final pdf = pw.Document();
    double amountPaid = (data['amountPaid'] ?? data['amount'] ?? 0).toDouble();

    if (!isOtherIncome) {
      double discount = (data['discount'] ?? 0).toDouble();
      double totalAtPayment = (data['totalAtPayment'] ?? 0).toDouble();
      double remaining = totalAtPayment - (amountPaid + discount);

      bool isNewSchema = data.containsKey('paidBreakdown');
      Map<String, dynamic> paidMap = isNewSchema
          ? Map<String, dynamic>.from(data['paidBreakdown'] ?? {})
          : Map<String, dynamic>.from(data['restoredFees'] ?? {});
      Map<String, dynamic> remainingMap = isNewSchema
          ? Map<String, dynamic>.from(data['remainingAfterPayment'] ?? {})
          : {};

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(currentSchoolDisplayName(),
                        style: pw.TextStyle(
                            fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Center(child: pw.Text("Fee Payment Receipt")),
                  pw.SizedBox(height: 12),
                  pw.Text("Student: $name",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("Father: ${data['fName'] ?? 'N/A'}"),
                  pw.Text("Class: $className"),
                  pw.Text("Date: $formattedDate"),
                  pw.SizedBox(height: 10),
                  pw.Text("Fee Breakdown:",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Table(
                    border: pw.TableBorder.all(),
                    children: [
                      pw.TableRow(children: [
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text("Field",
                                style:
                                    pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text("Paid",
                                style:
                                    pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text("Remaining",
                                style:
                                    pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      ]),
                      for (var f in _orderedFeeFields(paidMap))
                        pw.TableRow(children: [
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(_formatFieldLabel(f))),
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text("Rs. ${paidMap[f]}")),
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(isNewSchema
                                  ? "Rs. ${remainingMap[f] ?? 0}"
                                  : "-")),
                        ]),
                      if (isNewSchema && (data['duesPaid'] ?? 0) > 0)
                        pw.TableRow(children: [
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text("Previous Dues")),
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text("Rs. ${data['duesPaid']}")),
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child:
                                  pw.Text("Rs. ${remainingMap['dues'] ?? 0}")),
                        ]),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(),
                  _pdfRow(
                      "Amount Paid", "Rs. ${amountPaid.toStringAsFixed(0)}"),
                  _pdfRow("Discount", "Rs. ${discount.toStringAsFixed(0)}"),
                  _pdfRow("Total at Payment",
                      "Rs. ${totalAtPayment.toStringAsFixed(0)}"),
                  pw.Divider(thickness: 2),
                  _pdfRow("Remaining Dues (at that time)",
                      "Rs. ${remaining.toStringAsFixed(0)}",
                      bold: true),
                  pw.SizedBox(height: 20),
                  pw.Align(
                    alignment: pw.Alignment.bottomRight,
                    child: pw.Text("Signature: ________"),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } else {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(currentSchoolDisplayName(),
                        style: pw.TextStyle(
                            fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Center(child: pw.Text("Other Income Receipt")),
                  pw.SizedBox(height: 12),
                  pw.Text("Income Source: $name",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("Description: ${data['description'] ?? 'N/A'}"),
                  pw.Text("Date: $formattedDate"),
                  pw.SizedBox(height: 10),
                  pw.Divider(),
                  _pdfRow("Amount", "Rs. ${amountPaid.toStringAsFixed(0)}",
                      bold: true),
                ],
              ),
            );
          },
        ),
      );
    }

    final bytes = await pdf.save();
    final fileName =
        "receipt_${name.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf";

    if (!context.mounted) return;

    if (kIsWeb) {
      // Web doesn't support dart:io File / path_provider — pass the
      // bytes straight to the Printing package (which is web-compatible).
      await _showPdfActionSheetWeb(context, bytes, fileName);
    } else {
      final output = await getTemporaryDirectory();
      final file = File("${output.path}/$fileName");
      await file.writeAsBytes(bytes);
      if (context.mounted) {
        await _showPdfActionSheet(context, file, "Receipt for $name");
      }
    }
  }

  // Preview and Send both options in one place (mobile/desktop — uses
  // share_plus with a file path)
  Future<void> _showPdfActionSheet(
      BuildContext context, File file, String shareText) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text("Preview"),
              onTap: () async {
                Navigator.pop(context);
                await showPdfPreviewPage(
                  context,
                  title: shareText,
                  shareFileName: file.path.split(Platform.pathSeparator).last,
                  build: (format) async => file.readAsBytes(),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text("Send"),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await Share.shareXFiles([XFile(file.path)],
                      text: shareText);
                } catch (e) {
                  // On Windows (especially when not packaged as MSIX),
                  // share_plus's native "Share" sheet isn't available
                  // and this can fail — tell the user where the file
                  // was saved so they can attach it manually.
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          "Direct Send is not supported on this device. "
                          "File saved at:\n${file.path}"),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 6),
                    ));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Web version — doesn't use File/path_provider, previews and
  // downloads/shares straight from bytes (via the Printing package)
  Future<void> _showPdfActionSheetWeb(
      BuildContext context, Uint8List bytes, String fileName) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text("Preview"),
              onTap: () async {
                Navigator.pop(context);
                await Printing.layoutPdf(onLayout: (format) async => bytes);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text("Download / Share"),
              onTap: () async {
                Navigator.pop(context);
                await Printing.sharePdf(bytes: bytes, filename: fileName);
              },
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Income & Fee History"),
        backgroundColor: Colors.teal[800],
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            border: Border.all(color: Colors.teal.shade200),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _selectedMonth == null
                      ? "Showing: All records"
                      : "Filter: ${DateFormat('MMMM yyyy').format(_selectedMonth!)}",
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal),
                ),
              ),
              if (_selectedMonth != null)
                TextButton.icon(
                  onPressed: () => setState(() => _selectedMonth = null),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text("Clear"),
                ),
              ElevatedButton.icon(
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                icon: const Icon(Icons.calendar_month,
                    color: Colors.white, size: 18),
                label: const Text("Filter by Month",
                    style: TextStyle(color: Colors.white)),
                onPressed: _pickMonth,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText:
                  "Search by student name, father name, class, income source...",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.teal.shade200),
              ),
            ),
          ),
        ),
        Expanded(child: StreamBuilder<QuerySnapshot>(
        stream:
            schoolCollection('fee_history').snapshots(),
        builder: (context, feeSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: schoolCollection('other_incomes')
                .snapshots(),
            builder: (context, otherSnapshot) {
              if (feeSnapshot.connectionState == ConnectionState.waiting ||
                  otherSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              List<DocumentSnapshot> allDocs = [];

              if (feeSnapshot.hasData) {
                allDocs.addAll(feeSnapshot.data!.docs);
              }
              if (otherSnapshot.hasData) {
                allDocs.addAll(otherSnapshot.data!.docs);
              }

              if (allDocs.isEmpty) {
                return const Center(child: Text("No record found!"));
              }

              // Apply the selected month filter (if one was set)
              if (_selectedMonth != null) {
                allDocs = allDocs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  Timestamp? ts = data['date'] as Timestamp?;
                  if (ts == null) return false;
                  final d = ts.toDate();
                  return d.year == _selectedMonth!.year &&
                      d.month == _selectedMonth!.month;
                }).toList();
              }

              if (allDocs.isEmpty) {
                return const Center(
                    child: Text("No record found for this month!"));
              }

              // Filter using the search bar — show the record if the query
              // matches any of: student name, father name, class, income
              // source, or description.
              if (_searchQuery.trim().isNotEmpty) {
                final searchTerm = _searchQuery.trim().toLowerCase();
                allDocs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final fields = [
                    data['name'],
                    data['fName'],
                    data['class'],
                    data['incomeSource'],
                    data['description'],
                  ];
                  return fields.any((f) =>
                      f != null &&
                      f.toString().toLowerCase().contains(searchTerm));
                }).toList();
              }

              if (allDocs.isEmpty) {
                return const Center(
                    child: Text("No record matches your search."));
              }

              // Sort combined documents by 'date' field descending (latest first)
              allDocs.sort((a, b) {
                var dataA = a.data() as Map<String, dynamic>;
                var dataB = b.data() as Map<String, dynamic>;
                Timestamp? timeA = dataA['date'] as Timestamp?;
                Timestamp? timeB = dataB['date'] as Timestamp?;
                if (timeA == null && timeB == null) return 0;
                if (timeA == null) return 1;
                if (timeB == null) return -1;
                return timeB.compareTo(timeA);
              });

              return ListView.builder(
                itemCount: allDocs.length,
                itemBuilder: (context, index) {
                  var doc = allDocs[index];
                  var data = doc.data() as Map<String, dynamic>;

                  // Check which collection this record belongs to
                  bool isOtherIncome =
                      doc.reference.path.contains('other_incomes');

                  // If it's other income, show the 'incomeSource' field, otherwise the student's 'name'
                  String name = isOtherIncome
                      ? (data['incomeSource'] ?? 'Other Income')
                      : (data['name'] ?? 'Unknown');

                  String className =
                      data['class'] ?? (isOtherIncome ? 'Other Source' : 'N/A');

                  // To fetch the amount (other_incomes has 'amountPaid')
                  double amount =
                      (data['amountPaid'] ?? data['amount'] ?? 0).toDouble();

                  String formattedDate = "N/A";
                  if (data['date'] != null) {
                    formattedDate = DateFormat('dd-MM-yyyy HH:mm')
                        .format((data['date'] as Timestamp).toDate());
                  }

                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: Icon(
                        isOtherIncome
                            ? Icons.account_balance_wallet
                            : Icons.receipt_long,
                        color: isOtherIncome
                            ? Colors.orange[800]
                            : Colors.teal[800],
                      ),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          "Type: ${isOtherIncome ? 'Other Income' : (data['source'] == 'online' ? 'Fee Collection (Online - ${data['paymentMethod'] ?? ''})' : 'Fee Collection')}\nClass: $className\nDate: $formattedDate"),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Rs. ${amount.toStringAsFixed(0)}",
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          IconButton(
                            tooltip: "Delete record",
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _deleteRecord(context, doc,
                                isOtherIncome ? 'other_incomes' : 'fee_history'),
                          ),
                        ],
                      ),
                      onLongPress: () => _deleteRecord(context, doc,
                          isOtherIncome ? 'other_incomes' : 'fee_history'),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text("Details: $name"),
                            content: SizedBox(
                              width: double.maxFinite,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isOtherIncome) ...[
                                      Text(
                                          "Father Name: ${data['fName'] ?? 'N/A'}"),
                                      Text(
                                          "Amount Paid: Rs. ${data['amountPaid'] ?? 0}"),
                                      Text(
                                          "Discount: Rs. ${data['discount'] ?? 0}"),
                                      Text(
                                          "Total at Payment: Rs. ${data['totalAtPayment'] ?? 0}"),
                                      Builder(builder: (_) {
                                        double paid = (data['amountPaid'] ?? 0)
                                            .toDouble();
                                        double discount =
                                            (data['discount'] ?? 0).toDouble();
                                        double total =
                                            (data['totalAtPayment'] ?? 0)
                                                .toDouble();
                                        double remaining =
                                            total - (paid + discount);
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4.0),
                                          child: Text(
                                            "Remaining Dues: Rs. ${remaining.toStringAsFixed(0)}",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red),
                                          ),
                                        );
                                      }),
                                      ..._buildFeeBreakdownSection(data),
                                    ] else ...[
                                      Text(
                                          "Income Source: ${data['incomeSource'] ?? 'N/A'}"),
                                      Text(
                                          "Amount Paid: Rs. ${data['amountPaid'] ?? 0}"),
                                      Text(
                                          "Description: ${data['description'] ?? 'N/A'}"),
                                    ],
                                    const SizedBox(height: 8),
                                    Text("Date: $formattedDate"),
                                  ],
                                ),
                              ),
                            ),
                            actions: [
                              TextButton.icon(
                                icon: const Icon(Icons.picture_as_pdf,
                                    color: Colors.red),
                                label: const Text("Print / Share PDF"),
                                onPressed: () => _generateReceiptPdf(
                                  context,
                                  data: data,
                                  isOtherIncome: isOtherIncome,
                                  name: name,
                                  className: className,
                                  formattedDate: formattedDate,
                                ),
                              ),
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text("Close"))
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      )),
      ]),
    );
  }
}
