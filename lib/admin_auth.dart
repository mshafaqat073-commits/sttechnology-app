/// Admin login now uses Firebase Auth (behind the username/password),
/// but an Admin doesn't actually have an email — only a username. So an
/// "internal" email is generated for each admin, which is only used as
/// an identifier inside Firebase Auth — it's never shown to the user and
/// is never verified/used like a real email.
///
/// !! IMPORTANT !!
/// This email is generated only at ACCOUNT CREATION time (migration
/// script / when adding a new admin), from the username at that time,
/// and then stays FIXED forever — even if the admin later changes their
/// "username" (the display/login field in Firestore). Login always first
/// looks up the username in Firestore, reads that doc's `authEmail`
/// field, and then passes that same email to Firebase Auth — so changing
/// the username never causes any issue.
///
/// The Node.js migration script (migrate_admin_to_auth.js, project root)
/// must have exactly this same logic, otherwise the emails on both sides
/// won't match.
const String kAdminAuthEmailDomain = 'admin.aepschoolsystem.local';

String adminEmailForUsername(String username) {
  final cleaned = username
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  return '$cleaned@$kAdminAuthEmailDomain';
}
