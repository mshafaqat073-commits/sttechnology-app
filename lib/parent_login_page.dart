import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'parent_dashboard.dart';
import 'school_context.dart';

class ParentLoginPage extends StatefulWidget {
  const ParentLoginPage({super.key});

  @override
  State<ParentLoginPage> createState() => _ParentLoginPageState();
}

class _ParentLoginPageState extends State<ParentLoginPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  /// Matches Login ID + PIN against Firestore (no OTP/SMS — free,
  /// unlimited). On a match, links all matching siblings to this
  /// (anonymous) account and navigates to the Parent Dashboard.
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
      // At login time we don't yet know which school this parent belongs
      // to, so we search the 'students' subcollections of ALL schools via
      // collectionGroup.
      var studentsSnapshot = await FirebaseFirestore.instance
          .collectionGroup('students')
          .where('parentLoginId', isEqualTo: loginId)
          .where('status', isEqualTo: 'active')
          .get();

      List<DocumentSnapshot> matchedChildren = studentsSnapshot.docs
          .where((doc) => (doc.data() as Map)['parentPin']?.toString() == pin)
          .toList();

      if (matchedChildren.isEmpty) {
        setState(() {
          _errorMessage = "Login ID or PIN is incorrect. Please check and try again.";
          _isLoading = false;
        });
        return;
      }

      // If this ID's children are (mistakenly) found across different
      // schools, we only keep the children from the FIRST school — so
      // two schools' data never mixes in this list.
      final firstSchoolId = schoolIdFromDoc(matchedChildren.first.reference);
      matchedChildren = matchedChildren
          .where((d) => schoolIdFromDoc(d.reference) == firstSchoolId)
          .toList();
      SchoolContext.set(firstSchoolId);
      await SchoolContext.loadBranding();

      // Anonymous account for the session (free, no SMS) — then link all
      // matched children (siblings) records to this account (for direct
      // lookup next time, see main.dart).
      final user = await _authService.signInAnonymouslyForLogin();
      var batch = FirebaseFirestore.instance.batch();
      for (var doc in matchedChildren) {
        batch.set(
            doc.reference,
            {
              'authUid': user.uid,
              'lastLoginAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
      await batch.commit();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (_) => ParentDashboard(children: matchedChildren)),
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
      backgroundColor: Colors.indigo[700],
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.family_restroom,
                    size: 70, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  "Parent Login",
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Enter the Login ID and PIN provided by the school office",
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
                          hintText: "P48213",
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
                              backgroundColor: Colors.indigo[700]),
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
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _pinController.dispose();
    super.dispose();
  }
}
