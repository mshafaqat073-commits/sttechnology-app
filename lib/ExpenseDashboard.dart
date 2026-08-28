import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'expense_page.dart';
import 'school_context.dart';
import 'pdf_preview_helper.dart';
import 'performance_bar_chart.dart';

class ExpenseDashboard extends StatelessWidget {
  const ExpenseDashboard({super.key});

  Future<void> _generateExpensePDF(BuildContext context) async {
    final snapshot =
        await schoolCollection('expenses').get();
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (pw.Context context) {
      return pw.Column(children: [
        pw.Text("Expense Report",
            style: pw.TextStyle(
                // <-- const yahan se hata diya
                fontSize: 25,
                fontWeight: pw.FontWeight.bold)),
        pw.Table.fromTextArray(
          headers: ["Name", "Description", "Paid", "Remaining"],
          data: snapshot.docs.map((doc) {
            var data = doc.data();
            return [
              data['name'] ?? '',
              data['description'] ?? '',
              data['paid'].toString(),
              data['remaining'].toString()
            ];
          }).toList(),
        ),
      ]);
    }));
    await showPdfPreviewPage(context, title: "Expense Report Preview", build: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Expense Dashboard"),
        backgroundColor: Colors.deepOrange,
        actions: [
          IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () => _generateExpensePDF(context)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: schoolCollection('expenses')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data!.docs;

          // Total Paid Amount Calculation
          double totalPaid = 0.0;
          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            var paidVal = data['paid'];
            totalPaid += (paidVal is String)
                ? double.tryParse(paidVal) ?? 0.0
                : (paidVal as num).toDouble();
          }

          return Column(
            children: [
              // Total Paid Header
              Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                color: Colors.deepOrange[50],
                child: Center(
                  child: Text(
                    "Total Paid: Rs. ${totalPaid.toStringAsFixed(2)}",
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange),
                  ),
                ),
              ),
              if (docs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                  child: PerformanceBarChart(
                    height: 140,
                    valueSuffix: '',
                    bars: docs.take(8).map((doc) {
                      var data = doc.data() as Map<String, dynamic>;
                      var paidVal = data['paid'];
                      double paid = (paidVal is String)
                          ? double.tryParse(paidVal) ?? 0.0
                          : (paidVal as num? ?? 0).toDouble();
                      return PerformanceBarData(
                        label: (data['name'] ?? 'N/A').toString(),
                        value: paid,
                        color: Colors.deepOrange,
                      );
                    }).toList(),
                  ),
                ),

              // Expenses List
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(data['name'] ?? 'No Name'),
                        subtitle: Text(
                            "Paid: ${data['paid']} | Rem: ${data['remaining']}"),
                        onLongPress: () => _showDialog(context, doc),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepOrange,
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (context) => const AddExpensePage())),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDialog(BuildContext context, DocumentSnapshot doc) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("Options"),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text("Update"),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  UpdateExpensePage(doc: doc)));
                    }),
                ListTile(
                    leading: const Icon(Icons.delete),
                    title: const Text("Delete"),
                    onTap: () {
                      doc.reference.delete();
                      Navigator.pop(context);
                    }),
              ]),
            ));
  }
}

// --- UPDATE CLASS ---
class UpdateExpensePage extends StatefulWidget {
  final DocumentSnapshot doc;
  const UpdateExpensePage({super.key, required this.doc});
  @override
  State<UpdateExpensePage> createState() => _UpdateExpensePageState();
}

class _UpdateExpensePageState extends State<UpdateExpensePage> {
  late TextEditingController _nameCtrl, _totalCtrl, _paidCtrl;
  @override
  void initState() {
    super.initState();
    var data = widget.doc.data() as Map<String, dynamic>;
    _nameCtrl = TextEditingController(text: data['name']);
    _totalCtrl = TextEditingController(text: data['total'].toString());
    _paidCtrl = TextEditingController(text: data['paid'].toString());
  }

  Future<void> _update() async {
    double total = double.tryParse(_totalCtrl.text) ?? 0;
    double paid = double.tryParse(_paidCtrl.text) ?? 0;
    await widget.doc.reference.update({
      'name': _nameCtrl.text,
      'total': total,
      'paid': paid,
      'remaining': total - paid
    });
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text("Update Expense")),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Name")),
            TextField(
                controller: _totalCtrl,
                decoration: const InputDecoration(labelText: "Total")),
            TextField(
                controller: _paidCtrl,
                decoration: const InputDecoration(labelText: "Paid")),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _update, child: const Text("Update"))
          ]),
        ));
  }
}
