import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';

/// App-wide login no longer uses Firebase Phone Auth (SMS OTP) — SMS OTP
/// incurs a per-message charge on Firebase Blaze billing, which becomes
/// expensive for 10,000+ parents/staff. Instead, every Parent/Teacher
/// automatically gets a Login ID + PIN at admission/staff-form time
/// (see admission_page.dart / add_staff_page.dart). On the login screen,
/// that same ID+PIN is matched against Firestore (parent_login_page.dart /
/// teacher_login_page.dart).
///
/// For the session we use Firebase Anonymous Auth — this is completely
/// free even on Firebase's FREE (Spark) plan, requires no billing/Blaze,
/// and genuinely scales without limit. That anonymous account's uid is
/// linked on the matched student/staff record as 'authUid' — exactly the
/// way the old phone-auth uid used to be linked — so the rest of the app
/// (main.dart's _RoleRouter, Firestore security rules, etc.) keeps working
/// exactly as before, and the session also persists across app restarts.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Creates or reuses a session for login. If an (anonymous) session
  /// already exists it is reused, otherwise a new anonymous account is
  /// created. This call never sends SMS/OTP and is completely free.
  Future<User> signInAnonymouslyForLogin() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing;
    final cred = await _auth.signInAnonymously();
    if (cred.user == null) {
      throw StateError("Anonymous sign-in failed — user null.");
    }
    return cred.user!;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

final Random _rng = Random.secure();

/// Generates a new random Login ID, e.g. "P48213" (Parent) or "T77291"
/// (Teacher/Staff). Pass a single letter for [prefix], e.g. "P" or "T".
String generateLoginId(String prefix) {
  final n = 10000 + _rng.nextInt(90000); // 5-digit: 10000-99999
  return "$prefix$n";
}

/// Generates a 4-digit numeric PIN, e.g. "4821".
String generatePin() {
  final n = _rng.nextInt(10000);
  return n.toString().padLeft(4, '0');
}
