// ============================================================================
// Google Apps Script — FCM Push Notification Relay (100% FREE, Blaze plan
// ki zaroorat NAHI)
// ----------------------------------------------------------------------------
// Cloud Functions ki jagah ye script Firebase Cloud Messaging (FCM) ko
// seedha call karta hai. Google Apps Script bilkul free hai — koi billing
// account ya card lagane ki zaroorat nahi.
//
// SETUP (ek dafa karna hai):
//
//  1) Firebase Console > Project Settings (gear icon) > Service Accounts
//     tab > "Generate new private key" — ek JSON file download hogi.
//
//     (Recommended, optional: Google Cloud Console > IAM me is service
//      account ko sirf "Firebase Cloud Messaging API Admin" role dein,
//      taake key ka scope mehdood rahe.)
//
//  2) script.google.com par jaa kar "New Project" banayein. Default
//     'Code.gs' file ka sara content mita kar ye poora code paste karein.
//
//  3) Left side "Project Settings" (gear icon) > "Script Properties" >
//     "Add script property" — ye 4 properties add karein (JSON file se
//     values copy karein):
//
//       CLIENT_EMAIL   -> JSON file ka "client_email"
//       PRIVATE_KEY    -> JSON file ka "private_key" (poora paste karein,
//                          "-----BEGIN PRIVATE KEY-----" se
//                          "-----END PRIVATE KEY-----" tak)
//       PROJECT_ID     -> JSON file ka "project_id"
//       SHARED_SECRET  -> khud ek lamba random string bana lein (jese
//                          terminal me: openssl rand -hex 24). Ye password
//                          ki tarah he — kisi ko na batayein.
//
//  4) Upar "Deploy" button > "New deployment" > gear icon se type
//     "Web app" select karein.
//       Execute as: Me
//       Who has access: Anyone
//     "Deploy" par click karein, permission maangega to allow kar dein.
//     Jo URL milega (".../exec" par khatam hoga) usay copy kar lein —
//     yehi Flutter ki notification_helper.dart file mein daalna he.
// ============================================================================

function doPost(e) {
  const props = PropertiesService.getScriptProperties();
  const SHARED_SECRET = props.getProperty('SHARED_SECRET');

  let body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return jsonResponse_({ ok: false, error: 'Invalid JSON' });
  }

  // Shared secret match nahi kiya to koi bhi is URL ko call nahi kar sakta.
  if (body.secret !== SHARED_SECRET) {
    return jsonResponse_({ ok: false, error: 'Unauthorized' });
  }

  const tokens = body.tokens || [];
  const title = body.title || '';
  const notifBody = body.body || '';
  const data = body.data || {};

  if (tokens.length === 0) {
    return jsonResponse_({ ok: true, sent: 0, failed: 0 });
  }

  let accessToken;
  try {
    accessToken = getAccessToken_();
  } catch (err) {
    return jsonResponse_({ ok: false, error: 'Auth failed: ' + err });
  }

  const projectId = props.getProperty('PROJECT_ID');
  let sent = 0;
  let failed = 0;

  tokens.forEach(function (token) {
    const message = {
      message: {
        token: token,
        notification: { title: title, body: notifBody },
        data: stringifyMap_(data),
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default' } } },
      },
    };

    const response = UrlFetchApp.fetch(
      'https://fcm.googleapis.com/v1/projects/' + projectId + '/messages:send',
      {
        method: 'post',
        contentType: 'application/json',
        headers: { Authorization: 'Bearer ' + accessToken },
        payload: JSON.stringify(message),
        muteHttpExceptions: true,
      }
    );

    if (response.getResponseCode() === 200) {
      sent++;
    } else {
      failed++;
      Logger.log('FCM send failed: ' + response.getContentText());
    }
  });

  return jsonResponse_({ ok: true, sent: sent, failed: failed });
}

// Service account credentials (JWT bearer flow) se OAuth2 access token
// banata hai — koi external library ki zaroorat nahi.
function getAccessToken_() {
  const props = PropertiesService.getScriptProperties();
  const clientEmail = props.getProperty('CLIENT_EMAIL');
  const privateKey = props.getProperty('PRIVATE_KEY').replace(/\\n/g, '\n');

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claimSet = {
    iss: clientEmail,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = base64UrlEncode_(JSON.stringify(header));
  const encodedClaim = base64UrlEncode_(JSON.stringify(claimSet));
  const signatureInput = encodedHeader + '.' + encodedClaim;

  const signatureBytes = Utilities.computeRsaSha256Signature(
    signatureInput,
    privateKey
  );
  const encodedSignature = Utilities.base64EncodeWebSafe(
    signatureBytes
  ).replace(/=+$/, '');

  const jwt = signatureInput + '.' + encodedSignature;

  const tokenResponse = UrlFetchApp.fetch(
    'https://oauth2.googleapis.com/token',
    {
      method: 'post',
      contentType: 'application/x-www-form-urlencoded',
      payload: {
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      },
      muteHttpExceptions: true,
    }
  );

  const tokenData = JSON.parse(tokenResponse.getContentText());
  if (!tokenData.access_token) {
    throw new Error(tokenResponse.getContentText());
  }
  return tokenData.access_token;
}

function base64UrlEncode_(str) {
  return Utilities.base64EncodeWebSafe(
    Utilities.newBlob(str).getBytes()
  ).replace(/=+$/, '');
}

// FCM data payload ke sab values string hone chahiye.
function stringifyMap_(obj) {
  const out = {};
  for (const k in obj) {
    out[k] = typeof obj[k] === 'string' ? obj[k] : JSON.stringify(obj[k]);
  }
  return out;
}

function jsonResponse_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(
    ContentService.MimeType.JSON
  );
}
