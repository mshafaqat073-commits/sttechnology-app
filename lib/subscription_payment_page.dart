import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'school_context.dart';

/// Developer's own Easypaisa/UBL account (subscription renewal payments
/// land here) — hardcoded because this is the developer's account, not a
/// per-school setting. Kept as one place (instead of duplicated inside
/// settings_page.dart) so it only has to be updated in one spot if the
/// developer ever changes accounts.
const String kDevEasypaisaNumber = "0300-6585073";
const String kDevEasypaisaName = "Muhammad Shafaqat Ali Zafar";
const String kDevUblIban = "PK33 UNIL 0109 0003 2622 4775";
const String kDevUblName = "Muhammad Shafaqat Ali Zafar";

/// Top-level Firestore collection (sits next to `schools`, not inside any
/// one school) — this is what the Super Admin panel reads to show the
/// "Pending Payment Requests" queue.
///
/// Document shape:
///   schoolId        -> which school this request belongs to
///   schoolName       -> denormalized, for display in Super Admin list
///   method            -> 'easypaisa' | 'ubl'
///   note              -> optional transaction ID / reference the user typed
///   screenshotUrl     -> Cloudinary secure URL of the payment screenshot
///   status            -> 'pending' | 'approved' | 'rejected'
///   requestedAt       -> server timestamp, when the user submitted it
///   reviewedAt        -> server timestamp, when the developer acted on it
///   reviewedDays      -> days granted (only set when approved)
const String kSubscriptionRequestsCollection = 'subscriptionPaymentRequests';

/// Roadmap: "Pay to Renew Subscription" — user sends payment to the
/// developer's Easypaisa/UBL account, then submits a screenshot here.
/// That creates a `pending` request; the Super Admin panel is the only
/// place that can move it to `approved` (which also extends the
/// subscription) or `rejected`.
class SubscriptionPaymentPage extends StatefulWidget {
  const SubscriptionPaymentPage({super.key});

  @override
  State<SubscriptionPaymentPage> createState() =>
      _SubscriptionPaymentPageState();
}

class _SubscriptionPaymentPageState extends State<SubscriptionPaymentPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _noteController = TextEditingController();
  XFile? _picked;
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("$label copied")));
  }

  Widget _devAccountRow(IconData icon, Color color, String title,
      String number, String accountName) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text("$number\n$accountName"),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 20),
        tooltip: "Copy",
        onPressed: () => _copy(number, title),
      ),
    );
  }

  Future<void> _pickScreenshot() async {
    final XFile? picked = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text("Take Photo"),
              onTap: () async {
                final f = await _picker.pickImage(source: ImageSource.camera);
                if (ctx.mounted) Navigator.pop(ctx, f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Choose Screenshot from Gallery"),
              onTap: () async {
                final f =
                    await _picker.pickImage(source: ImageSource.gallery);
                if (ctx.mounted) Navigator.pop(ctx, f);
              },
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _picked = picked);
  }

  Future<void> _submit() async {
    final XFile? picked = _picked;
    if (picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please attach your payment screenshot first.")));
      return;
    }

    setState(() => _submitting = true);
    try {
      final cloudinary = CloudinaryPublic('niilo9ek', 'shafi073', cache: false);
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          picked.path,
          resourceType: CloudinaryResourceType.Image,
          folder: 'subscription_payments/${SchoolContext.schoolId}',
        ),
      );

      await FirebaseFirestore.instance
          .collection(kSubscriptionRequestsCollection)
          .add({
        'schoolId': SchoolContext.schoolId,
        'schoolName': SchoolContext.schoolName ?? SchoolContext.schoolId,
        'note': _noteController.text.trim(),
        'screenshotUrl': response.secureUrl,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _picked = null;
        _noteController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            "Screenshot sent to the developer. You'll be upgraded once it's approved."),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Upload failed: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _statusChip(String status) {
    late Color color;
    late String label;
    switch (status) {
      case 'approved':
        color = Colors.green;
        label = "Approved";
        break;
      case 'rejected':
        color = Colors.red;
        label = "Rejected";
        break;
      default:
        color = Colors.orange;
        label = "Pending review";
    }
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pay to Renew Subscription")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "1. Send payment to the developer's account",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _devAccountRow(Icons.phone_android, Colors.green, "Easypaisa",
                    kDevEasypaisaNumber, kDevEasypaisaName),
                const Divider(height: 1),
                _devAccountRow(Icons.account_balance, Colors.indigo,
                    "UBL Bank", kDevUblIban, kDevUblName),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "2. Attach your payment screenshot",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (_picked != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? Image.network(_picked!.path, height: 180, fit: BoxFit.cover)
                  : Image.file(File(_picked!.path), height: 180, fit: BoxFit.cover),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _pickScreenshot,
            icon: const Icon(Icons.attach_file),
            label: Text(_picked == null
                ? "Choose Screenshot"
                : "Change Screenshot"),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: "Reference / Transaction ID (optional)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text(_submitting ? "Sending..." : "Send to Developer"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            "Your Requests",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(kSubscriptionRequestsCollection)
                .where('schoolId', isEqualTo: SchoolContext.schoolId)
                .orderBy('requestedAt', descending: true)
                .limit(5)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Couldn't load your requests.",
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${snap.error}",
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Text("No requests submitted yet.",
                    style: TextStyle(color: Colors.black54));
              }
              return Column(
                children: docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final status = (data['status'] as String?) ?? 'pending';
                  final ts = data['requestedAt'];
                  final date = ts is Timestamp
                      ? DateFormat('d MMM, yyyy – h:mm a').format(ts.toDate())
                      : '';
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(date),
                      subtitle: (data['note'] as String?)?.isNotEmpty == true
                          ? Text("Ref: ${data['note']}")
                          : null,
                      trailing: _statusChip(status),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
