/// Admin login ab (username/password ke pichay) Firebase Auth use karta hai,
/// lekin Admin ke paas asal mein koi email nahi hoti — sirf username hota
/// hai. Is liye har admin ke liye ek "internal" email khud bana lete hain,
/// jo sirf Firebase Auth ke andar identifier ke tor par use hoti hai, kabhi
/// user ko dikhai nahi jaati aur kabhi real email ki tarah verify/use nahi
/// hoti.
///
/// !! IMPORTANT !!
/// Ye email sirf ACCOUNT BANATE waqt (migration script / naya admin add
/// karte waqt) us waqt ke username se banti hai aur phir hamesha ke liye
/// FIXED rehti hai — chahe baad mein admin apna "username" (Firestore
/// wala display/login field) badal le. Login hamesha pehle Firestore mein
/// username se dhoond kar us doc ki `authEmail` field nikalta hai, phir
/// wahi email Firebase Auth ko deta hai — is liye username badalne se
/// koi masla nahi hota.
///
/// Node.js migration script (migrate_admin_to_auth.js, project root) mein bhi
/// bilkul yehi logic honi chahiye, warna dono taraf ki email match nahi
/// karegi.
const String kAdminAuthEmailDomain = 'admin.aepschoolsystem.local';

String adminEmailForUsername(String username) {
  final cleaned = username
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  return '$cleaned@$kAdminAuthEmailDomain';
}
