import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_context.dart';
import 'school_branding.dart';
import 'pdf_preview_helper.dart';

class StaffDirectoryReportPage extends StatelessWidget {
  const StaffDirectoryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Staff Directory"),
        backgroundColor: Colors.indigo,
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
        // Fetch the staff or teachers collection
        stream: schoolCollection('staff').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No staff member found.",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
              ),
            );
          }

          var docs = snapshot.data!.docs;

          return Column(
            children: [
              // Total Staff Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border.all(color: Colors.indigo.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total Staff Members:",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo),
                    ),
                    Text(
                      "${docs.length}",
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo),
                    ),
                  ],
                ),
              ),

              // Staff List
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String name = data['name'] ?? 'N/A';
                    String role = data['role'] ?? 'Teacher';
                    // Check the database field 'contact' (phone/contactNo also kept as a fallback)
                    String phone = data['contact'] ??
                        data['contactNo'] ??
                        data['phone'] ??
                        'N/A';
                    String email = (data['email'] as String?)?.trim() ?? '';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: Text(
                            "${index + 1}",
                            style: TextStyle(
                                color: Colors.indigo.shade800,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            email.isNotEmpty ? "Role: $role  •  $email" : "Role: $role"),
                        trailing: Text(
                          phone,
                          style: const TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                        onTap: () {
                          _showStaffDetails(context, data);
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

  // Staff Detail Dialog on Tap
  void _showStaffDetails(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(data['name'] ?? 'Staff Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Role: ${data['role'] ?? 'Teacher'}"),
            const SizedBox(height: 6),
            Text(
                "Contact: ${data['contact'] ?? data['contactNo'] ?? data['phone'] ?? 'N/A'}"),
            const SizedBox(height: 6),
            Text(
                "Email: ${(data['email'] as String?)?.trim().isNotEmpty == true ? data['email'] : 'Not provided'}"),
            const SizedBox(height: 6),
            Text(
                "Address: ${(data['address'] as String?)?.trim().isNotEmpty == true ? data['address'] : 'Not provided'}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // PDF Generation Function for Staff Directory
  Future<void> _generateAndPrintPdf(BuildContext context) async {
    final pdf = pw.Document();

    var snapshot = await schoolCollection('staff').get();

    if (snapshot.docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "No staff record available to generate PDF!")),
        );
      }
      return;
    }

    var docs = snapshot.docs;
    List<Map<String, dynamic>> pdfList = [];

    for (var doc in docs) {
      var data = doc.data();
      pdfList.add({
        'name': data['name'] ?? 'N/A',
        'role': data['role'] ?? 'Teacher',
        'contact':
            data['contact'] ?? data['contactNo'] ?? data['phone'] ?? 'N/A',
        'email': (data['email'] as String?)?.trim().isNotEmpty == true
            ? data['email']
            : '-',
        'address': (data['address'] as String?)?.trim().isNotEmpty == true
            ? data['address']
            : '-',
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
                  pw.Text("Staff Directory Report",
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text("Total Staff Members: ${pdfList.length}",
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: [
                'Sr.',
                'Staff Name',
                'Role',
                'Contact No',
                'Email',
                'Address'
              ],
              data: List.generate(pdfList.length, (index) {
                var item = pdfList[index];
                return [
                  "${index + 1}",
                  item['name'],
                  item['role'],
                  item['contact'],
                  item['email'],
                  item['address'],
                ];
              }),
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          ];
        },
      ),
    );

    // Print or preview the PDF
    await showPdfPreviewPage(
      context,
      title: "Staff Directory Report Preview",
      build: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
