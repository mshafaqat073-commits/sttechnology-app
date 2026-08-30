import 'package:flutter/material.dart';
import 'settings_page.dart'
    show kManagedCollections, kCollectionDisplayNames, resetSingleCollection;

// -----------------------------------------------------------------------
// Reset Data page — reached from Settings > Reset Data.
//
// Shows every category of data this app stores in the database (the same
// list used by Backup/Import, see kManagedCollections in
// settings_page.dart), with:
//   - a "Reset All Data" button at the top, for wiping everything at once
//   - one "Reset" action per category below it, for clearing just that
//     one category while leaving every other category untouched
//
// Both paths ultimately call resetSingleCollection() (settings_page.dart)
// per collection, so there is only one place that actually performs a
// delete — this page is just two different ways of driving it.
// -----------------------------------------------------------------------
class ResetDataPage extends StatefulWidget {
  const ResetDataPage({super.key});

  @override
  State<ResetDataPage> createState() => _ResetDataPageState();
}

class _ResetDataPageState extends State<ResetDataPage> {
  bool _resettingAll = false;
  final Set<String> _resettingOne = {};

  Future<void> _confirmAndResetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Reset All Data",
            style: TextStyle(color: Colors.red)),
        content: const Text(
          "Warning: this will permanently delete every category of data "
          "listed below. This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                const Text("Delete All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingAll = true);

    final progress = ValueNotifier<int>(0);
    final total = kManagedCollections.length;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, done, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 20),
                  Expanded(
                      child: Text("Resetting all data... ($done/$total)")),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      int done = 0;
      // Reset every category in parallel — same approach as the previous
      // single "Reset All Data" flow, so clearing one large collection
      // never blocks the rest from finishing.
      await Future.wait(kManagedCollections.map((coll) async {
        await resetSingleCollection(coll);
        done++;
        progress.value = done;
      }));
      navigator.pop(); // close progress dialog
      messenger.showSnackBar(
        const SnackBar(
            content: Text("All data reset successfully!"),
            backgroundColor: Colors.teal),
      );
    } catch (e) {
      navigator.pop(); // close progress dialog
      messenger.showSnackBar(
        SnackBar(content: Text("Reset failed: $e"), backgroundColor: Colors.red),
      );
    } finally {
      progress.dispose();
      if (mounted) setState(() => _resettingAll = false);
    }
  }

  Future<void> _confirmAndResetOne(String collection) async {
    final label = kCollectionDisplayNames[collection] ?? collection;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Reset $label", style: const TextStyle(color: Colors.red)),
        content: Text(
          "Warning: this will permanently delete all \"$label\" data only. "
          "Every other category stays untouched. This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingOne.add(collection));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await resetSingleCollection(collection);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
              content: Text("$label reset successfully!"),
              backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
              content: Text("Reset failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _resettingOne.remove(collection));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset Data")),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              "Reset everything at once with the button below, or reset "
              "just one category from the list. Every action here "
              "permanently deletes data and cannot be undone.",
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _resettingAll ? null : _confirmAndResetAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _resettingAll
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.warning_amber_rounded,
                        color: Colors.white),
                label: const Text(
                  "Reset All Data",
                  style:
                      TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "RESET ONE CATEGORY AT A TIME",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),
          ...kManagedCollections.map((coll) {
            final label = kCollectionDisplayNames[coll] ?? coll;
            final isResetting = _resettingOne.contains(coll);
            return ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: Text(label),
              trailing: isResetting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed:
                          _resettingAll ? null : () => _confirmAndResetOne(coll),
                      child: const Text("Reset",
                          style: TextStyle(color: Colors.red)),
                    ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
