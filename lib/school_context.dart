import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Only ONE school is "active" across the whole app at a time — set at
/// login time (Admin username/password, Teacher/Parent Login ID+PIN — all
/// three flows store their schoolId here). After that, every page reads/
/// writes data only within that schoolId, so two schools' data never mix.
///
/// The Firestore structure is now:
///   schools/{schoolId}                     -> basic school info
///   schools/{schoolId}/settings/global      -> schoolName, principalName, address, logoUrl
///   schools/{schoolId}/students/{id}
///   schools/{schoolId}/staff/{id}
///   schools/{schoolId}/users/{id}           -> admin login (username/password)
///   schools/{schoolId}/fee_payments/{id}
///   ... etc. (every former top-level collection now lives under this)
class SchoolContext {
  static String? _schoolId;
  static String? _schoolName;
  static String? _logoUrl;
  static String? _contactNumber;
  static String? _contactEmail;
  static String? _principalName;

  /// School's own online payment accounts (JazzCash, Easypaisa, bank
  /// account, or any other method) — set from Settings > "Online Payment
  /// Accounts". Each entry is a map with keys: 'method', 'number',
  /// 'accountName'. Replaces the old fixed Easypaisa/UBL-only fields so
  /// the admin can add any number of accounts of any method.
  static List<Map<String, String>> _paymentAccounts = [];

  /// This counter increments every time schoolName/logoUrl changes —
  /// SchoolLogo / SchoolNameText widgets listen to it so that changing the
  /// name/logo in Settings shows up instantly across the whole app
  /// (without an app restart). See lib/school_branding.dart.
  static final ValueNotifier<int> _version = ValueNotifier<int>(0);
  static ValueListenable<int> get listenable => _version;

  static String get schoolId {
    final id = _schoolId;
    if (id == null) {
      throw StateError(
          'SchoolContext.schoolId is not set. Firestore should not be '
          'accessed before the login flow completes — SchoolContext.set() '
          'must be called first.');
    }
    return id;
  }

  static String? get schoolIdOrNull => _schoolId;
  static String? get schoolName => _schoolName;
  static String? get logoUrl => _logoUrl;

  /// This school's own WhatsApp/contact number — set from Settings >
  /// WhatsApp Number. Each school adds its own number; wherever the app
  /// needs to show/use the school's contact number (AI chat, SLC,
  /// letterhead, etc.), use this field instead of a hardcoded number.
  static String? get contactNumber => _contactNumber;

  /// This school's own contact email — Settings > Contact Email. Same
  /// pattern as contactNumber above: wherever the app needs to show or
  /// use an email address (reports, letterhead, AI chat, etc.), it should
  /// read this field instead of a hardcoded address.
  static String? get contactEmail => _contactEmail;

  /// This school's own principal name — Settings > Principal Name. Same
  /// pattern as contactNumber/contactEmail above: wherever the app needs
  /// to show or use the principal's name (AI chat, letterhead, etc.), it
  /// should read this field instead of a hardcoded name.
  static String? get principalName => _principalName;
  static bool get isSet => _schoolId != null;

  /// This school's own online payment accounts — set from Settings >
  /// "Online Payment Accounts". The parent app's "Pay Fee Online" screen
  /// shows exactly these accounts (no account is hardcoded — each school
  /// adds its own via a dialog: method + account number + account name).
  static List<Map<String, String>> get paymentAccounts => _paymentAccounts;

  /// Whether the school has added at least one payment account —
  /// PayFeeOnlinePage uses this to decide whether to show the account
  /// cards or an "admin hasn't set this up yet" message.
  static bool get hasPaymentAccountSet => _paymentAccounts.isNotEmpty;

  static void set(String id, {String? name}) {
    _schoolId = id;
    if (name != null) _schoolName = name;
  }

