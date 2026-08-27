# Multi-School Conversion — Setup Guide

## Kya badla hai

Poora data ab `schools/{schoolId}/...` ke andar rehta hai, top-level nahi.
Login (Admin username/password, Teacher/Parent phone OTP) — teeno ab
`collectionGroup()` se **saari schools** mein dhoondte hain ke ye user
kaunse school ka hai, phir usi school ko `SchoolContext` mein "lock" kar
dete hain. Uske baad poori app (86 files) isi locked school ke andar hi
padhti/likhti hai (`schoolCollection('students')` waghera — dekhein
`lib/school_context.dart`).

## 1. Naya school add karna (aap manually karenge)

Firebase Console > Firestore > "Start collection" se:

```
schools/{schoolId}                (schoolId khud choose karein, e.g. "abc-school")
  name: "ABC Public School"
  createdAt: <timestamp>

schools/{schoolId}/users/{autoId}   <- admin ka login
  username: "admin"
  password: "kuch_strong_password"

schools/{schoolId}/staff/...        <- app se hi add hoga (Add Staff page)
schools/{schoolId}/students/...     <- app se hi add hoga (Admission page)
```

Bas itna karne ke baad us school ka Admin turant login kar sakta hai —
baaqi (staff, students, fees...) sab app ke andar se hi add hota hai jaisa
pehle hota tha.

## 2. Purana data migrate karna

Agar pehle se ek school ka data maujood hai (top-level collections mein),
to `migrate_to_multi_school.js` chalayein:

```
npm install firebase-admin
node migrate_to_multi_school.js
```

Chalane se pehle file ke andar `SCHOOL_ID` aur `SCHOOL_NAME` set kar lein,
aur Firestore ka ek manual export/backup zaroor le lein. Migration ke baad,
sab kuch check kar ke purani top-level collections Console se delete kar
dein.

## 3. Cloud Functions deploy karna

Do functions hain:

- `functions_notification_trigger.js` — push notification bhejta hai
  (`schools/{schoolId}/push_notifications/{id}` par trigger hota hai —
  path update ho chuka hai).
- `functions_set_school_claims.js` — Teacher/Parent login ke baad
  `{schoolId, role}` claim laga deta hai, taake Firestore rules unhein
  sirf apni school ka data dikhayen.

`functions/index.js` mein dono ko require/export karein, phir:

```
firebase deploy --only functions
```

## 4. Firestore security rules

`firestore.rules` file bana di gayi hai — ye custom claims (`schoolId`,
`role`) check karke ek school ka data doosri school ko nahi dikhne deti.
Deploy: `firebase deploy --only firestore:rules`

## 4b. Firestore indexes (zaroori — warna login "failed-precondition" error dega)

Login flows ab `collectionGroup()` queries use karte hain (saari schools
mein user dhoondne ke liye), aur Firestore in par explicit index maangta
hai. `firestore.indexes.json` bana di gayi hai — deploy karein:

```
firebase deploy --only firestore:indexes
```

(Agar `firebase.json` mein indexes file ka path set nahi hai to pehle
`"firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" }`
add karein.) Index banne mein 1-2 minute lagta hai. Agar deploy na karna
ho, to jab bhi koi "failed-precondition ... requires an index" error aaye,
uske sath diya gaya link click kar ke Firebase Console se bhi bana sakte
hain.

### ⚠️ Zaroori: Teacher/Parent login mein ek chhota sa addition baaqi hai

Rules kaam karne ke liye, login hone ke FAURAN baad app ko
`setSchoolClaims` Cloud Function call karni hogi. Ye maine abhi Dart code
mein wire nahi kiya kyunke isay `cloud_functions` package chahiye jo
shayad aapke `pubspec.yaml` mein na ho — pehle ye line add karein:

```yaml
dependencies:
  cloud_functions: ^5.0.0   # ya jo bhi latest stable version ho
```

Phir `teacher_login_page.dart` aur `parent_login_page.dart` mein,
`SchoolContext.set(...)` ke turant baad ye add karein:

```dart
import 'package:cloud_functions/cloud_functions.dart';
// ...
await FirebaseFunctions.instance.httpsCallable('setSchoolClaims').call({
  'schoolId': SchoolContext.schoolId,
  'role': 'teacher', // ya 'parent' — jis file mein ho
});
await FirebaseAuth.instance.currentUser?.getIdToken(true); // naya claim load karo
```

### ✅ Admin ab Firebase Auth use karta hai (pehle ye ek known limitation thi)

Admin login ab bhi UI mein Username/Password hi maangta hai, lekin peeche
asal check ab **Firebase Auth** karta hai — Firestore mein plaintext
password kahin store nahi hota. Kaam yun karta hai:

- Har admin ke liye ek "internal" email khud ban jaati hai (username se,
  dekhein `lib/admin_auth.dart`) — ye kabhi real email ki tarah use ya
  verify nahi hoti, sirf Firebase Auth identifier hai.
- `schools/{schoolId}/users/{id}` doc mein ab `username`, `authEmail`,
  `authUid` fields hain (`password` field hata di gayi hai).
- Login (`lib/login_page.dart`) pehle username se doc dhoondta hai (ye
  collectionGroup query publicly readable hai kyunke doc mein ab koi
  secret nahi — dekhein `firestore.rules`), phir us doc ki `authEmail` +
  typed password se `FirebaseAuth.signInWithEmailAndPassword` call karta
  hai.
- `firestore.rules` mein Admin ke liye ab koi alag/khula rule nahi chahiye
  — generic `isAdminOfSchool()` check hi kaam karta hai, kyunke Admin ke
  Firebase Auth account par `{schoolId, role: 'admin'}` claim account
  banate hi laga di jaati hai.

**Purane admins (jo is migration se pehle bane the) ke liye ek baar
chalayein:**

```
npm install firebase-admin
node migrate_admin_to_auth.js
```

(`serviceAccountKey.json` chahiye hoga — dekhein `migrate_to_multi_school.js`
wale steps, same tareeqa.) Ye script har `users` doc ke liye Firebase Auth
account bana kar `authEmail`/`authUid` set kar deta hai, aur plaintext
`password` field hata deta hai. Idempotent hai, dobara chalane se kuch
nahi toothega.

**Naya school/admin banate waqt:** Ab sirf Firestore Console se
`username`+`password` doc bana kar chhod dena kaafi nahi — us naye admin
par bhi ye migration script chalana zaroori hai (ya usay bhi
`migrate_admin_to_auth.js` mein include kar lein), warna wo login nahi kar
sakega ("Ye account abhi update nahi hua" wala error dikhega).

**Username/Password badalna:** Settings > "Update Login Info"
(`lib/auth_settings.dart`) se — username sirf Firestore field hai (seedha
badal jata hai), password Firebase Auth mein update hota hai (current
password se reauthenticate karne ke baad).

## 5. Quick checklist

- [ ] Naya school Firestore Console se add kiya (`schools/{id}` + `users`
      doc — `username` + `password`)
- [ ] `node migrate_admin_to_auth.js` chala kar us admin ko Firebase Auth
      account diya
- [ ] Purana data migrate script se copy kiya (agar zaroorat ho)
- [ ] `pubspec.yaml` mein `cloud_functions` add kiya (Teacher/Parent ke
      liye — Admin ko iski zaroorat nahi)
- [ ] Teacher/Parent login mein `setSchoolClaims` call wire kiya
- [ ] Dono Cloud Functions deploy kiye
- [ ] `firestore.rules` deploy kiye
- [ ] `firestore.indexes.json` deploy kiya (`username` aur `authUid`
      single-field collection-group indexes)
