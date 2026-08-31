// lib/app_update_checker.dart
//
// Custom auto-update checker for Android (sideload APK) and
// Windows/macOS/Linux (installer). The download now happens fully
// in-app (no longer handed off to the browser/Downloads manager),
// shows real progress percentage, and automatically opens the
// installer/APK as soon as the download finishes so the user only
// has to tap "Install".
//
// Does nothing on web — web always serves the latest deploy from
// Netlify.
//
// UPDATED BEHAVIOUR:
// - An automatic check (on app start / on resume) only pops the
//   "Update Available" dialog once per release, then stays quiet for
//   kUpdatePromptCooldown (currently 6 hours) if the user tapped
//   "Later" — instead of showing it again on every single resume.
// - A manual check (the "Check for Update" button, showResult: true)
//   always shows the result immediately, ignoring that cooldown.
// - force_update releases always show, ignoring the cooldown too.
// - Once the installed version actually catches up to the published
//   one, the stored cooldown record is cleared automatically, so the
//   *next* release starts its own fresh cooldown.
// - Uses shared_preferences (already a dependency in this project —
//   see login_page.dart / pay_fee_page.dart) to remember what was
//   last prompted and when.
//
// ==========================================================================
// SETUP (do this first, or the build will fail)
// ==========================================================================
//
// 1) In pubspec.yaml -> dependencies, add:
//      dio: ^5.7.0
//      (package_info_plus, path_provider, and open_file are already
//      in this project)
//
//    Then run: flutter pub get
//
// 2) In android/app/src/main/AndroidManifest.xml, inside the
//    <manifest> tag (outside/above <application>), add:
//
//      <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
//
//    (INTERNET permission should already be present:
//      <uses-permission android:name="android.permission.INTERNET" /> )
//
//    open_file registers its own FileProvider automatically, so you
//    do NOT need to add a <provider> entry yourself.
//
// 3) In main.dart, wrap AppUpdateChecker around MaterialApp's
//    `builder:` instead of `home:` — this makes it an ANCESTOR of the
//    whole app (every route), not just the first screen, so any
//    dashboard (Admin/Parent/Teacher/Staff) can reach it via
//    `AppUpdateChecker.of(context)`. Example:
//
//      return MaterialApp(
//        // ... existing theme/title/etc ...
//        builder: (context, child) =>
//            AppUpdateChecker(child: child ?? const SizedBox.shrink()),
//        home: const _SignOutThenRoleSelector(),
//      );
//
//    (Previously it was `home: AppUpdateChecker(child: ...)` — replace
//    that with the `builder:` pattern above. `home:` stays as normal.)
//
// 4) To show a manual "Check for Update" button/menu item on any
//    dashboard (Admin/Parent/Teacher):
//
//      IconButton(
//        icon: const Icon(Icons.system_update_alt),
//        tooltip: 'Check for Update',
//        onPressed: () =>
//            AppUpdateChecker.of(context)?.checkForUpdate(showResult: true),
//      )
//
//    Passing `showResult: true` also shows a message like "you're
//    already on the latest version" when there's no update, so the
//    button doesn't feel like it's doing nothing.
//
// ==========================================================================
// For every new release, only version.json on Netlify needs updating —
// no code changes required.
// ==========================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// URL of the version.json file hosted on Netlify.
const String kVersionCheckUrl =
    'https://sttechnology.netlify.app/version.json';

/// How long to wait before re-showing the "Update Available" dialog to a
/// user who already saw it for the current latest version and chose
/// "Later". Without this, an automatic check on every app start/resume
/// would pop the same dialog up again and again. Ignored for
/// force_update releases, which must always be shown.
const Duration kUpdatePromptCooldown = Duration(hours: 6);

/// SharedPreferences keys used to remember what was last shown, so the
/// dialog doesn't repeat on every launch/resume.
const String kPrefLastPromptedVersion = 'app_update_last_prompted_version';
const String kPrefLastPromptedAtMs = 'app_update_last_prompted_at_ms';

