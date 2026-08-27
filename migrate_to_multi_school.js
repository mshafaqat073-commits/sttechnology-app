// ============================================================================
// One-time migration: purana single-school data ko schools/{schoolId}/...
// structure mein copy karta hai.
//
// USE: Sirf EK dafa chalayein — apke MOJOODA (purane) Firebase project ka
// data isi project ke naye multi-school structure mein le aata hai. Naye
// schools ko is script se koi taluq nahi (unka data seedha sahi jagah
// bnta hai).
//
// SETUP:
//   1) npm install firebase-admin
//   2) Firebase Console > Project Settings > Service Accounts se ek
//      "serviceAccountKey.json" download kar ke isi folder mein rakhein.
//   3) Neeche SCHOOL_ID aur SCHOOL_NAME apni marzi se set karein (ye us
//      naye school ka ID/naam hoga jahan purana sara data chala jayega).
//   4) node migrate_to_multi_school.js
//
// ⚠️ Chalane se pehle Firestore ka ek manual backup/export zaroor le lein
//    (Firebase Console > Firestore > Export), taake kuch ghalat ho to
//    wapas laya ja sake.
// ============================================================================

const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// ---- Yahan apni values likhein --------------------------------------------
const SCHOOL_ID = "my-first-school"; // Firestore doc ID — chota, no spaces
const SCHOOL_NAME = "Mera School";
// -----------------------------------------------------------------------

const COLLECTIONS_TO_MIGRATE = [
  "SLC",
  "app_settings",
  "attendance",
  "bulk_fee_operations",
  "counters",
  "documents",
  "expenses",
  "fee_history",
  "fee_payments",
  "fee_structures",
  "notifications",
  "other_incomes",
  "push_notifications",
  "results",
  "school_diary",
  "school_events",
  "school_homework",
  "settings",
  "special_messages",
  "staff",
  "students",
  "teacher_attendance",
  "teacher_notifications",
  "teachers",
  "timetable",
  "users",
];

const BATCH_SIZE = 400;

async function migrateCollection(name) {
  const src = db.collection(name);
  const dest = db.collection("schools").doc(SCHOOL_ID).collection(name);

  const snapshot = await src.get();
  if (snapshot.empty) {
    console.log(`  (${name}: khaali hai, skip)`);
    return 0;
  }

  let count = 0;
  const docs = snapshot.docs;
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + BATCH_SIZE);
    for (const doc of chunk) {
      batch.set(dest.doc(doc.id), doc.data());
    }
    await batch.commit();
    count += chunk.length;
  }
  console.log(`  ${name}: ${count} documents migrate ho gaye`);
  return count;
}

async function main() {
  console.log(`Migration shuru: schoolId = "${SCHOOL_ID}"`);

  // School ka apna document bana dein
  await db.collection("schools").doc(SCHOOL_ID).set(
    {
      name: SCHOOL_NAME,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  let total = 0;
  for (const coll of COLLECTIONS_TO_MIGRATE) {
    total += await migrateCollection(coll);
  }

  console.log(`\nDone. Total ${total} documents "schools/${SCHOOL_ID}/..." mein copy ho gaye.`);
  console.log(
    `Purani (top-level) collections abhi bhi maujood hain — sab kuch check kar lene ke baad, ` +
    `unhein Firebase Console se manually delete kar dein taake purana/naya data mix hoke confusion na paida ho.`
  );
}

main().catch((err) => {
  console.error("Migration fail hui:", err);
  process.exit(1);
});
