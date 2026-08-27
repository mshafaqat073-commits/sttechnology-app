import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

/// Parent ke liye read-only fee payment history — sirf usi bache ki
/// jitni bhi payments 'fee_history' collection mein save hain
/// (jo admin ki PayFeePage se _submitFee() ke waqt banti hain), date ke
/// sath latest-first order mein. Koi delete/edit option nahi — sirf
/// dekhne aur PDF receipt nikalne ke liye (history_page.dart admin
/// side ki tarah hi).
class ParentFeeHistoryPage extends StatelessWidget {
  final String studentId;
  final String studentName;

  const ParentFeeHistoryPage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  // Ye default fields hain — inhi ki tarteeb pehle dikhai jayegi.
  // Koi bhi naya custom field automatically inke baad list ho jayega.
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

  // camelCase field name ko readable label me convert karta hai
  String _formatFieldLabel(String key) {
    if (key.isEmpty) return key;
    String spaced =
        key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  // Detail dialog ke andar "Fee Breakdown" section banata hai. Naye
  // records mein har field ka Paid + Remaining dono dikhata hai (jaise
  // jaise partial payment hui waise hi). Purane records (jinke paas sirf
  // 'restoredFees' hai) ke liye sirf "Paid" dikhaya jata hai kyunke us
  // waqt fields hamesha poori pay hoti thin.
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
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
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
      double remaining = isNewSchema && remainingMap[f] is num
          ? (remainingMap[f] as num).toDouble()
          : 0.0;

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

    // Previous dues ki row bhi breakdown mein dikhayein (agar us waqt
    // kuch pay kiya gaya tha)
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

  // Record ki receipt PDF banata hai aur share/print karne ke liye khol
  // deta hai — bilkul history_page.dart (admin) ki tarah.
  Future<void> _generateReceiptPdf(
    BuildContext context, {
    required Map<String, dynamic> data,
    required String formattedDate,
  }) async {
    final pdf = pw.Document();
    double amountPaid = (data['amountPaid'] ?? 0).toDouble();
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
                pw.Text("Student: $studentName",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text("Father: ${data['fName'] ?? 'N/A'}"),
                pw.Text("Class: ${data['class'] ?? 'N/A'}"),
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
                            child: pw.Text("Rs. ${remainingMap['dues'] ?? 0}")),
                      ]),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(),
                _pdfRow("Amount Paid", "Rs. ${amountPaid.toStringAsFixed(0)}"),
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

    final output = await getTemporaryDirectory();
    final file = File(
        "${output.path}/receipt_${studentName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf");
    await file.writeAsBytes(await pdf.save());
    if (context.mounted) {
      await _showPdfActionSheet(context, file, "Receipt for $studentName");
    }
  }

  // Preview and Send both options in one place
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

  void _showDetails(
      BuildContext context, Map<String, dynamic> data, String formattedDate) {
    double paid = (data['amountPaid'] ?? 0).toDouble();
    double discount = (data['discount'] ?? 0).toDouble();
    double total = (data['totalAtPayment'] ?? 0).toDouble();
    double remaining = total - (paid + discount);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Payment Details"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Date: $formattedDate"),
                const SizedBox(height: 4),
                Text("Amount Paid: Rs. ${paid.toStringAsFixed(0)}"),
                Text("Discount: Rs. ${discount.toStringAsFixed(0)}"),
                Text("Total at Payment: Rs. ${total.toStringAsFixed(0)}"),
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    "Remaining Dues (at that time): Rs. ${remaining.toStringAsFixed(0)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ),
                ..._buildFeeBreakdownSection(data),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            label: const Text("Print / Share PDF"),
            onPressed: () => _generateReceiptPdf(
              context,
              data: data,
              formattedDate: formattedDate,
            ),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$studentName - Fee History"),
        backgroundColor: Colors.indigo[700],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('fee_history')
            .where('studentId', isEqualTo: studentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No payment record found."));
          }

          var docs = snapshot.data!.docs;
          // Latest payment sabse upar (client-side sort, taake
          // composite Firestore index ki zaroorat na pade).
          docs.sort((a, b) {
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
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              double paid = (data['amountPaid'] ?? 0).toDouble();

              String formattedDate = "N/A";
              if (data['date'] != null) {
                formattedDate = DateFormat('dd-MM-yyyy HH:mm')
                    .format((data['date'] as Timestamp).toDate());
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.teal),
                  title: Text("Rs. ${paid.toStringAsFixed(0)} Paid",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      "Date: $formattedDate${data['source'] == 'online' ? '  •  Online (${data['paymentMethod'] ?? ''})' : ''}"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDetails(context, data, formattedDate),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
