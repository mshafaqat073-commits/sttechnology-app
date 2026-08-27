// ============================================================================
// One-time migration: har school ke `users` subcollection mein maujood
// plaintext-password Admin records ko Firebase Auth accounts mein convert
// karta hai.
//
// Ye karta hai:
//   1. Har schools/{schoolId}/users/{docId} doc padhta hai jisme abhi
//      "username" + "password" (plaintext) hai.
//   2. Us username se ek FIXED "internal" email banata hai (kabhi real
//      email ki tarah use ya verify nahi hoti — sirf Firebase Auth
//      identifier hai). Logic lib/admin_auth.dart ke `adminEmailForUsername`
//      se HUBAHU match karti hai — agar wahan formula badlein to yahan
//      bhi badalna zaroori hai.
//   3. Firebase Auth mein us email/password se account banata hai (agar
//      pehle se na ho to).
//   4. Us account par custom claims { schoolId, role: 'admin' } laga deta
//      hai — Firestore rules (firestore.rules) inhi claims se Admin ko
//      access dete hain.
//   5. Firestore doc update karta hai: `authEmail` aur `authUid` fields
//      add karta hai, aur `password` field HATA deta hai (ab plaintext
//      password kahin store nahi hota).
//
// Idempotent hai — dobara chalane par jo accounts pehle se ban chuke hain
// unhein skip kar deta hai (email already-exists check karta hai).
//
// SETUP:
//   1) npm install firebase-admin
//   2) Firebase Console > Project Settings > Service Accounts se ek
//      "serviceAccountKey.json" download kar ke isi folder mein rakhein.
//   3) node migrate_admin_to_auth.js
//
// ⚠️ Chalane se pehle Firestore ka ek manual backup/export zaroor le lein
//    (Firebase Console > Firestore > Export).
// ============================================================================

const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const auth = admin.auth();

// !! lib/admin_auth.dart ke `adminEmailForUsername` se bilkul match hona
// chahiye !!
const AUTH_EMAIL_DOMAIN = "admin.aepschoolsystem.local";

function adminEmailForUsername(username) {
  const cleaned = username
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]/g, "_");
  return `${cleaned}@${AUTH_EMAIL_DOMAIN}`;
}

async function migrateOneUserDoc(doc) {
  const data = doc.data();
  const username = (data.username || "").toString();
  const password = (data.password || "").toString();

  if (!username) {
    console.log(`  [skip] ${doc.ref.path}: 'username' field khaali/missing hai`);
    return;
  }

  const schoolDocRef = doc.ref.parent.parent; // schools/{schoolId}
  if (!schoolDocRef || schoolDocRef.parent.id !== "schools") {
    console.log(`  [skip] ${doc.ref.path}: schools/{schoolId}/users/... ke andar nahi hai`);
    return;
  }
  const schoolId = schoolDocRef.id;

  if (data.authEmail && data.authUid) {
    console.log(`  [already migrated] ${doc.ref.path} (username: ${username})`);
    return;
  }

  const email = adminEmailForUsername(username);

  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    console.log(`  [auth account pehle se maujood] ${email}`);
  } catch (err) {
    if (err.code !== "auth/user-not-found") throw err;

    if (!password) {
      console.log(
        `  [skip] ${doc.ref.path}: 'password' field khaali/missing hai, account nahi ban saka`
      );
      return;
    }

    userRecord = await auth.createUser({
      email,
      password,
      disabled: false,
    });
    console.log(`  [naya auth account bana] ${email} (uid: ${userRecord.uid})`);
  }

  await auth.setCustomUserClaims(userRecord.uid, {
    schoolId,
    role: "admin",
  });

  await doc.ref.update({
    authEmail: email,
    authUid: userRecord.uid,
    password: admin.firestore.FieldValue.delete(),
  });

  console.log(`  [done] ${doc.ref.path} -> schoolId="${schoolId}", authUid="${userRecord.uid}"`);
}

async function main() {
  console.log("Admin -> Firebase Auth migration shuru...\n");

  const snapshot = await db.collectionGroup("users").get();
  if (snapshot.empty) {
    console.log("Koi 'users' record nahi mila.");
    return;
  }

  console.log(`${snapshot.size} 'users' record(s) mile.\n`);

  for (const doc of snapshot.docs) {
    try {
      await migrateOneUserDoc(doc);
    } catch (err) {
      console.error(`  [ERROR] ${doc.ref.path}:`, err.message || err);
    }
  }

  console.log("\nDone. Ab har admin apne purane username/password se hi login kar sakta hai —");
  console.log("bas asal check ab Firebase Auth karta hai, Firestore mein plaintext password nahi bacha.");
}

main().catch((err) => {
  console.error("Migration fail hui:", err);
  process.exit(1);
});
