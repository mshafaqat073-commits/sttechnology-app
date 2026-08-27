const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

if (!getApps().length) {
  initializeApp();
}

const db = getFirestore();

exports.sendNotificationOnCreate = onDocumentCreated(
  "push_notifications/{notificationId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

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
      const userDoc = await db.collection(collectionName).doc(toId).get();

      if (!userDoc.exists) {
        await snap.ref.update({ status: "failed", error: "User not found" });
        return;
      }

      const token = userDoc.data().fcmToken;
      if (!token) {
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
          notificationId: event.params.notificationId,
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

function stringifyMap(obj) {
  const out = {};
  for (const k in obj) {
    out[k] = typeof obj[k] === "string" ? obj[k] : JSON.stringify(obj[k]);
  }
  return out;
}