import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'school_context.dart';
import 'secrets.dart';

// ============================================================================
// NotificationHelper
// ----------------------------------------------------------------------------
// For any action from admin/teacher's side — diary entry, homework,
// special message, fee reminder, etc. — call this helper.
//
// It does two things:
//   1) Writes a document into the 'push_notifications' collection —
//      used for the app's "Notifications" (bell icon) list. This is a
//      normal Firestore free-tier read/write, no billing needed.
//   2) Sends a push notification directly to the given FCM token(s) —
//      by calling a FREE Google Apps Script web app
//      (apps_script_fcm_relay.gs) instead of a Cloud Function, so the
//      Blaze (paid) plan isn't needed.
//
// SETUP: fill in your Apps Script deployment values in _pushEndpoint
// and _sharedSecret below (the full steps are written in
// apps_script_fcm_relay.gs's comments).
// ============================================================================

class NotificationHelper {
  // Both of these now live in lib/secrets.dart — that file never goes
  // to GitHub (it's in .gitignore), so they're not hardcoded here.
  static const String _pushEndpoint = notificationEndpoint;
  static const String _sharedSecret = notificationSharedSecret;

  static final _col =
      schoolCollection('push_notifications');

  /// Sends a push notification directly to the given FCM tokens. This
  /// is only called from within this helper — don't use it directly
  /// from outside.
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
        // Content-Type is deliberately kept as 'text/plain' —
        // 'application/json' triggers a "preflight" (OPTIONS) request when
        // sending a cross-origin request from the browser, which Google
        // Apps Script doesn't handle and gives a "Failed to fetch" (CORS)
        // error. 'text/plain' counts as a "simple request", so preflight
        // is skipped. Apps Script (e.postData.contents) still parses this
        // content correctly as JSON — only the header name changed, the
        // actual data being sent is still JSON.
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

  /// Sends a notification to one student/teacher (both push + in-app
  /// history). If [fcmToken] is known (e.g. the caller already fetched
  /// the doc), be sure to pass it — otherwise only in-app history is
  /// created, no push is sent.
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

  /// For sending to multiple students/teachers at once — e.g. a diary
  /// notification to an entire class.
  ///
  /// [targets] each entry is {'id': doc id, 'token': fcmToken-or-null} —
  /// the caller already gets this from the students/staff query, so
  /// there's no need for another Firestore call.
  static Future<void> sendToMultiple({
    required List<Map<String, String?>> targets,
    required String toRole,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
  }) async {
    if (targets.isEmpty) return;

    // In-app history: Firestore batch has a 500 writes limit.
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

    // Actual push — only to students/teachers whose fcmToken is known
    // (those who have never opened/logged into the app won't have a
    // token, they'll only get in-app history, and once they log in
    // they'll start getting pushes too).
    final tokens = targets
        .map((t) => t['token'])
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toList();

    await _pushToTokens(tokens: tokens, title: title, body: body, data: data);
  }
}
