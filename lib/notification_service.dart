import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'school_context.dart';

// ============================================================================
// NotificationService
// ----------------------------------------------------------------------------
// Sets up FCM (Firebase Cloud Messaging), saves/refreshes the device token,
// and handles notifications in all three states: foreground, background,
// and terminated.
//
// SETUP (add to pubspec.yaml):
//   firebase_messaging: ^15.0.0
//   flutter_local_notifications: ^17.0.0
//
// USAGE:
//   1) Inside main.dart, right after Firebase.initializeApp():
//        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
//
//   2) After a teacher logs in (once):
//        await NotificationService().init(uid: staffDocId, role: 'teacher');
//
//   3) After a parent logs in — a parent can have multiple children
//      (siblings), so the token is saved on ALL of those students' docs:
//        await NotificationService().initParent(
//          studentIds: children.map((d) => d.id).toList(),
//        );
//
//   4) On logout:
//        await NotificationService().clearToken();
// ============================================================================

/// Called when an FCM message arrives while the app is in the
/// background/terminated state. MUST be top-level (outside the class),
/// otherwise it won't work.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // When the app is closed, the OS shows the notification automatically —
  // add any extra background logic here (e.g. updating a local cache) if
  // needed.
  debugPrint('Background FCM message: ${message.messageId}');
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance =
      NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'default_channel',
    'General Notifications',
    description:
        'School app notifications (diary, fee, message, attendance, etc.)',
    importance: Importance.high,
  );

  bool _localInitialized = false;
  // How many Firestore docs (student/staff) will have this device's token
  // saved on them — normally just 1, but for a parent it can be more than
  // one (one per sibling).
  List<DocumentReference> _tokenTargets = [];

  /// Call this after a teacher or single-student login.
  /// [onNotificationTap] is optional — use it if tapping a notification
  /// should navigate to a specific screen.
  Future<void> init({
    required String uid,
    required String role, // 'student' | 'teacher'
    void Function(RemoteMessage message)? onNotificationTap,
  }) async {
    final collection = role == 'teacher' ? 'staff' : 'students';
    _tokenTargets = [
      schoolCollection(collection).doc(uid),
    ];
    await _completeInit(onNotificationTap: onNotificationTap);
  }

  /// Call this after a parent logs in — [studentIds] are that parent's
  /// children's (siblings') 'students' collection doc IDs. The token is
  /// saved on ALL of those students' documents so that a notification sent
  /// for any of the children reaches this parent's device.
  Future<void> initParent({
    required List<String> studentIds,
    void Function(RemoteMessage message)? onNotificationTap,
  }) async {
    _tokenTargets = studentIds
        .map((id) =>
            schoolCollection('students').doc(id))
        .toList();
    await _completeInit(onNotificationTap: onNotificationTap);
  }

  Future<void> _completeInit({
    void Function(RemoteMessage message)? onNotificationTap,
  }) async {
    await _setupLocalNotifications();

    // Permission must be requested on iOS and Android 13+.
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }

    // The token can refresh occasionally (app reinstall, OS update, etc.) —
    // Firestore needs to be updated at that point too.
    _messaging.onTokenRefresh.listen(_saveToken);

    // FCM doesn't show a notification on its own while the app is open in
    // the foreground — so we show a local notification manually.
    FirebaseMessaging.onMessage.listen(_showLocalNotification);

    // App was in the background, opened by tapping the notification.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap?.call(message);
    });

    // App was fully closed (terminated), opened by tapping the notification.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      onNotificationTap?.call(initialMessage);
    }
  }

  Future<void> _saveToken(String token) async {
    for (final ref in _tokenTargets) {
      await ref.set({'fcmToken': token}, SetOptions(merge: true));
    }
  }

  /// Clear the old token on logout so that if another user logs in on the
  /// same device, the previous user doesn't keep receiving notifications.
  Future<void> clearToken() async {
    for (final ref in _tokenTargets) {
      await ref
          .update({'fcmToken': FieldValue.delete()}).catchError((_) {});
    }
    _tokenTargets = [];
  }

  Future<void> _setupLocalNotifications() async {
    if (_localInitialized) return;
    _localInitialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _localNotifications.initialize(settings: initSettings);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }
}
