import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class FeeCollectionReportPage extends StatefulWidget {
  const FeeCollectionReportPage({super.key});

  @override
  State<FeeCollectionReportPage> createState() =>
      _FeeCollectionReportPageState();
}

class _FeeCollectionReportPageState extends State<FeeCollectionReportPage> {
  // null = "All" (no filter applied). Month is only applied when the
  // year is also selected — this prevents selecting "just month"
  // (without year), which could have been ambiguous.
  int? _filterYear;
  int? _filterMonth;

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  // From the last 5 years to next year — to show in this dropdown.
  List<int> get _yearOptions {
    final currentYear = DateTime.now().year;
    return List.generate(7, (i) => currentYear + 1 - i);
  }

  bool _matchesFilter(Timestamp? ts) {
    if (_filterYear == null) return true; // "All" selected
    if (ts == null) return false;
    final d = ts.toDate();
    if (d.year != _filterYear) return false;
    if (_filterMonth != null && d.month != _filterMonth) return false;
    return true;
  }

  String get _filterLabel {
    if (_filterYear == null) return "All Time";
    if (_filterMonth == null) return "Year $_filterYear";
    return "${_monthNames[_filterMonth! - 1]} $_filterYear";
  }

  // These are the default fields — they are shown in this order first.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fee Collection Report"),
        backgroundColor: Colors.teal[800],
        actions: [
          // PDF Generate Button in AppBar
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Download/Print PDF",
            onPressed: () => _generateAndPrintPdf(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('fee_history')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // If the Firestore query fails (missing index,
          // permission-denied, etc.) the error is now shown clearly here —
          // previously it silently hid behind a "no records" message.
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Error loading fee history:\n${snapshot.error}",
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No fee collection record found yet.",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
              ),
            );
          }

          // Apply the Month/Year filter (both, or year only, or
          // "All Time" — see _matchesFilter).
          var docs = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return _matchesFilter(data['date'] as Timestamp?);
          }).toList();

          // Calculate the Total Collected Amount (on the filtered docs)
          double totalCollected = 0;
          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            totalCollected +=
                double.tryParse(data['amountPaid']?.toString() ?? '0') ?? 0;
          }

          return Column(
            children: [
              _buildFilterBar(),
              // Total Collection Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total Fee Collected:",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green),
                    ),
                    Text(
                      "Rs. ${totalCollected.toStringAsFixed(2)}",
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green),
                    ),
                  ],
                ),
              ),

              // Fee Records List
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Text(
                          "No fee collection record for $_filterLabel.",
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String studentName = data['name'] ?? 'Unknown Student';
                    String className = data['class'] ?? 'N/A';
                    String sectionName =
                        (data['section'] ?? '').toString().trim();
                    double amount = double.tryParse(
                            data['amountPaid']?.toString() ?? '0') ??
                        0;

                    String formattedDate = "N/A";
                    if (data['date'] != null) {
                      formattedDate = DateFormat('dd-MM-yyyy HH:mm')
                          .format((data['date'] as Timestamp).toDate());
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.shade100,
                          child:
                              Icon(Icons.check, color: Colors.green.shade800),
                        ),
                        title: Text(studentName,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          (sectionName.isNotEmpty
                                  ? "Class: $className - $sectionName | Date: $formattedDate"
                                  : "Class: $className | Date: $formattedDate") +
                              (data['source'] == 'online'
                                  ? "\nOnline (${data['paymentMethod'] ?? ''})"
                                  : ""),
                        ),
                        isThreeLine: data['source'] == 'online',
                        trailing: Text(
                          "+ Rs. ${amount.toStringAsFixed(0)}",
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text("Details: $studentName"),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          "Father Name: ${data['fName'] ?? 'N/A'}"),
                                      Text("Class: $className"),
                                      Text(
                                          "Section: ${sectionName.isNotEmpty ? sectionName : 'N/A'}"),
                                      Text(
                                          "Amount Paid: Rs. ${data['amountPaid'] ?? 0}"),
                                      Text(
                                          "Discount: Rs. ${data['discount'] ?? 0}"),
                                      Text(
                                          "Total at Payment: Rs. ${data['totalAtPayment'] ?? 0}"),
                                      if (data['source'] == 'online') ...[
                                        Text(
                                            "Payment Method: ${data['paymentMethod'] ?? 'N/A'}"),
                                        Text(
                                            "Transaction ID: ${data['transactionId'] ?? 'N/A'}"),
                                      ],
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
                                      if (data['restoredFees'] != null &&
                                          (data['restoredFees'] as Map)
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        const Divider(),
                                        const Text("Fee Breakdown:",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal)),
                                        const SizedBox(height: 4),
                                        ..._orderedFeeFields(
                                                Map<String, dynamic>.from(
                                                    data['restoredFees']))
                                            .map((f) {
                                          var val = Map<String, dynamic>.from(
                                              data['restoredFees'])[f];
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 2.0),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(_formatFieldLabel(f),
                                                    style: const TextStyle(
                                                        color: Colors.black54)),
                                                Text("Rs. $val",
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                      const SizedBox(height: 8),
                                      Text("Date: $formattedDate"),
                                    ],
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text("Close"),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Month/Year filter bar — Month is only enabled after Year is
  // selected (selecting only month without year would be ambiguous).
  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        border: Border.all(color: Colors.teal.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, color: Colors.teal, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: _filterYear,
                hint: const Text("Year: All"),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text("Year: All")),
                  ..._yearOptions.map((y) => DropdownMenuItem<int?>(
                      value: y, child: Text("Year: $y"))),
                ],
                onChanged: (val) {
                  setState(() {
                    _filterYear = val;
                    _filterMonth = null; // reset month as soon as year changes
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: _filterMonth,
                hint: const Text("Month: All"),
                // The month filter has no meaning without a year selected.
                onChanged: _filterYear == null
                    ? null
                    : (val) => setState(() => _filterMonth = val),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text("Month: All")),
                  ...List.generate(
                    12,
                    (i) => DropdownMenuItem<int?>(
                      value: i + 1,
                      child: Text(_monthNames[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // PDF Generation Function — generates the PDF only for the currently
  // filtered (visible on screen) records, so the PDF matches the same
  // month/year the user selected.
  Future<void> _generateAndPrintPdf(BuildContext context) async {
    final pdf = pw.Document();

    // Fetch fresh data for PDF generation from 'fee_history'
    var fullSnapshot = await schoolCollection('fee_history')
        .orderBy('date', descending: true)
        .get();

    var snapshotDocs = fullSnapshot.docs
        .where((doc) => _matchesFilter(doc.data()['date'] as Timestamp?))
        .toList();

    if (snapshotDocs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("No record available for PDF generate !")),
        );
      }
      return;
    }

    List<Map<String, dynamic>> pdfList = [];
    double totalCollectedSum = 0;

    for (var doc in snapshotDocs) {
      var data = doc.data();
      double amount =
          double.tryParse(data['amountPaid']?.toString() ?? '0') ?? 0;
      totalCollectedSum += amount;

      String formattedDate = "N/A";
      if (data['date'] != null) {
        formattedDate = DateFormat('dd-MM-yyyy')
            .format((data['date'] as Timestamp).toDate());
      }

      pdfList.add({
        'name': data['name'] ?? 'N/A',
        'fName': data['fName'] ?? 'N/A',
        'class': data['class'] ?? 'N/A',
        'section': (data['section'] ?? '').toString().trim(),
        'amount': amount,
        'date': formattedDate,
        'source': data['source'] == 'online'
            ? 'Online (${data['paymentMethod'] ?? ''})'
            : 'Cash',
      });
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(currentSchoolDisplayName(),
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Fee Collection Report ($_filterLabel)",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
                "Total Transactions: ${pdfList.length} | Total Collection: Rs. ${totalCollectedSum.toStringAsFixed(0)}",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: [
                'Sr.',
                'Student Name',
                'Father Name',
                'Class',
                'Section',
                'Amount',
                'Date',
                'Source',
              ],
              data: List.generate(pdfList.length, (index) {
                var item = pdfList[index];
                return [
                  "${index + 1}",
                  item['name'],
                  item['fName'],
                  item['class'],
                  (item['section'] as String).isNotEmpty
                      ? item['section']
                      : '-',
                  "Rs. ${item['amount'].toStringAsFixed(0)}",
                  item['date'],
                  item['source'],
                ];
              }),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
            ),
          ];
        },
      ),
    );

    // Show the PDF in an in-app preview screen
    await showPdfPreviewPage(
      context,
      title: "Fee Collection Report Preview ($_filterLabel)",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
