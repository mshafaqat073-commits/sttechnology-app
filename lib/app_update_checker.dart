// lib/app_update_checker.dart
//
// Android (sideload APK) aur Windows (installer/exe) ke liye "custom"
// auto-update checker. Web ke liye ye kuch nahi karta — web hamesha
// Netlify par latest deploy hi serve karta hai (reload/browser refresh
// se naya version mil jata hai), isliye web ko is check ki zaroorat
// nahi.
//
// Kaam kaise karta hai:
// 1. App start hote hi (ya jab bhi chaho) ye ek chhota JSON file fetch
//    karta hai jo Netlify par host hoga — e.g.
//    https://sttechnology.netlify.app/version.json
// 2. Us JSON mein latest version number + download link hota hai.
// 3. App apna current version (pubspec.yaml ka `version:`) us se
//    compare karta hai — agar naya version available hai to ek dialog
//    dikhata hai jisme "Update" button download link khol deta hai.
//
// SETUP (do steps):
//   1) pubspec.yaml mein add karo:
//        package_info_plus: ^8.0.0
//      (http aur url_launcher already project mein hain)
//
//   2) main.dart mein, MaterialApp ke home widget ko is se wrap karo:
//        home: AppUpdateChecker(child: const _SignOutThenRoleSelector()),
//
// Har naye release par sirf Netlify par version.json update karna
// hota hai (repo ke `web/version.json` ya kisi bhi publish folder mein
// rakh do, taake wo deploy ke sath hi live ho jaye) — code mein kuch
// badalne ki zaroorat nahi.

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Netlify site ka version.json URL — apna asal Netlify domain yahan
/// daalo (ya custom domain ho to wo).
const String kVersionCheckUrl =
    'https://sttechnology.netlify.app/version.json';

class AppUpdateChecker extends StatefulWidget {
  final Widget child;
  const AppUpdateChecker({super.key, required this.child});

  @override
  State<AppUpdateChecker> createState() => _AppUpdateCheckerState();
}

class _AppUpdateCheckerState extends State<AppUpdateChecker> {
  @override
  void initState() {
    super.initState();
    // Web par kuch check nahi karna — web khud hamesha latest hota hai.
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "1.4.2"

      final res = await http
          .get(Uri.parse(kVersionCheckUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // Platform ke hisaab se sahi section uthao.
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
      }
    } catch (_) {
      // Update check fail ho (no internet, JSON missing waghera) to
      // chup-chap ignore karo — app normal chalti rahe.
    }
  }

  /// Simple "1.4.10" vs "1.4.2" jaisa semantic-version comparison.
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
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Later'),
              ),
            ElevatedButton(
              onPressed: () async {
                final uri = Uri.parse(downloadUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (!forceUpdate && ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
