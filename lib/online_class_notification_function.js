/**
 * Cloud Function: sendOnlineClassNotification
 * ----------------------------------------------------------------------------
 * Deploy this in your Firebase Functions project (functions/index.js or a
 * file you `require` from it). It listens for new documents in
 * `online_classes` and pushes a notification to every active student in
 * that class (and section, if one was set) — which reaches the parent's
 * device, since NotificationService.initParent() already saves the
 * parent's fcmToken on each of their children's student documents.
 *
 * This has to run server-side (Cloud Functions) because sending an FCM
 * push requires the Firebase Admin SDK / a service account — that can
 * never be shipped inside the Flutter app.
 *
 * IMPORTANT: adjust the Firestore paths below ("schools/{schoolId}/...")
 * to exactly match whatever your app's `schoolCollection()` helper uses.
 * This file assumes the common multi-tenant layout
 * schools/{schoolId}/online_classes and schools/{schoolId}/students.
 *
 * Install (once, inside your functions/ folder):
 *   npm install firebase-admin firebase-functions
 */

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

exports.sendOnlineClassNotification = onDocumentCreated(
  'schools/{schoolId}/online_classes/{classId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const { schoolId } = event.params;
    const className = data.className;
    const section = (data.section || '').toString().trim();
    const title = data.title || 'New Online Class';
    const subject = data.subject || '';
    const platform = data.platform || '';

    if (!className) return;

    // Find every active student in this class (and section, if given).
    let studentsQuery = admin
      .firestore()
      .collection('schools')
      .doc(schoolId)
      .collection('students')
      .where('status', '==', 'active')
      .where('class', '==', className);

    if (section) {
      studentsQuery = studentsQuery.where('section', '==', section);
    }

    const studentsSnap = await studentsQuery.get();
    if (studentsSnap.empty) {
      console.log(`No active students found for ${className} ${section}`);
      return;
    }

    // Collect unique, non-empty FCM tokens (siblings can share a parent's
    // device/token — de-dupe so the parent isn't notified twice).
    const tokens = [
      ...new Set(
        studentsSnap.docs
          .map((doc) => doc.data().fcmToken)
          .filter((t) => typeof t === 'string' && t.length > 0)
      ),
    ];

    if (tokens.length === 0) {
      console.log(`No FCM tokens found for ${className} ${section}`);
      return;
    }

    const notificationBody = subject
      ? `${subject} • ${platform} • scheduled now`
      : `${platform} • scheduled now`;

    // FCM allows a max of 500 tokens per multicast call — batch it.
    const batches = [];
    for (let i = 0; i < tokens.length; i += 500) {
      batches.push(tokens.slice(i, i + 500));
    }

    for (const batch of batches) {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        notification: {
          title: `Online Class: ${title}`,
          body: notificationBody,
        },
        data: {
          type: 'online_class',
          classId: event.params.classId,
          className,
          section,
        },
      });

      // Clean up tokens that are no longer valid (uninstalled app, etc.)
      response.responses.forEach((res, idx) => {
        if (
          !res.success &&
          (res.error?.code === 'messaging/registration-token-not-registered' ||
            res.error?.code === 'messaging/invalid-registration-token')
        ) {
          const badToken = batch[idx];
          studentsSnap.docs
            .filter((doc) => doc.data().fcmToken === badToken)
            .forEach((doc) => doc.ref.update({ fcmToken: admin.firestore.FieldValue.delete() }));
        }
      });
    }

    console.log(`Sent online class notification to ${tokens.length} device(s).`);
  }
);
