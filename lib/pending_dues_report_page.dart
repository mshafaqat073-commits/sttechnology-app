import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class PendingDuesReportPage extends StatelessWidget {
  const PendingDuesReportPage({super.key});

  // Ye keys fee_structures document mein hoti hain lekin actual fee amount
  // nahi hain — inhe kabhi bhi fee list/total mein shamil nahi karna.
  static const Set<String> _nonFeeKeys = {
    'studentId',
    'name',
    'fName',
    'class',
    'section',
    'updatedAt',
    'docId',
  };

  // Ye default fields hain — inhi ki tarteeb pehle dikhai jayegi.
  // Koi bhi naya custom field (set_fee_page se add kiya gaya) automatically
  // inke baad list ho jayega.
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
        .where(
            (f) => !_defaultFieldOrder.contains(f) && !_nonFeeKeys.contains(f))
        .toList()
      ..sort();
    return [...known, ...extra];
  }

  // camelCase field name ko readable label me convert karta hai
  String _formatFieldLabel(String key) {
    if (key.isEmpty) return key;
    String spaced =
        key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  double _sumFeeData(Map<String, dynamic> feeData) {
    double total = 0;
    feeData.forEach((key, value) {
      if (_nonFeeKeys.contains(key)) return;
      total += double.tryParse(value?.toString() ?? '0') ?? 0;
    });
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pending Dues Report"),
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
        stream: schoolCollection('students')
            .where('status', isEqualTo: 'active')
            .snapshots(),
        builder: (context, studentSnapshot) {
          if (studentSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!studentSnapshot.hasData || studentSnapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No student found!"));
          }

          var studentDocs = studentSnapshot.data!.docs;

          return StreamBuilder<QuerySnapshot>(
            stream: schoolCollection('fee_structures')
                .snapshots(),
            builder: (context, feeSnapshot) {
              if (!feeSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              // Fee structures map for quick lookup
              Map<String, Map<String, dynamic>> feeMap = {};
              for (var feeDoc in feeSnapshot.data!.docs) {
                feeMap[feeDoc.id] = feeDoc.data() as Map<String, dynamic>;
              }

              List<Map<String, dynamic>> defaultersList = [];
              double totalPendingAmount = 0;

              for (var studentDoc in studentDocs) {
                var studentData = studentDoc.data() as Map<String, dynamic>;
                var feeData = feeMap[studentDoc.id] ?? {};

                // Current fee fields sum (default + koi bhi custom field)
                double totalFeeStruct = _sumFeeData(feeData);

                // Previous dues from student document
                double previousDues =
                    double.tryParse(studentData['dues']?.toString() ?? '0') ??
                        0;

                double grandTotal = totalFeeStruct + previousDues;

                if (grandTotal > 0) {
                  totalPendingAmount += grandTotal;
                  defaultersList.add({
                    'studentDoc': studentDoc,
                    'studentData': studentData,
                    'feeData': feeData,
                    'grandTotal': grandTotal,
                  });
                }
              }

              if (defaultersList.isEmpty) {
                return const Center(
                  child: Text(
                    "Great! No student has any dues remaining.",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green),
                  ),
                );
              }

              return Column(
                children: [
                  // Total Summary Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Total Pending Dues:",
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red),
                        ),
                        Text(
                          "Rs. ${totalPendingAmount.toStringAsFixed(0)}",
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),

                  // Defaulters List with Tap Details
                  Expanded(
                    child: ListView.builder(
                      itemCount: defaultersList.length,
                      itemBuilder: (context, index) {
                        var defaulter = defaultersList[index];
                        var studentData = defaulter['studentData'];
                        double grandTotal = defaulter['grandTotal'];

                        String name = studentData['name'] ?? 'N/A';
                        String fName = studentData['fName'] ?? 'N/A';
                        String className = studentData['class'] ?? 'N/A';
                        String sectionName =
                            (studentData['section'] ?? '').toString().trim();

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          elevation: 2,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.red.shade100,
                              child: Text(
                                "${index + 1}",
                                style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(sectionName.isNotEmpty
                                ? "Father: $fName | Class: $className - $sectionName"
                                : "Father: $fName | Class: $className"),
                            trailing: Text(
                              "Rs. ${grandTotal.toStringAsFixed(0)}",
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            onTap: () {
                              _showDefaulterDetailDialog(context, defaulter);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Detail Dialog on Card Tap
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
                  Text("Section: ${studentData['section'] ?? 'N/A'}",
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

  // PDF Generation Function
  // PDF Generation Function
  Future<void> _generateAndPrintPdf(BuildContext context) async {
    final pdf = pw.Document();

    // Fetch fresh data for PDF generation
    var studentSnapshot = await schoolCollection('students')
        .where('status', isEqualTo: 'active')
        .get();

    var feeSnapshot =
        await schoolCollection('fee_structures').get();

    Map<String, Map<String, dynamic>> feeMap = {};
    for (var feeDoc in feeSnapshot.docs) {
      feeMap[feeDoc.id] = feeDoc.data();
    }

    List<Map<String, dynamic>> pdfList = [];
    double grandTotalSum = 0;

    for (var studentDoc in studentSnapshot.docs) {
      var studentData = studentDoc.data();
      var feeData = feeMap[studentDoc.id] ?? {};

      double totalFeeStruct = _sumFeeData(feeData);

      double previousDues =
          double.tryParse(studentData['dues']?.toString() ?? '0') ?? 0;
      double grandTotal = totalFeeStruct + previousDues;

      if (grandTotal > 0) {
        grandTotalSum += grandTotal;
        pdfList.add({
          'name': studentData['name'] ?? 'N/A',
          'fName': studentData['fName'] ?? 'N/A',
          'class': studentData['class'] ?? 'N/A',
          'section': (studentData['section'] ?? '').toString().trim(),
          'total': grandTotal,
        });
      }
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
                  pw.Text("Pending Dues Report",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
                "Total Defaulters: ${pdfList.length} | Total Pending Amount: Rs. ${grandTotalSum.toStringAsFixed(0)}",
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
                'Pending Dues'
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
                  "Rs. ${item['total'].toStringAsFixed(0)}",
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

    // Print or preview the PDF using 'onLayout' instead of 'onData'
    await showPdfPreviewPage(
      context,
      title: "Pending Dues Report Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
