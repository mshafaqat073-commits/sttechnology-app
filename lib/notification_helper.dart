import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'school_context.dart';
import 'secrets.dart';

// ============================================================================
// NotificationHelper
// ----------------------------------------------------------------------------
// Admin/teacher ki taraf se koi bhi action ho — diary entry, homework,
// special message, fee reminder waghera — is helper ko call karein.
//
// Ye do kaam karta hai:
//   1) 'push_notifications' collection mein ek document likhta he — isay
//      app ke andar "Notifications" (bell icon) list ke liye use karte
//      hain. Ye Firestore ka normal free-tier read/write he, koi billing
//      nahi chahiye.
//   2) Diya gaya FCM token(s) par seedha push notification bhejta he —
//      Cloud Function ki jagah ek FREE Google Apps Script web app ko call
//      kar ke (apps_script_fcm_relay.gs), taake Blaze (paid) plan ki
//      zaroorat na pare.
//
// SETUP: neeche _pushEndpoint aur _sharedSecret mein apni Apps Script
// deployment ki values daalein (apps_script_fcm_relay.gs ke comments mein
// pura tareeqa likha hua he).
// ============================================================================

class NotificationHelper {
  // Ye dono ab lib/secrets.dart mein hain — wo file GitHub par kabhi
  // nahi jati (.gitignore mein he), isliye yahan hardcode nahi kiye.
  static const String _pushEndpoint = notificationEndpoint;
  static const String _sharedSecret = notificationSharedSecret;

  static final _col =
      schoolCollection('push_notifications');

  /// Diye gaye FCM tokens ko seedha push notification bhejta he. Ye
  /// helper ke andar hi call hota he — bahar se seedha use nahi karna.
  static Future<void> _pushToTokens({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (tokens.isEmpty) return;
    if (_pushEndpoint.startsWith('PASTE_')) {
      debugPrint(
          'NotificationHelper: Apps Script URL not set yet — push skip.');
      return;
    }
    try {
      final res = await http.post(
        Uri.parse(_pushEndpoint),
        // Content-Type 'text/plain' jaan-boojh kar rakha hai — 'application/json'
        // browser se cross-origin request bhejte waqt ek "preflight" (OPTIONS)
        // request trigger karta he, jo Google Apps Script handle nahi karta aur
        // "Failed to fetch" (CORS) error deta he. 'text/plain' ek "simple
        // request" ginta he, isliye preflight skip ho jata he. Apps Script
        // (e.postData.contents) is content ko phir bhi sahi JSON ki tarah
        // parse kar leta he — sirf header ka naam badla he, actual data JSON
        // hi bhej rahe hain.
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'secret': _sharedSecret,
          'tokens': tokens,
          'title': title,
          'body': body,
          'data': data ?? {},
        }),
      );
      debugPrint('Push relay response: ${res.body}');
    } catch (e) {
      debugPrint('Push send failed: $e');
    }
  }

  /// Ek student/teacher ko notification (push + in-app history dono).
  /// [fcmToken] agar maloom ho (jese caller ne already doc fetch kiya ho)
  /// to zaroor pass karein — warna sirf in-app history bane gi, push nahi
  /// jayegi.
  static Future<void> sendToUser({
    required String toId,
    required String toRole, // 'student' | 'teacher'
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
    String? fcmToken,
  }) async {
    await _col.add({
      'toId': toId,
      'toRole': toRole,
      'title': title,
      'body': body,
      'type': type,
      'data': data ?? {},
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (fcmToken != null && fcmToken.isNotEmpty) {
      await _pushToTokens(
          tokens: [fcmToken], title: title, body: body, data: data);
    }
  }

  /// Ek se zyada students/teachers ko ek sath bhejne ke liye — jaise
  /// poori class ko diary notification.
  ///
  /// [targets] har entry {'id': doc id, 'token': fcmToken-ya-null} —
  /// caller ko ye pehle hi students/staff query se mil jata he, is liye
  /// dobara Firestore call karne ki zaroorat nahi.
  static Future<void> sendToMultiple({
    required List<Map<String, String?>> targets,
    required String toRole,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
  }) async {
    if (targets.isEmpty) return;

    // In-app history: Firestore batch ki 500 writes/limit hoti he.
    const chunkSize = 400;
    for (var i = 0; i < targets.length; i += chunkSize) {
      final chunk = targets.sublist(
          i, i + chunkSize > targets.length ? targets.length : i + chunkSize);
      final batch = FirebaseFirestore.instance.batch();
      for (final t in chunk) {
        batch.set(_col.doc(), {
          'toId': t['id'],
          'toRole': toRole,
          'title': title,
          'body': body,
          'type': type,
          'data': data ?? {},
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    // Actual push — sirf un students/teachers ko jinka fcmToken maloom he
    // (jinhon ne kabhi app open/login nahi ki unka token nahi hoga, unko
    // sirf in-app history milegi, jab wo login karenge tab se push milni
    // shuru ho jayegi).
    final tokens = targets
        .map((t) => t['token'])
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toList();

    await _pushToTokens(tokens: tokens, title: title, body: body, data: data);
  }
}
