// ============================================================================
// Cloud Function: sendNotificationOnCreate
// ----------------------------------------------------------------------------
// 'notifications/{notificationId}' collection mein jab bhi app se
// (NotificationHelper.sendToUser / sendToMultiple) ek naya document banta
// he, ye function trigger ho kar us document ke 'toId' + 'toRole' se
// student/teacher ka fcmToken nikalta he aur real push notification
// bhejta he.
//
// SETUP:
//   1) functions/ folder mein ye code apni index.js mein add karein
//      (ya is file ko require kar ke exports mein shamil karein):
//         exports.sendNotificationOnCreate =
//             require('./notification_trigger').sendNotificationOnCreate;
//
//   2) firebase-functions v2 aur firebase-admin already project mein
//      hone chahiye:
//         npm install firebase-functions firebase-admin
//
//   3) Deploy:
//         firebase deploy --only functions:sendNotificationOnCreate
// ============================================================================

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

if (!getApps().length) {
  initializeApp();
}

const db = getFirestore();

exports.sendNotificationOnCreate = onDocumentCreated(
  "schools/{schoolId}/push_notifications/{notificationId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const { schoolId, notificationId } = event.params;
    const notif = snap.data();
    const { toId, toRole, title, body, data, type } = notif;

    if (!toId || !toRole || !title || !body) {
      await snap.ref.update({
        status: "failed",
        error: "Missing required fields (toId/toRole/title/body)",
      });
      return;
    }

    const collectionName = toRole === "teacher" ? "staff" : "students";

    try {
      const userDoc = await db
        .collection("schools")
        .doc(schoolId)
        .collection(collectionName)
        .doc(toId)
        .get();

      if (!userDoc.exists) {
        await snap.ref.update({ status: "failed", error: "User not found" });
        return;
      }

      const token = userDoc.data().fcmToken;
      if (!token) {
        // User ne kabhi app open/login nahi ki, ya notification permission
        // nahi di — is case mein sirf in-app list (jo already ban chuki
        // he is document ki wajah se) kaafi he, push bas skip ho jayega.
        await snap.ref.update({
          status: "failed",
          error: "No fcmToken saved for this user",
        });
        return;
      }

      const message = {
        token,
        notification: { title, body },
        data: {
          type: type || "general",
          notificationId: notificationId,
          ...stringifyMap(data || {}),
        },
        android: {
          priority: "high",
          notification: { channelId: "default_channel" },
        },
        apns: {
          payload: { aps: { sound: "default" } },
        },
      };

      await getMessaging().send(message);
      await snap.ref.update({ status: "sent", sentAt: new Date() });
    } catch (err) {
      await snap.ref.update({
        status: "failed",
        error: err.message || String(err),
      });
    }
  }
);

// FCM data payload ke sab values string hone chahiye.
function stringifyMap(obj) {
  const out = {};
  for (const k in obj) {
    out[k] = typeof obj[k] === "string" ? obj[k] : JSON.stringify(obj[k]);
  }
  return out;
}
