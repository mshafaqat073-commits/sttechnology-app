import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'school_context.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Lets the signed-in admin change their username (a Firestore
/// display/login field) and/or password (stored in Firebase Auth).
///
/// - Username is just a Firestore field used as a lookup key at login time
///   — changing it does NOT change the underlying Firebase Auth account
///   (see lib/admin_auth.dart).
/// - Password actually lives in Firebase Auth, so changing it requires
///   re-authenticating with the current password first (a Firebase
///   security requirement — calling updatePassword() directly fails if
///   the sign-in is not "recent").
Future<void> showUpdateCredentialsDialog(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.email == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("No active login session. Please log in again.")));
    return;
  }

  // Show a loading indicator immediately — the Firestore lookup below can
  // take a moment on a slow connection, and without this the button can
  // look like it isn't doing anything.
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  QueryDocumentSnapshot<Map<String, dynamic>>? userDoc;
  String lookupError = '';
  try {
    // Find our own Firestore doc via authUid — that's where the current
    // username lives, and where an updated username gets written.
    final querySnapshot = await schoolCollection("users")
        .where("authUid", isEqualTo: user.uid)
        .limit(1)
        .get();
    if (querySnapshot.docs.isNotEmpty) {
      userDoc = querySnapshot.docs.first;
    }
  } catch (e) {
    lookupError = e.toString();
  }

  if (!context.mounted) return;
  Navigator.pop(context); // close the loading dialog

  if (userDoc == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lookupError.isEmpty
            ? "Couldn't find your account record."
            : "Couldn't load your account: $lookupError")));
    return;
  }

  final userDocRef = userDoc.reference;
  final currentUsername = (userDoc.data()['username'] ?? '').toString();

  final userController = TextEditingController(text: currentUsername);
  final currentPassController = TextEditingController();
  final newPassController = TextEditingController();
  final confirmPassController = TextEditingController();
  bool isSaving = false;
  String? errorText;
  bool obscureCurrentPassword = true;
  bool obscureNewPassword = true;
  bool obscureConfirmPassword = true;

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text("Edit Login Info"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userController,
                decoration: const InputDecoration(labelText: "Username"),
              ),
              TextField(
                controller: currentPassController,
                obscureText: obscureCurrentPassword,
                decoration: InputDecoration(
                  labelText: "Current Password",
                  helperText: "Required to confirm this change",
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrentPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setDialogState(() =>
                        obscureCurrentPassword = !obscureCurrentPassword),
                  ),
                ),
              ),
              TextField(
                controller: newPassController,
                obscureText: obscureNewPassword,
                decoration: InputDecoration(
                  labelText: "New Password (leave blank to keep it)",
                  suffixIcon: IconButton(
                    icon: Icon(obscureNewPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setDialogState(
                        () => obscureNewPassword = !obscureNewPassword),
                  ),
                ),
              ),
              TextField(
                controller: confirmPassController,
                obscureText: obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: "Confirm New Password",
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirmPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setDialogState(() =>
                        obscureConfirmPassword = !obscureConfirmPassword),
                  ),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: isSaving
                ? null
                : () async {
                    final newUsername = userController.text.trim();
                    final currentPassword = currentPassController.text;
                    final newPassword = newPassController.text;
                    final confirmPassword = confirmPassController.text;

                    if (newUsername.isEmpty) {
                      setDialogState(
                          () => errorText = "Username cannot be empty.");
                      return;
                    }
                    if (currentPassword.isEmpty) {
                      setDialogState(
                          () => errorText = "Current password is required.");
                      return;
                    }
                    if (newPassword.isNotEmpty &&
                        newPassword != confirmPassword) {
                      setDialogState(() =>
                          errorText = "New password and confirmation do not match.");
                      return;
                    }

                    setDialogState(() {
                      isSaving = true;
                      errorText = null;
                    });

                    try {
                      // 1. Re-authenticate — Firebase requires this before
                      // sensitive account changes.
                      final cred = EmailAuthProvider.credential(
                        email: user.email!,
                        password: currentPassword,
                      );
                      await user.reauthenticateWithCredential(cred);

                      // 2. Username is just a Firestore field — update it
                      // directly.
                      if (newUsername != currentUsername) {
                        await userDocRef.update({"username": newUsername});
                      }

                      // 3. Password (if a new one was given) lives in
                      // Firebase Auth.
                      if (newPassword.isNotEmpty) {
                        await user.updatePassword(newPassword);
                      }

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(newPassword.isNotEmpty
                                ? "Password updated successfully!"
                                : "Updated!")));
                      }
                    } on FirebaseAuthException catch (e) {
                      String msg;
                      switch (e.code) {
                        case 'wrong-password':
                        case 'invalid-credential':
                          msg = "Current password is incorrect.";
                          break;
                        case 'weak-password':
                          msg = "New password must be at least 6 characters.";
                          break;
                        case 'requires-recent-login':
                          msg =
                              "Please log out and log back in, then try again.";
                          break;
                        case 'network-request-failed':
                          msg = "Network error — check your connection.";
                          break;
                        default:
                          msg = e.message ?? "Couldn't update your info.";
                      }
                      setDialogState(() {
                        isSaving = false;
                        errorText = msg;
                      });
                    } catch (e) {
                      setDialogState(() {
                        isSaving = false;
                        errorText = "Error: $e";
                      });
                    }
                  },
            child: isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Update"),
          ),
        ],
      ),
    ),
  );
}