  /// Call this right after login (immediately after SchoolContext.set())
  /// — it loads and caches schoolName and logoUrl from that school's
  /// settings/global doc, so the whole app and PDFs can use it without
  /// reading Firestore repeatedly.
  ///
  /// Also call this again after the name/logo is updated from the
  /// Settings page, so the cache refreshes immediately.
  static Future<void> loadBranding() async {
    try {
      final doc = await schoolCollection('settings').doc('global').get();
      final data = doc.data();
      final name = (data?['schoolName'] as String?)?.trim();
      final logo = (data?['logoUrl'] as String?)?.trim();
      final contact = (data?['contactNumber'] as String?)?.trim();
      final email = (data?['contactEmail'] as String?)?.trim();
      final principal = (data?['principalName'] as String?)?.trim();
      final rawAccounts = data?['paymentAccounts'] as List<dynamic>?;
      _schoolName = (name != null && name.isNotEmpty) ? name : null;
      _logoUrl = (logo != null && logo.isNotEmpty) ? logo : null;
      _contactNumber = (contact != null && contact.isNotEmpty) ? contact : null;
      _contactEmail = (email != null && email.isNotEmpty) ? email : null;
      _principalName = (principal != null && principal.isNotEmpty) ? principal : null;
      _paymentAccounts = (rawAccounts ?? [])
          .map((e) => Map<String, String>.from(
              (e as Map).map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))))
          .where((e) => (e['number'] ?? '').isNotEmpty)
          .toList();
    } catch (_) {
      // Network issue etc. — keep whatever is already cached.
    }
    _version.value++;
  }

  /// Applies a logo URL that was cached locally (SharedPreferences) from
  /// the last successful login — used on the Admin Login screen so it
  /// can show that school's logo again before this login even starts,
  /// without doing any Firestore call. Does NOT touch schoolName, so the
  /// Role Selector's generic app name (see lib/app_branding.dart) is
  /// never affected by this.
  static void applyCachedPreLoginLogo(String? url) {
    _logoUrl = (url != null && url.isNotEmpty) ? url : null;
    _version.value++;
  }

  /// Call this BEFORE login (at app startup) — it loads schoolName/logoUrl
  /// from the settings/global of whichever school is found in Firestore,
  /// so the Role Selector and Login screen can also show that school's
  /// own logo/name instead of a generic default (see
  /// lib/app_branding.dart).
  ///
  /// NOTE: This does NOT set SchoolContext.schoolId — it only caches the
  /// name/logo for display. The real "active school" is always decided
  /// by SchoolContext.set() after login. If Firestore has more than one
  /// school, any one of them may be returned (order is not guaranteed) —
  /// this app is designed assuming one deployment per school, so in
  /// practice there is virtually always just one school.
  ///
  /// NOT currently called anywhere (kept for reference/future use) —
  /// the app now uses applyCachedPreLoginLogo() + the locally saved
  /// "last logged-in school" logo instead, so the Role Selector always
  /// shows the generic app name/logo until an actual login happens.
  static Future<void> loadPreLoginBranding() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('settings')
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final name = (data['schoolName'] as String?)?.trim();
        final logo = (data['logoUrl'] as String?)?.trim();
        if (name != null && name.isNotEmpty) _schoolName = name;
        if (logo != null && logo.isNotEmpty) _logoUrl = logo;
      }
    } catch (_) {
      // Network issue, no school created yet, etc. — silently stay on
      // default branding.
    }
    _version.value++;
  }

  /// Make sure to call this at logout, otherwise the next login could
  /// show the previous school's data until a new SchoolContext.set() is
  /// made.
  static void clear() {
    _schoolId = null;
    _schoolName = null;
    _logoUrl = null;
    _contactNumber = null;
    _contactEmail = null;
    _principalName = null;
    _paymentAccounts = [];
    _version.value++;
  }
}

/// A reference to a collection inside the current (logged-in) school.
/// Example: schoolCollection('students') ==
///   schools/{SchoolContext.schoolId}/students
CollectionReference<Map<String, dynamic>> schoolCollection(String name) {
  return FirebaseFirestore.instance
      .collection('schools')
      .doc(SchoolContext.schoolId)
      .collection(name);
}

/// The current school's own document — schools/{schoolId}
DocumentReference<Map<String, dynamic>> schoolDoc() {
  return FirebaseFirestore.instance
      .collection('schools')
      .doc(SchoolContext.schoolId);
}

/// Extracts the schoolId from the reference of any document under
/// schools/{schoolId}/<collection>/<id>. Used at login time to find the
/// schoolId of documents returned by a collectionGroup query (at that
/// point SchoolContext isn't set yet, so schoolCollection() above can't
/// be used).
String schoolIdFromDoc(DocumentReference ref) {
  final schoolDocRef = ref.parent.parent; // schools/{schoolId}
  if (schoolDocRef == null || schoolDocRef.parent.id != 'schools') {
    throw StateError(
        'This document is not inside a schools/{schoolId}/... subcollection: '
        '${ref.path}');
  }
  return schoolDocRef.id;
}