/// Remembers which version's installer was already downloaded and
/// launched. The running app process still reports the OLD version
/// (PackageInfo) until it is actually closed and reopened after the
/// install finishes — so without this, pressing "Update" again in that
/// window would start the whole download over, even though the update
/// has already been installed/launched. See the check in
/// checkForUpdate() below.
const String kPrefLastInstallLaunchedVersion =
    'app_update_last_install_launched_version';
const String kPrefLastInstallLaunchedAtMs =
    'app_update_last_install_launched_at_ms';

/// How long the "installer for this version was already launched" skip
/// lasts. Android's installer sometimes fails silently (e.g. "conflicts
/// with an existing package" when a release APK is signed with a
/// different key than what's currently installed) — if that happens,
/// PackageInfo will NEVER catch up to latestVersion, so this record must
/// not block re-downloading forever. After this window, a repeat "Update"
/// tap is treated as a genuine retry instead of an accidental double-tap.
const Duration kInstallLaunchedGracePeriod = Duration(minutes: 3);

/// Tracks how many times the installer has been launched for the SAME
/// [latestVersion] in a row. Android enforces signature matching at the
/// OS level — no app code (ours or anyone else's) can make it accept an
/// install over a differently-signed existing package; that decision
/// happens outside the app entirely. But if the SAME version's installer
/// keeps being launched attempt after attempt without PackageInfo ever
/// catching up, that's a strong signal the install is failing every time
/// (most often "conflicts with an existing package" — a leftover copy
/// signed with a different key, e.g. a debug build, or a cloned/"Dual
/// Apps" copy some phones keep in a hidden second profile). After
/// kInstallConflictHelpThreshold attempts, checkForUpdate() shows
/// targeted troubleshooting instead of just re-opening the same dialog.
const String kPrefInstallAttemptVersion = 'app_update_install_attempt_version';
const String kPrefInstallAttemptCount = 'app_update_install_attempt_count';
const int kInstallConflictHelpThreshold = 2;

/// Attach these to MaterialApp (navigatorKey / scaffoldMessengerKey) in
/// main.dart. AppUpdateChecker lives ABOVE the Navigator (it wraps
/// MaterialApp's `builder:`), so its own BuildContext is not a descendant
/// of the Navigator — using it directly with showDialog/ScaffoldMessenger
/// throws "context does not include a Navigator". These global keys give
/// us a context that IS inside the Navigator/Scaffold tree, regardless of
/// where AppUpdateChecker itself sits.
final GlobalKey<NavigatorState> appUpdateNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appUpdateScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class AppUpdateChecker extends StatefulWidget {
  final Widget child;
  const AppUpdateChecker({super.key, required this.child});

  /// Finds the nearest AppUpdateChecker state from any screen — used to
  /// build a manual "Check for Update" button. Only works when
  /// AppUpdateChecker is wrapped in MaterialApp's `builder:` (see setup
  /// step 3 above); otherwise this returns null.
  static AppUpdateCheckerState? of(BuildContext context) {
    return context.findAncestorStateOfType<AppUpdateCheckerState>();
  }

  @override
  State<AppUpdateChecker> createState() => AppUpdateCheckerState();
}

