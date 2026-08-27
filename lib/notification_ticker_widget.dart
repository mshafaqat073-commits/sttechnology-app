import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'school_context.dart';

/// ============================================================
/// NOTIFICATION TICKER (news ki tarah scrolling bar)
/// ============================================================
///
/// USAGE (apni Dashboard page mein):
///
///   final List<String> _notifications = [];
///
///   Column(
///     children: [
///       NotificationTickerBar(notifications: _notifications),
///       ElevatedButton.icon(
///         onPressed: () async {
///           final result = await showAddNotificationDialog(context);
///           if (result != null && result.trim().isNotEmpty) {
///             setState(() => _notifications.add(result.trim()));
///           }
///         },
///         icon: const Icon(Icons.campaign),
///         label: const Text("Add Notification"),
///       ),
///       ... rest of dashboard ...
///     ],
///   )
///
/// ============================================================

/// Scrolling ticker bar — top par news ki tarah chalti rahegi
class NotificationTickerBar extends StatefulWidget {
  final List<String> notifications;
  final Color backgroundColor;
  final Color textColor;
  final double height;
  final Duration speed; // kitni fast/slow scroll ho

  const NotificationTickerBar({
    super.key,
    required this.notifications,
    this.backgroundColor = const Color(0xFF00695C), // teal 800
    this.textColor = Colors.white,
    this.height = 40,
    this.speed = const Duration(milliseconds: 30),
  });

  @override
  State<NotificationTickerBar> createState() => _NotificationTickerBarState();
}

class _NotificationTickerBarState extends State<NotificationTickerBar> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  double _scrollPos = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() {
    if (widget.notifications.isEmpty || !_scrollController.hasClients) return;

    _timer?.cancel();
    _timer = Timer.periodic(widget.speed, (timer) {
      if (!_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollPos += 1.5;

      if (_scrollPos >= maxScroll) {
        _scrollPos = 0;
      }

      _scrollController.jumpTo(_scrollPos);
    });
  }

  @override
  void didUpdateWidget(covariant NotificationTickerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Agar notifications list change ho to scroll dubara start karo
    if (oldWidget.notifications != widget.notifications) {
      _scrollPos = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.notifications.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sab notifications ko ek single line mein jod dete hain (separator ke sath)
    final combinedText = widget.notifications.join("      •      ");

    return Container(
      height: widget.height,
      color: widget.backgroundColor,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            height: widget.height,
            color: Colors.black26,
            child: Row(
              children: [
                Icon(Icons.campaign, color: widget.textColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  "NOTICE",
                  style: TextStyle(
                    color: widget.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    // Text ko repeat karte hain taake loop seamless lage
                    "$combinedText      •      $combinedText",
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add/Edit Notification" dialog
Future<String?> showAddNotificationDialog(
  BuildContext context, {
  String initialText = '',
  String title = 'New Notification',
  String confirmLabel = 'Add',
}) {
  final controller = TextEditingController(text: initialText);

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: 3,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: "e.g. Tomorrow's paper submission deadline is 5 PM",
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// ============================================================
/// MANAGE NOTIFICATIONS PAGE
/// ============================================================
/// Notification button dabane pr ye page khulti hai — sab
/// existing notifications list mein dikhti hain, har ek ko
/// edit (pencil) ya delete (trash) kiya ja sakta hai, aur "+"
/// button se naya notification add kiya ja sakta hai.
class ManageNotificationsPage extends StatelessWidget {
  const ManageNotificationsPage({super.key});

  CollectionReference get _collection =>
      schoolCollection('notifications');

  Future<void> _addNotification(BuildContext context) async {
    final text = await showAddNotificationDialog(context);
    if (text != null && text.trim().isNotEmpty) {
      await _collection.add({
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _editNotification(
      BuildContext context, String id, String currentText) async {
    final text = await showAddNotificationDialog(
      context,
      initialText: currentText,
      title: "Edit Notification",
      confirmLabel: "Update",
    );
    if (text != null && text.trim().isNotEmpty) {
      await _collection.doc(id).update({'text': text.trim()});
    }
  }

  Future<void> _deleteNotification(BuildContext context, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Notification?"),
        content:
            const Text("This will remove it from the scrolling ticker."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _collection.doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Notifications"),
        backgroundColor: Colors.teal[800],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _collection.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No notifications yet.\nTap + to add one.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final text =
                  (doc.data() as Map<String, dynamic>)['text'] as String? ??
                      '';
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: const Icon(Icons.campaign, color: Colors.teal),
                  title: Text(text),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blueGrey),
                        onPressed: () =>
                            _editNotification(context, doc.id, text),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            _deleteNotification(context, doc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal[800],
        onPressed: () => _addNotification(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
