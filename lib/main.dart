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
import 'school_context.dart';
import 'app_update_checker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Web par IndexedDB persistence off — hot-restart/tab-visibility ke
  // waqt "Database is closing/hidden" jaisi errors se bachne ke liye.
  // Mobile/desktop par normal persistence (offline cache) chalta rehta hai.
  // Ye Firestore ki KISI BHI query se pehle set hona zaroori hai.
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  }

  // App background/terminated ho tab bhi FCM notification handle ho sake,
  // is liye background handler yahan register karna zaroori hai.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Login se pehle hi (Role Selector/Login screen ke liye) school ka
  // apna naam/logo load karne ki koshish karte hain — dekhein
  // SchoolContext.loadPreLoginBranding(). Ye sirf ek best-effort cache
  // hai, is liye await nahi karte — jab bhi mil jaye, SchoolLogo/
  // SchoolNameText widgets khud-b-khud update ho jate hain.
  SchoolContext.loadPreLoginBranding();

  // Windows/macOS/Linux (desktop) ke liye window ka size control karte
  // hain. Web par window_manager support hi nahi karta, aur Android/iOS
  // par bhi iska native implementation exist nahi karta — is liye check
  // sirf actual desktop OS ke liye specific hona chahiye, warna
  // MissingPluginException aata hai.
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
        // App bhar mein kaafi jagah AppBar ka sirf backgroundColor set kiya
        // gaya hai (title/icon color nahi) — Material 3 mein AppBar ka
        // default text/icon color theme ke colorScheme se aata hai jo
        // (teal seed ke sath) dark/black hota hai. Dark background
        // (teal/indigo/purple waghera) ke upar wo text/icon ghayab jaisa
        // (black-on-dark) nazar aata tha — is se poori app mein har AppBar
        // ka title aur action icons hamesha white honge, jab tak koi page
        // khud explicitly kuch aur color na de.
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
      // App jab bhi (cold) open ho, hamesha sab se pehle Role Selector
      // hi dikhana hai — chahe Firebase Auth ke paas pehle se koi
      // persisted session ho (admin/teacher/parent, kisi ka bhi). Pehle
      // yahan authStateChanges StreamBuilder tha jo purani session
      // milte hi seedha us role ke dashboard par bhej deta tha — isi
      // wajah se kabhi parent, kabhi admin, kabhi teacher dashboard
      // bina Role Selector dikhaye seedha khul jata tha. Ab hum har
      // cold start par pehle purani session ko sign out kar dete hain,
      // taake Role Selector hamesha, har waqt, sab se pehli screen ho.
      // (Har role ka apna login page — LoginPage/TeacherLoginPage/
      // ParentLoginPage — login hone ke baad khud seedha sahi dashboard
      // par navigate kar deta hai, is liye yahan _RoleRouter/
      // authStateChanges ki zaroorat nahi rahi.)
      // AppUpdateChecker ab `builder:` mein hai (pehle `home:` mein tha) —
      // is se ye poori app (Navigator ke har route/dashboard) ka ancestor
      // ban jata hai, taake Admin/Parent/Teacher/Staff dashboards mein bhi
      // AppUpdateChecker.of(context)?.checkForUpdate(showResult: true) se
      // manual "Check for Update" button lagaya ja sake.
      navigatorKey: appUpdateNavigatorKey,
      scaffoldMessengerKey: appUpdateScaffoldMessengerKey,
      builder: (context, child) =>
          AppUpdateChecker(child: child ?? const SizedBox.shrink()),
      home: const _SignOutThenRoleSelector(),
    );
  }
}


/// App cold-open hote hi (agar Firebase Auth ke paas koi purani session
/// hai — kisi bhi role/admin/teacher/parent ki) usay sign out karke,
/// hamesha Role Selector dikhata hai. Isi se guarantee hoti hai ke app
/// khulte hi sab se pehli screen "select role" wali hi ho, kabhi seedha
/// kisi dashboard par nahi jaye.
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