class AppUpdateCheckerState extends State<AppUpdateChecker>
    with WidgetsBindingObserver {
  bool _dialogOpen = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Also check when the app comes back to the foreground — so even if
    // the app is never fully restarted (just minimized/resumed), the
    // update prompt still reaches the user.
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      checkForUpdate();
    }
  }

  /// Installed app version (e.g. "1.0.0") — for showing in Settings/About
  /// next to a "Check for Update" button. Safe to call anytime; on web it
  /// still returns PackageInfo's version (just not used for update checks).
  Future<String> getInstalledVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// When [showResult] is true, also shows an "already up to date" /
  /// "check failed" message — useful for a manual button.
  Future<void> checkForUpdate({bool showResult = false}) async {
    debugPrint('[UpdateChecker] checkForUpdate called. kIsWeb=$kIsWeb, _dialogOpen=$_dialogOpen, _checking=$_checking, showResult=$showResult');
    if (kIsWeb) {
      debugPrint('[UpdateChecker] Early return — running on web.');
      return;
    }
    // A manual check (showResult: true, e.g. from a dashboard button) always
    // runs — it should never be silently swallowed just because a previous
    // automatic check left _dialogOpen/_checking stuck true (e.g. the app
    // was backgrounded while a dialog was open, or a hot reload happened
    // mid-check). Only automatic checks (app start / resume) skip while one
    // is already in progress, to avoid stacking duplicate dialogs.
    if (!showResult && (_dialogOpen || _checking)) {
      debugPrint('[UpdateChecker] Early return — automatic check skipped, already checking/dialog open.');
      return;
    }
    if (showResult && (_dialogOpen || _checking)) {
      debugPrint('[UpdateChecker] Manual check proceeding despite _dialogOpen/_checking being stuck true — resetting stale flags.');
    }
    _dialogOpen = false;
    _checking = true;
    // Immediate visible feedback for a manual check — a release build has
    // no visible debugPrint output, so without this the button appears to
    // "do nothing" for the whole duration of the network call (up to the
    // 8-second timeout below), or forever if AppUpdateChecker.of(context)
    // ever returned null at the call site. This confirms to the user that
    // the tap was registered and a check is actually in progress.
    if (showResult) _snack('Checking for updates…');
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "1.4.2"
      debugPrint('[UpdateChecker] Installed app version: $currentVersion');

      // Cache-busting query param + no-cache headers: Netlify's CDN can
      // keep serving an old cached copy of version.json for a while after
      // a new one is deployed. Without this, a device can compare the
      // freshly-installed app against a stale response and be told an
      // update is available again even though it just updated.
      final versionCheckUri = Uri.parse(kVersionCheckUrl).replace(
        queryParameters: {
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final res = await http.get(
        versionCheckUri,
        headers: const {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      ).timeout(const Duration(seconds: 8));
      debugPrint('[UpdateChecker] version.json fetch status: ${res.statusCode}');
      if (res.statusCode != 200) {
        debugPrint('[UpdateChecker] Non-200 response, aborting.');
        if (showResult) _snack('Update check failed. Please try again.');
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      final String platformKey = Platform.isAndroid
          ? 'android'
          : Platform.isWindows
              ? 'windows'
              : Platform.isMacOS
                  ? 'macos'
                  : Platform.isLinux
                      ? 'linux'
                      : '';
      debugPrint('[UpdateChecker] Detected platformKey: "$platformKey"');
      if (platformKey.isEmpty || data[platformKey] == null) {
        debugPrint('[UpdateChecker] No data for this platform in version.json, aborting.');
        return;
      }

      final platformData = data[platformKey] as Map<String, dynamic>;
      final String latestVersion = platformData['latest_version'] ?? '';
      final String downloadUrl = platformData['download_url'] ?? '';
      final String notes = platformData['notes'] ?? '';
      final bool forceUpdate = platformData['force_update'] == true;

      debugPrint('[UpdateChecker] latestVersion="$latestVersion", downloadUrl="$downloadUrl"');
      if (latestVersion.isEmpty || downloadUrl.isEmpty) {
        debugPrint('[UpdateChecker] Missing latest_version or download_url in version.json, aborting.');
        return;
      }

      final bool isNewer = _isNewer(latestVersion, currentVersion);
      debugPrint('[UpdateChecker] Is $latestVersion newer than $currentVersion? $isNewer');
      if (isNewer) {
        if (!mounted) return;

        // The installer for this exact version was already downloaded
        // and launched in a previous check — the app just hasn't been
        // restarted yet to pick it up, so PackageInfo still reports the
        // old version. Don't start a fresh download for the same
        // release; tell the user to finish installing/restart instead.
        // BUT: only for a short grace period. If the install actually
        // failed (e.g. Android's "conflicts with an existing package"
        // error, which usually means this APK was signed with a
        // different key than the one currently on the device),
        // PackageInfo will never catch up — so after the grace period
        // this is treated as a real retry instead of staying stuck
        // forever telling the user "already downloaded".
        final prefs = await SharedPreferences.getInstance();
        final alreadyLaunchedVersion =
            prefs.getString(kPrefLastInstallLaunchedVersion);
        final alreadyLaunchedAtMs =
            prefs.getInt(kPrefLastInstallLaunchedAtMs);
        if (alreadyLaunchedVersion == latestVersion &&
            alreadyLaunchedAtMs != null &&
            DateTime.now().difference(
                    DateTime.fromMillisecondsSinceEpoch(alreadyLaunchedAtMs)) <
                kInstallLaunchedGracePeriod) {
          debugPrint('[UpdateChecker] Installer for $latestVersion was already '
              'launched — skipping re-download (within grace period).');
          if (showResult) {
            _snack('Update to $latestVersion has already been downloaded — '
                'please finish installing it and restart the app.');
          }
          return;
        }

        // Same version's installer has already failed to actually take
        // effect kInstallConflictHelpThreshold times in a row — instead
        // of showing the same "Update Available" dialog again (which
        // would just repeat the same failing installer), show targeted
        // troubleshooting for the install-conflict problem.
        final priorAttemptVersion = prefs.getString(kPrefInstallAttemptVersion);
        final priorAttemptCount = prefs.getInt(kPrefInstallAttemptCount) ?? 0;
        if (priorAttemptVersion == latestVersion &&
            priorAttemptCount >= kInstallConflictHelpThreshold) {
          final bool shouldShowHelp = showResult ||
              forceUpdate ||
              await _shouldPromptAutomatically(latestVersion);
          if (shouldShowHelp) {
            await _rememberPrompted(latestVersion);
            if (!mounted) return;
            // The "conflicts with an existing package" failure mode (and
            // its fix — uninstall/check for App Clone/Dual Apps/restart)
            // is specific to how Android enforces signing-key matching.
            // Windows/macOS/Linux installers fail for different reasons
            // (permissions, an installer window already open, antivirus/
            // SmartScreen, a locked file, etc.), so they get their own
            // troubleshooting text instead of the Android-specific one.
            if (Platform.isAndroid) {
              _showInstallConflictHelpDialogAndroid(
                latestVersion: latestVersion,
                downloadUrl: downloadUrl,
              );
            } else {
              _showInstallConflictHelpDialogDesktop(
                latestVersion: latestVersion,
                downloadUrl: downloadUrl,
              );
            }
          }
          return;
        }

        // A manual check (showResult: true) or a forced update always shows
        // the dialog. An automatic check (app start/resume) only shows it
        // again if we haven't already prompted for this exact version
        // recently — otherwise a "Later" tap would just make the dialog
        // reappear every time the app is opened/resumed instead of leaving
        // the user alone for a while.
        final bool shouldShow = showResult ||
            forceUpdate ||
            await _shouldPromptAutomatically(latestVersion);
        if (!shouldShow) {
          debugPrint('[UpdateChecker] Skipping dialog — already prompted for '
              '$latestVersion within the last ${kUpdatePromptCooldown.inHours}h.');
          return;
        }

        await _rememberPrompted(latestVersion);
        if (!mounted) return;
        _showUpdateDialog(
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          notes: notes,
          forceUpdate: forceUpdate,
        );
      } else {
        // Not newer — either already updated or nothing published yet.
        // Clear any stale "last prompted"/"last installer launched"
        // records so a future real update starts fresh instead of
        // inheriting old state.
        await _clearPromptedRecord();
        if (showResult) {
          _snack('You are already on the latest version ($currentVersion) — updated.');
        }
      }
    } catch (e, st) {
      debugPrint('[UpdateChecker] EXCEPTION: $e');
      debugPrint('[UpdateChecker] Stack: $st');
      if (showResult) {
        _snack('Update check failed — please check your internet connection.');
      }
      // Silent fail on background/auto checks — app keeps running normally.
    } finally {
      _checking = false;
    }
  }

  void _snack(String msg) {
    appUpdateScaffoldMessengerKey.currentState
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  /// True if an automatic check should still pop the dialog for
  /// [latestVersion] — i.e. either we've never prompted for this version
  /// before, or we did but the cooldown window has since passed.
  Future<bool> _shouldPromptAutomatically(String latestVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final lastVersion = prefs.getString(kPrefLastPromptedVersion);
    final lastAtMs = prefs.getInt(kPrefLastPromptedAtMs);

    if (lastVersion != latestVersion || lastAtMs == null) {
      // Either a newer release than the one we last prompted for, or we've
      // never prompted at all — always show it.
      return true;
    }

    final lastAt = DateTime.fromMillisecondsSinceEpoch(lastAtMs);
    final elapsed = DateTime.now().difference(lastAt);
    return elapsed >= kUpdatePromptCooldown;
  }

  /// Records that we just prompted the user for [latestVersion] right now,
  /// so the cooldown in [_shouldPromptAutomatically] has something to
  /// measure against.
  Future<void> _rememberPrompted(String latestVersion) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefLastPromptedVersion, latestVersion);
    await prefs.setInt(
        kPrefLastPromptedAtMs, DateTime.now().millisecondsSinceEpoch);
  }

  /// Clears the "last prompted" record — called once the installed version
  /// catches up, so a future release doesn't inherit an old cooldown.
  Future<void> _clearPromptedRecord() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefLastPromptedVersion);
    await prefs.remove(kPrefLastPromptedAtMs);
    await prefs.remove(kPrefLastInstallLaunchedVersion);
    await prefs.remove(kPrefLastInstallLaunchedAtMs);
    await prefs.remove(kPrefInstallAttemptVersion);
    await prefs.remove(kPrefInstallAttemptCount);
  }

  /// Simple semantic-version comparison, e.g. "1.4.10" vs "1.4.2". Also
  /// strips any build-metadata suffix (e.g. "1.0.1+3" -> "1.0.1") before
  /// comparing, since some platforms can report the build number appended
  /// to the version string.
  bool _isNewer(String latest, String current) {
    final cleanLatest = latest.split('+').first;
    final cleanCurrent = current.split('+').first;
    final l = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = l.length > c.length ? l.length : c.length;
    for (var i = 0; i < len; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv != cv) return lv > cv;
    }
    return false;
  }

  void _showUpdateDialog({
    required String latestVersion,
    required String downloadUrl,
    required String notes,
    required bool forceUpdate,
  }) {
    final dialogContext = appUpdateNavigatorKey.currentContext;
    if (dialogContext == null) {
      debugPrint('[UpdateChecker] Cannot show dialog — navigatorKey has no context yet.');
      return;
    }
    _dialogOpen = true;
    showDialog(
      context: dialogContext,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => PopScope(
        canPop: !forceUpdate,
        child: AlertDialog(
          title: const Text('Update Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version $latestVersion is now available.'),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(notes, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
          actions: [
            if (!forceUpdate)
              TextButton(
                onPressed: () {
                  _dialogOpen = false;
                  Navigator.of(ctx).pop();
                },
                child: const Text('Later'),
              ),
            ElevatedButton(
              onPressed: () {
                _dialogOpen = false;
                Navigator.of(ctx).pop();
                _downloadAndInstall(downloadUrl, latestVersion);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    ).then((_) => _dialogOpen = false);
  }

  /// Shown instead of the plain "Update Available" dialog once the same
  /// version's installer has been launched kInstallConflictHelpThreshold
  /// times without the app ever actually updating. Explains WHY this
  /// happens (Android blocks installing over a differently-signed
  /// existing package — no app can override that, by design, for
  /// security) and what actually fixes it, plus a manual fallback.
  void _showInstallConflictHelpDialogAndroid({
    required String latestVersion,
    required String downloadUrl,
  }) {
    final dialogContext = appUpdateNavigatorKey.currentContext;
    if (dialogContext == null) {
      debugPrint('[UpdateChecker] Cannot show install-conflict dialog — navigatorKey has no context yet.');
      return;
    }
    _dialogOpen = true;
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Installation Keeps Failing'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The update download keeps completing, but the install itself '
                'is failing — usually shown as "App not installed as package '
                'conflicts with an existing package".',
              ),
              SizedBox(height: 10),
              Text(
                'This is enforced by Android itself, not by this app: it '
                'refuses to install an update over an existing copy that was '
                'signed with a different key, and no app can override that. '
                'It usually means a leftover copy of this app is still on '
                'the phone somewhere. Please try, in order:',
              ),
              SizedBox(height: 10),
              Text('1. Settings > Apps > find this app > Uninstall (if it still shows up at all).'),
              SizedBox(height: 4),
              Text('2. Check for an "App Clone" / "Dual Apps" / "Parallel Apps" feature in phone Settings — some phones keep a second hidden copy there that a normal uninstall does not remove. Turn that off/remove it too.'),
              SizedBox(height: 4),
              Text('3. Restart the phone.'),
              SizedBox(height: 4),
              Text('4. Then try installing again.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _dialogOpen = false;
              Navigator.of(ctx).pop();
            },
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: downloadUrl));
              if (ctx.mounted) {
                _snack('Download link copied — you can open it in a browser '
                    'or file manager to install manually.');
              }
            },
            child: const Text('Copy Download Link'),
          ),
          ElevatedButton(
            onPressed: () {
              _dialogOpen = false;
              Navigator.of(ctx).pop();
              _downloadAndInstall(downloadUrl, latestVersion);
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    ).then((_) => _dialogOpen = false);
  }

  /// Desktop (Windows/macOS/Linux) equivalent of the Android install-conflict
  /// dialog above. Desktop installers fail repeatedly for different reasons
  /// than Android's signing-key enforcement — most commonly the installer/
  /// app is already running (file locked), it needs admin/elevated rights,
  /// or antivirus/SmartScreen is quarantining or blocking the download —
  /// so this shows guidance relevant to those instead of the Android text.
  void _showInstallConflictHelpDialogDesktop({
    required String latestVersion,
    required String downloadUrl,
  }) {
    final dialogContext = appUpdateNavigatorKey.currentContext;
    if (dialogContext == null) {
      debugPrint('[UpdateChecker] Cannot show install-conflict dialog — navigatorKey has no context yet.');
      return;
    }
    _dialogOpen = true;
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Installation Keeps Failing'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The update download keeps completing, but the install '
                'itself does not seem to be taking effect. Please try, in '
                'order:',
              ),
              SizedBox(height: 10),
              Text('1. Fully close the app (including from the system tray/taskbar) before installing, so the installer isn\'t trying to replace files that are still in use.'),
              SizedBox(height: 4),
              Text('2. Right-click the installer and choose "Run as administrator" (Windows) or approve the install when prompted (macOS/Linux).'),
              SizedBox(height: 4),
              Text('3. Check if antivirus/Windows SmartScreen quarantined or blocked the downloaded file, and allow it if so.'),
              SizedBox(height: 4),
              Text('4. Restart the computer, then try installing again.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _dialogOpen = false;
              Navigator.of(ctx).pop();
            },
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: downloadUrl));
              if (ctx.mounted) {
                _snack('Download link copied — you can open it in a browser '
                    'or file manager to install manually.');
              }
            },
            child: const Text('Copy Download Link'),
          ),
          ElevatedButton(
            onPressed: () {
              _dialogOpen = false;
              Navigator.of(ctx).pop();
              _downloadAndInstall(downloadUrl, latestVersion);
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    ).then((_) => _dialogOpen = false);
  }

  // ==========================================================================
  // In-app download (dio) + real progress + auto-install trigger (open_filex)
  // ==========================================================================

  Future<void> _downloadAndInstall(String url, String version) async {
    // Track repeated attempts for this same version — see
    // kPrefInstallAttemptCount above. Counted from the moment "Update"/
    // "Try Again" is tapped, regardless of whether the install itself
    // ends up succeeding (we have no way to know that — Android doesn't
    // report install success/failure back to the launching app).
    final attemptPrefs = await SharedPreferences.getInstance();
    final priorAttemptVersion =
        attemptPrefs.getString(kPrefInstallAttemptVersion);
    final priorAttemptCount =
        priorAttemptVersion == version
            ? (attemptPrefs.getInt(kPrefInstallAttemptCount) ?? 0)
            : 0;
    await attemptPrefs.setString(kPrefInstallAttemptVersion, version);
    await attemptPrefs.setInt(
        kPrefInstallAttemptCount, priorAttemptCount + 1);

    final progress = ValueNotifier<double>(0); // negative = indeterminate
    final cancelToken = CancelToken();
    bool closedByUser = false;

    // Progress dialog — the user stays inside the app until the download
    // finishes, so the "stuck at 100% in notification tray" problem goes
    // away, because the installer opens automatically right after.
    final progressDialogContext = appUpdateNavigatorKey.currentContext;
    if (progressDialogContext == null) {
      debugPrint('[UpdateChecker] Cannot show download dialog — navigatorKey has no context yet.');
      return;
    }
    showDialog(
      context: progressDialogContext,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Downloading update…'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: value < 0 ? null : value),
                const SizedBox(height: 12),
                Text(value < 0
                    ? 'Starting…'
                    : '${(value * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                closedByUser = true;
                cancelToken.cancel('User cancelled');
                Navigator.of(ctx).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    try {
      final savePath = await _resolveSavePath(url, version);

      // Delete any old/partial download — it could be corrupt and cause
      // the same "stuck" symptom.
      final existing = File(savePath);
      if (await existing.exists()) {
        await existing.delete();
      }

      await Dio().download(
        url,
        savePath,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          followRedirects: true,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progress.value = received / total;
          }
        },
      );

      if (!closedByUser && mounted) {
        appUpdateNavigatorKey.currentState?.pop(); // close progress dialog
      }

      // Download complete — open the installer/APK so the user can go
      // straight to "Install".
      final result = await OpenFile.open(savePath);
      if (result.type == ResultType.done) {
        // Remember that this exact version's installer was launched, so
        // a repeat "Update" tap right away doesn't trigger another full
        // download — see the check in checkForUpdate(). This only holds
        // for kInstallLaunchedGracePeriod; if the install actually failed
        // (e.g. a signing-key conflict) a later retry is allowed again.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kPrefLastInstallLaunchedVersion, version);
        await prefs.setInt(
            kPrefLastInstallLaunchedAtMs, DateTime.now().millisecondsSinceEpoch);
      } else if (mounted) {
        _snack(
          'Download finished but the install screen could not open '
          'automatically (${result.message}). The file is saved at: '
          '$savePath — please open it manually to install.',
        );
      }
    } on DioException catch (e) {
      if (!closedByUser) {
        appUpdateNavigatorKey.currentState?.pop();
      }
      if (e.type != DioExceptionType.cancel) {
        _snack('Download failed — please check your internet connection and try again.');
      }
    } catch (e) {
      if (!closedByUser) {
        appUpdateNavigatorKey.currentState?.pop();
      }
      _snack('Something went wrong: $e');
    }
  }

  /// On Android, uses app-specific external storage (no runtime
  /// permission needed, works on Android 10+). On desktop
  /// (Windows/macOS/Linux), uses the Downloads folder.
  Future<String> _resolveSavePath(String url, String version) async {
    final fileName = _fileNameFromUrl(url, version);
    Directory dir;
    if (Platform.isAndroid) {
      dir = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } else {
      dir = (await getDownloadsDirectory()) ??
          await getApplicationDocumentsDirectory();
    }
    return '${dir.path}/$fileName';
  }

  String _fileNameFromUrl(String url, String version) {
    final uri = Uri.tryParse(url);
    final last = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : '';
    if (last.isNotEmpty && last.contains('.')) return last;
    // Fallback: guess the extension based on platform.
    final ext = Platform.isAndroid
        ? 'apk'
        : Platform.isWindows
            ? 'exe'
            : Platform.isMacOS
                ? 'dmg'
                : 'AppImage';
    return 'update-$version.$ext';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
