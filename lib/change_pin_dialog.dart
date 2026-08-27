import 'package:flutter/material.dart';

/// Shows a "Change PIN" dialog so a Parent or Teacher can set their own
/// new PIN from inside their own app, without asking the school office.
///
/// [currentPin] is the PIN currently on record — the user must enter it
/// correctly first (as a lightweight identity check) before a new PIN is
/// accepted. [onChangePin] is called with the new 4-digit PIN once every
/// check passes; implement it to write the new PIN to Firestore (for a
/// parent, update every sibling's record so everyone's login keeps
/// working with the same PIN).
Future<void> showChangePinDialog({
  required BuildContext context,
  required String currentPin,
  required Future<void> Function(String newPin) onChangePin,
}) async {
  final oldPinController = TextEditingController();
  final newPinController = TextEditingController();
  final confirmPinController = TextEditingController();

  await showDialog(
    context: context,
    builder: (ctx) {
      String? errorText;
      bool isSaving = false;

      return StatefulBuilder(builder: (ctx, setState) {
        Future<void> submit() async {
          final oldPin = oldPinController.text.trim();
          final newPin = newPinController.text.trim();
          final confirmPin = confirmPinController.text.trim();

          if (oldPin != currentPin) {
            setState(() => errorText = "Current PIN is incorrect.");
            return;
          }
          if (newPin.length != 4 || int.tryParse(newPin) == null) {
            setState(() => errorText = "New PIN must be exactly 4 digits.");
            return;
          }
          if (newPin != confirmPin) {
            setState(
                () => errorText = "New PIN and Confirm PIN do not match.");
            return;
          }
          if (newPin == oldPin) {
            setState(() =>
                errorText = "New PIN must be different from the current PIN.");
            return;
          }

          setState(() {
            isSaving = true;
            errorText = null;
          });

          try {
            await onChangePin(newPin);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("PIN changed successfully."),
                  backgroundColor: Colors.green));
            }
          } catch (e) {
            setState(() {
              isSaving = false;
              errorText = "Could not change PIN: $e";
            });
          }
        }

        return AlertDialog(
          title: const Text("Change PIN"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldPinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: "Current PIN",
                    counterText: "",
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newPinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: "New PIN (4 digits)",
                    counterText: "",
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmPinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  enabled: !isSaving,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!isSaving) submit();
                  },
                  decoration: const InputDecoration(
                    labelText: "Confirm New PIN",
                    counterText: "",
                    prefixIcon: Icon(Icons.check_circle_outline),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: isSaving ? null : submit,
              child: isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text("Save"),
            ),
          ],
        );
      });
    },
  );
}
