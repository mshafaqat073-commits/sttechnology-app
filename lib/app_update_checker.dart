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
// ==========================================================================
// SETUP (do this first, or the build will fail)
// ==========================================================================
//
// 1) In pubspec.yaml -> dependencies, add:
//      dio: ^5.7.0
//      open_filex: ^4.5.0
//      package_info_plus: ^8.0.0
//      path_provider: ^2.1.0   (already in this project)
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
//    open_filex registers its own FileProvider automatically, so you
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
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// URL of the version.json file hosted on Netlify.
const String kVersionCheckUrl =
    'https://sttechnology.netlify.app/version.json';

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

  /// When [showResult] is true, also shows an "already up to date" /
  /// "check failed" message — useful for a manual button.
  Future<void> checkForUpdate({bool showResult = false}) async {
    if (kIsWeb || _dialogOpen || _checking) return;
    _checking = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "1.4.2"

      final res = await http
          .get(Uri.parse(kVersionCheckUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
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
      if (platformKey.isEmpty || data[platformKey] == null) return;

      final platformData = data[platformKey] as Map<String, dynamic>;
      final String latestVersion = platformData['latest_version'] ?? '';
      final String downloadUrl = platformData['download_url'] ?? '';
      final String notes = platformData['notes'] ?? '';
      final bool forceUpdate = platformData['force_update'] == true;

      if (latestVersion.isEmpty || downloadUrl.isEmpty) return;

      if (_isNewer(latestVersion, currentVersion)) {
        if (!mounted) return;
        _showUpdateDialog(
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          notes: notes,
          forceUpdate: forceUpdate,
        );
      } else if (showResult) {
        _snack('You are already on the latest version ($currentVersion).');
      }
    } catch (_) {
      if (showResult) {
        _snack('Update check failed — please check your internet connection.');
      }
      // Silent fail on background/auto checks — app keeps running normally.
    } finally {
      _checking = false;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Simple semantic-version comparison, e.g. "1.4.10" vs "1.4.2".
  bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
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
    _dialogOpen = true;
    showDialog(
      context: context,
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

  // ==========================================================================
  // In-app download (dio) + real progress + auto-install trigger (open_filex)
  // ==========================================================================

  Future<void> _downloadAndInstall(String url, String version) async {
    final progress = ValueNotifier<double>(0); // negative = indeterminate
    final cancelToken = CancelToken();
    bool closedByUser = false;

    // Progress dialog — the user stays inside the app until the download
    // finishes, so the "stuck at 100% in notification tray" problem goes
    // away, because the installer opens automatically right after.
    showDialog(
      context: context,
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
        Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
      }

      // Download complete — open the installer/APK so the user can go
      // straight to "Install".
      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done && mounted) {
        _snack(
          'Download finished but the install screen could not open '
          'automatically (${result.message}). The file is saved at: '
          '$savePath — please open it manually to install.',
        );
      }
    } on DioException catch (e) {
      if (!closedByUser && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (e.type != DioExceptionType.cancel && mounted) {
        _snack('Download failed — please check your internet connection and try again.');
      }
    } catch (e) {
      if (!closedByUser && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) _snack('Something went wrong: $e');
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
