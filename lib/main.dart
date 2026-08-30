import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:window_manager/window_manager.dart';
import 'role_selector_page.dart';
import 'firebase_options.dart';
import 'notification_service.dart';
import 'app_update_checker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // IndexedDB persistence off on Web — to avoid errors like "Database
  // is closing/hidden" during hot-restart/tab-visibility changes.
  // Normal persistence (offline cache) still runs on Mobile/desktop.
  // This must be set before ANY Firestore query.
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  }

  // So FCM notifications are handled even when the app is
  // backgrounded/terminated, the background handler must be
  // registered here.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // NOTE: Pre-login branding auto-load has been intentionally removed.
  // The Role Selector always shows the generic app name/logo
  // (see lib/app_branding.dart) until an actual login happens. The
  // Admin Login screen separately shows the LAST logged-in school's
  // own logo, cached locally — see SchoolContext.loadLastKnownLogo()
  // and lib/login_page.dart.

  // Control the window size for Windows/macOS/Linux (desktop). Web
  // doesn't support window_manager at all, and Android/iOS don't have
  // a native implementation for it either — so the check must be
  // specific to an actual desktop OS, otherwise a
  // MissingPluginException occurs.
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 800),
      center: true,
      minimumSize: Size(800, 600),
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
        // In many places throughout the app, only the AppBar's
        // backgroundColor is set (not the title/icon color) — in
        // Material 3, AppBar's default text/icon color comes from the
        // theme's colorScheme, which (with a teal seed) is dark/black.
        // On a dark background (teal/indigo/purple, etc.) that text/icon
        // looked almost invisible (black-on-dark) — this makes every
        // AppBar's title and action icons white throughout the app,
        // unless a page explicitly sets some other color itself.
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.teal[800],
          foregroundColor: Colors.white,
          elevation: 2,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // Whenever the app is (cold) opened, the Role Selector should
      // always be shown first — even if Firebase Auth already has a
      // persisted session (of any role, admin/teacher/parent). This
      // used to have an authStateChanges StreamBuilder that sent the
      // user straight to that role's dashboard as soon as an old
      // session was found — that's why sometimes a parent, sometimes
      // an admin, sometimes a teacher dashboard would open directly
      // without showing the Role Selector. Now, on every cold start, the
      // old session is signed out first, so the Role Selector is always,
      // every time, the very first screen. (Each role's own login page
      // — LoginPage/TeacherLoginPage/ParentLoginPage — navigates
      // straight to the correct dashboard itself after login, so
      // _RoleRouter/authStateChanges is no longer needed here.)
      // AppUpdateChecker is now in `builder:` (previously it was in
      // `home:`) — this makes it an ancestor of the whole app (every
      // route/dashboard under the Navigator), so a manual "Check for
      // Update" button can also be added in the Admin/Parent/Teacher/
      // Staff dashboards via
      // AppUpdateChecker.of(context)?.checkForUpdate(showResult: true).
      builder: (context, child) =>
          AppUpdateChecker(child: child ?? const SizedBox.shrink()),
      home: const _SignOutThenRoleSelector(),
    );
  }
}


/// As soon as the app cold-opens (if Firebase Auth has an old session
/// — of any role, admin/teacher/parent), signs it out and always shows
/// the Role Selector. This guarantees that the very first screen when
/// the app opens is always "select role", never straight to some
/// dashboard.
class _SignOutThenRoleSelector extends StatefulWidget {
  const _SignOutThenRoleSelector();

  @override
  State<_SignOutThenRoleSelector> createState() =>
      _SignOutThenRoleSelectorState();
}

class _SignOutThenRoleSelectorState extends State<_SignOutThenRoleSelector> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _signOutIfNeeded();
  }

  Future<void> _signOutIfNeeded() async {
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      debugPrint('Cold-start sign out failed: $e');
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return const RoleSelectorPage();
  }
}
