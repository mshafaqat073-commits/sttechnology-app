import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'teacher_dashboard.dart';
import 'school_context.dart';

class TeacherLoginPage extends StatefulWidget {
  const TeacherLoginPage({super.key});

  @override
  State<TeacherLoginPage> createState() => _TeacherLoginPageState();
}

class _TeacherLoginPageState extends State<TeacherLoginPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  /// Matches Login ID + PIN against Firestore (no OTP/SMS — free,
  /// unlimited). On a match, links the staff record and navigates to the
  /// Teacher Dashboard.
  Future<void> _login() async {
    String loginId = _idController.text.trim();
    String pin = _pinController.text.trim();

    if (loginId.isEmpty || pin.isEmpty) {
      setState(() => _errorMessage = "Please enter both Login ID and PIN.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // At login time we don't yet know which school this teacher belongs
      // to, so we search the 'staff' subcollections of ALL schools via
      // collectionGroup.
      var staffSnapshot = await FirebaseFirestore.instance
          .collectionGroup('staff')
          .where('staffLoginId', isEqualTo: loginId)
          .limit(1)
          .get();

      DocumentSnapshot? matchedDoc;
      if (staffSnapshot.docs.isNotEmpty) {
        final doc = staffSnapshot.docs.first;
        final data = doc.data();
        if (data['staffPin']?.toString() == pin) {
          matchedDoc = doc;
        }
      }

      if (matchedDoc == null) {
        setState(() {
          _errorMessage =
              "Login ID or PIN is incorrect. Please check and try again.";
          _isLoading = false;
        });
        return;
      }

      // Find out which school this doc belongs to, and set it as the
      // active school for the whole app.
      SchoolContext.set(schoolIdFromDoc(matchedDoc.reference));
      await SchoolContext.loadBranding();

      // Anonymous account for the session (free, no SMS) — link the staff
      // record to this account (for direct lookup next time).
      final user = await _authService.signInAnonymouslyForLogin();
      await matchedDoc.reference.set(
        {
          'authUid': user.uid,
          'lastLoginAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => TeacherDashboard(
            staffDocId: matchedDoc!.id,
            staffData: matchedDoc.data() as Map<String, dynamic>,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      setState(() {
        _errorMessage = "Login error: $e";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal[800],
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.school, size: 70, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  "Teacher Login",
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Enter the Login ID and PIN provided by the admin",
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _idController,
                        enabled: !_isLoading,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: "Login ID",
                          hintText: "T77291",
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        enabled: !_isLoading,
                        // Autofill/suggestions turned off — on some
                        // Android phones a wrong app's shortcut appears in
                        // the keyboard suggestion strip above the field
                        // and opens on tap.
                        autofillHints: null,
                        enableSuggestions: false,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_isLoading) _login();
                        },
                        decoration: const InputDecoration(
                          labelText: "PIN",
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal[800]),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Text("LOGIN",
                                  style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _pinController.dispose();
    super.dispose();
  }
}
