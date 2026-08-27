import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'school_context.dart';
import 'school_branding.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _isLoading = false;
  bool _isObscure = true; // Password hide/show ke liye

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Custom back arrow (role selector par wapas) — dark gradient
      // background par default black back-arrow ki jagah ab white aur
      // hamesha nazar aane wala.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF004D40), Color(0xFF00695C), Color(0xFF00897B)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo badge
                  Container(
                    height: 100,
                    width: 100,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child:
                        const ClipOval(child: SchoolLogo(fit: BoxFit.contain)),
                  ),
                  const SizedBox(height: 16),
                  const SchoolNameText(
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Admin Login",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Login card
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Username Field
                        TextField(
                          controller: _userController,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            labelText: "Username",
                            prefixIcon: const Icon(Icons.person_outline),
                            filled: true,
                            fillColor: Colors.grey[100],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field with Eye Icon
                        TextField(
                          controller: _passController,
                          obscureText: _isObscure,
                          enabled: !_isLoading,
                          onSubmitted: (_) {
                            if (!_isLoading) _login();
                          },
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            filled: true,
                            fillColor: Colors.grey[100],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(_isObscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _isObscure = !_isObscure),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Login Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFF00695C)))
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal[800],
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 3,
                                  ),
                                  onPressed: _login,
                                  child: const Text(
                                    "Login",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                        ),

                        // Forgot Password Button
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text("Contact Admin for Password Reset")),
                            );
                          },
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(color: Colors.teal[800]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    final typedUsername = _userController.text.trim();
    final typedPassword = _passController.text;

    if (typedUsername.isEmpty || typedPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter both fields!")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Login ke waqt abhi tak pata nahi ke ye admin kis school ka hai,
      // is liye collectionGroup se SAARI schools ke 'users' subcollections
      // mein sirf USERNAME se dhoondte hain (password Firestore mein ab
      // store hi nahi hota — asal check niche Firebase Auth karta hai).
      //
      // "users" collection publicly readable hai (dekhein firestore.rules)
      // kyunke isme ab koi secret nahi — sirf username aur ek internal
      // (fake, kabhi khud password ka kaam na karne wali) authEmail hoti
      // hai.
      //
      // NOTE: Ye query apna alag try/catch rakhti hai taake network issue
      // (no internet / timeout) ko "Invalid Username or Password" na keh
      // dein — ye do bilkul alag cheezein hain aur user ko sahi wajah pata
      // chalni chahiye.
      QuerySnapshot<Map<String, dynamic>> querySnapshot;
      try {
        querySnapshot = await FirebaseFirestore.instance
            .collectionGroup("users")
            .where("username", isEqualTo: typedUsername)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 15));
      } on TimeoutException {
        _showError(
            "Network is too slow or unavailable. Please check your internet connection and try again.");
        return;
      } on FirebaseException catch (e) {
        if (e.code == 'unavailable') {
          _showError(
              "No internet connection. Please check your network and try again.");
        } else {
          _showError(
              "Network error: ${e.message ?? e.code}. Please try again.");
        }
        return;
      }

      if (querySnapshot.docs.isEmpty) {
        _showError("Invalid Username or Password!");
        return;
      }

      final userDoc = querySnapshot.docs.first;
      final authEmail = userDoc.data()['authEmail'] as String?;
      if (authEmail == null || authEmail.isEmpty) {
        // Purana record hai jo abhi Firebase Auth par migrate nahi hua
        // (migrate_admin_to_auth.js chalana baaqi hai).
        _showError(
            "This account has not been updated yet. Please contact the Developer/Admin.");
        return;
      }

      // 2. Asal password check yahan Firebase Auth khud (securely, server
      // side) karta hai — Firestore mein kahin bhi plaintext password
      // nahi jaata.
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: authEmail,
        password: typedPassword,
      );

      // 3. Ye doc kis school ke andar hai, wo maloom kar ke poori app ke
      // liye active school set kar dete hain.
      SchoolContext.set(schoolIdFromDoc(userDoc.reference));
      // School ka naam/logo (Settings > School Name/Logo se) cache kar
      // lete hain taake Dashboard aur PDFs turant sahi branding dikhayein.
      await SchoolContext.loadBranding();

      final prefs = await SharedPreferences.getInstance();
      // Sirf username save karte hain (convenience/prefill ke liye) —
      // password ab kahin bhi (Firestore ya SharedPreferences) plaintext
      // store nahi hota.
      await prefs.setString('saved_username', typedUsername);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    } on FirebaseAuthException catch (e) {
      // Wrong password, disabled account, waghera — sab ko generic
      // message dete hain taake attacker ko pata na chale ke kya ghalat
      // tha (username exist karta hai ya password).
      if (e.code == 'wrong-password' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-email') {
        _showError("Invalid Username or Password!");
      } else if (e.code == 'too-many-requests') {
        _showError("Too many attempts. Please try again later.");
      } else if (e.code == 'user-disabled') {
        _showError("This account has been disabled. Please contact the admin.");
      } else if (e.code == 'network-request-failed') {
        _showError(
            "No internet connection. Please check your network and try again.");
      } else {
        _showError(e.message ?? "There was a problem logging in.");
      }
    } on TimeoutException {
      _showError(
          "Network is too slow or unavailable. Please check your internet connection and try again.");
    } catch (e) {
      _showError("Error: $e");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }
}
