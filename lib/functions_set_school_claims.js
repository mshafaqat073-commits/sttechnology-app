// ============================================================================
// Cloud Function: setSchoolClaims
// ----------------------------------------------------------------------------
// Teacher/Parent login (staff/students subcollection mein authUid link hone)
// ke FAURAN baad app ye callable function hit karta hai. Ye function verify
// karta hai ke us Firebase Auth uid ka record wakai us school ke andar
// maujood hai, aur agar haan to us user ke Firebase Auth token par
// custom claims { schoolId, role } laga deta hai.
//
// Firestore security rules (firestore.rules) inhi claims ko check karke
// decide karti hain ke koi user sirf apni school ka data access kar sakta
// he, kisi doosri school ka nahi.
//
// NOTE — Admin: Admin abhi Firebase Auth use hi nahi karta (sirf
// username/password Firestore query se check hota he, koi Auth session
// nahi banta). Is liye Admin ke liye ye function apply nahi hoti, aur
// Firestore rules mein Admin access abhi bhi properly secure nahi ho
// sakta jab tak Admin login ko bhi Firebase Auth (email/password) par
// migrate na kiya jaye. Filhaal ye ek known limitation hai — README
// mein isay explain kiya gaya he.
//
// SETUP:
//   1) functions/ folder ki index.js mein add/require karein:
//        exports.setSchoolClaims =
//            require('./set_school_claims').setSchoolClaims;
//   2) Deploy: firebase deploy --only functions:setSchoolClaims
//   3) pubspec.yaml mein 'cloud_functions' package add karein aur
//      Flutter side se HttpsCallable use karein (README dekhein).
// ============================================================================

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

if (!getApps().length) {
  initializeApp();
}

const db = getFirestore();

exports.setSchoolClaims = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Pehle login karein.");
  }

  const uid = request.auth.uid;
  const { schoolId, role } = request.data || {};

  if (!schoolId || (role !== "teacher" && role !== "parent")) {
    throw new HttpsError(
      "invalid-argument",
      "schoolId aur role ('teacher' ya 'parent') zaroori hain."
    );
  }

  // Verify karte hain ke ye uid wakai isi school ke staff/students
  // subcollection mein linked hai — taake koi khud se apne liye
  // kisi bhi school ka claim na bana sake.
  const groupName = role === "teacher" ? "staff" : "students";
  const snap = await db
    .collectionGroup(groupName)
    .where("authUid", "==", uid)
    .get();

  const verified = snap.docs.some(
    (doc) => doc.ref.parent.parent && doc.ref.parent.parent.id === schoolId
  );

  if (!verified) {
    throw new HttpsError(
      "permission-denied",
      "Is uid ka is school ke andar koi record nahi mila."
    );
  }

  await getAuth().setCustomUserClaims(uid, { schoolId, role });
  return { schoolId, role };
});
