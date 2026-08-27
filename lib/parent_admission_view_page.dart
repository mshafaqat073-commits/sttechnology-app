import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_context.dart';

// Read-only view of the admission form data for one student, built from
// the exact fields saved by admission_page.dart's 'students' collection.
class ParentAdmissionViewPage extends StatelessWidget {
  final String studentId;
  final Map<String, dynamic> data;

  const ParentAdmissionViewPage(
      {super.key, required this.studentId, required this.data});

  // Ye keys fee_structures document mein hoti hain lekin actual fee amount
  // nahi hain — inhe kabhi bhi total mein shamil nahi karna.
  // (pay_fee_page.dart ki _nonFeeKeys ke sath match honi chahiye)
  static const Set<String> _nonFeeKeys = {
    'studentId',
    'name',
    'fName',
    'class',
    'section',
    'updatedAt',
    'docId',
  };

  // fee_structures doc ke saare fee fields jama karke + student ke
  // 'dues' field (pichli baqaya raqam) ko add karke asal current dues
  // nikalta he — bilkul waisi hi calculation jaisi PayFeePage admin
  // side par karta he, taake donon jagah number match ho.
  double _computeTotalDues(Map<String, dynamic>? feeData) {
    double previousDues = double.tryParse(data['dues']?.toString() ?? '0') ?? 0;

    if (feeData == null) return previousDues;

    double feeTotal = 0;
    for (var key in feeData.keys.where((f) => !_nonFeeKeys.contains(f))) {
      feeTotal += double.tryParse(feeData[key]?.toString() ?? '0') ?? 0;
    }

    return feeTotal + previousDues;
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black54)),
          ),
          Expanded(
            child: Text((value == null || value.trim().isEmpty) ? "N/A" : value,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = (data['imageUrl'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admission Form"),
        backgroundColor: Colors.indigo[700],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        // fee_structures live sunte hain taake current dues hamesha
        // sahi (aur admin ki PayFeePage jaisi hi) figure dikhaye —
        // sirf purani 'dues' field par depend nahi karte.
        stream: schoolCollection('fee_structures')
            .doc(studentId)
            .snapshots(),
        builder: (context, feeSnapshot) {
          Map<String, dynamic>? feeData;
          if (feeSnapshot.hasData && feeSnapshot.data!.exists) {
            feeData = feeSnapshot.data!.data() as Map<String, dynamic>;
          }
          final dues = _computeTotalDues(feeData);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.indigo.shade100,
                  backgroundImage:
                      imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                  child: imageUrl.isEmpty
                      ? const Icon(Icons.person, size: 40, color: Colors.indigo)
                      : null,
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Student Information",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.indigo)),
                        const Divider(),
                        _row("Form No.", data['formNo']?.toString()),
                        _row("Admission Date", data['date']?.toString()),
                        _row("Student Name", data['name']?.toString()),
                        _row("Date of Birth", data['dob']?.toString()),
                        _row("Age", data['age']?.toString()),
                        _row("Student CNIC / B-Form",
                            data['sCNIC']?.toString()),
                        _row("Gender", data['gender']?.toString()),
                        _row("Class", data['class']?.toString()),
                        _row("Section", data['section']?.toString()),
                        _row("Religion", data['religion']?.toString()),
                        _row("Previous School", data['preSchool']?.toString()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Family Information",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.indigo)),
                        const Divider(),
                        _row("Father Name", data['fName']?.toString()),
                        _row("Father CNIC", data['fCNIC']?.toString()),
                        _row("Contact No.", data['contactNo']?.toString()),
                        _row(
                            "Permanent Address", data['pAddress']?.toString()),
                        _row("District", data['district']?.toString()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Fee / Status",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.indigo)),
                        const Divider(),
                        _row("Admission Fee", data['addFee']?.toString()),
                        _row(
                            "Current Dues",
                            dues > 0
                                ? "Rs. ${dues.toStringAsFixed(0)}"
                                : "No Dues"),
                        _row("Status", data['status']?.toString()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
