import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'school_context.dart';
import 'app_branding.dart';

/// Current (logged-in) school ka display naam — Settings mein set kiya
/// gaya naam, warna default app naam (dekhein lib/app_branding.dart).
String currentSchoolDisplayName() {
  final name = SchoolContext.schoolName;
  return (name != null && name.isNotEmpty) ? name : kDefaultSchoolName;
}

/// Current (logged-in) school ka WhatsApp/contact number — Settings >
/// WhatsApp Number mein set kiya gaya. Agar school ne abhi tak apna
/// number add nahi kiya, empty string milegi (UI mein caller khud decide
/// kare ke kya dikhana hai — is liye yahan koi ek school ka fixed number
/// hardcode nahi kiya gaya).
String currentSchoolContactNumber() {
  final number = SchoolContext.contactNumber;
  return (number != null && number.isNotEmpty) ? number : '';
}

/// Current (logged-in) school ka contact email — Settings > Contact
/// Email mein set kiya gaya. Jahan bhi app mein school ka email
/// dikhana/use karna ho (Reports, AI chat, letterhead, waghera), wahan
/// hardcoded email ki jagah yehi field use karein. Agar school ne abhi
/// tak email add nahi ki, empty string milegi.
String currentSchoolContactEmail() {
  final email = SchoolContext.contactEmail;
  return (email != null && email.isNotEmpty) ? email : '';
}

/// The current (logged-in) school's principal name — set from Settings >
/// Principal Name. AI Chat gets the principal's name from this same
/// function (no single school's name is hardcoded), so every school can
/// show its own principal name correctly in AI Chat. If the school hasn't
/// added a principal name yet, an empty string is returned.
String currentSchoolPrincipalName() {
  final name = SchoolContext.principalName;
  return (name != null && name.isNotEmpty) ? name : '';
}

/// Kisi bhi UI screen mein current school ka logo dikhane ke liye —
/// Settings > School Logo se upload kiya hua custom logo (agar set hai)
/// warna default bundled logo.
///
/// SchoolContext.listenable ko sunta hai, is liye Settings se logo
/// badalte hi (bina app restart kiye) jahan jahan bhi ye widget use ho
/// raha hai wahan turant naya logo nazar aa jata hai.
class SchoolLogo extends StatelessWidget {
  final double? height;
  final double? width;
  final BoxFit fit;

  const SchoolLogo({
    super.key,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SchoolContext.listenable,
      builder: (context, _, __) {
        final url = SchoolContext.logoUrl;
        if (url != null && url.isNotEmpty) {
          return Image.network(
            url,
            height: height,
            width: width,
            fit: fit,
            errorBuilder: (_, __, ___) => Image.asset(
              kDefaultLogoAsset,
              height: height,
              width: width,
              fit: fit,
            ),
          );
        }
        return Image.asset(
          kDefaultLogoAsset,
          height: height,
          width: width,
          fit: fit,
        );
      },
    );
  }
}

/// Current school ka naam Text widget ke tor par — auto update hota hai
/// jab Settings se naam badle (SchoolContext.listenable).
class SchoolNameText extends StatelessWidget {
  final TextStyle? style;
  final String suffix;
  final TextAlign? textAlign;

  const SchoolNameText({
    super.key,
    this.style,
    this.suffix = '',
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SchoolContext.listenable,
      builder: (context, _, __) => Text(
        '${currentSchoolDisplayName()}$suffix',
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}

/// PDF banate waqt (pw.MemoryImage ke liye) current school ka logo bytes
/// ki shakal mein chahiye hota hai. Custom logo set hai to network se
/// download karta hai, warna bundled default asset se leta hai. Network
/// fail ho jaye to bhi default asset par fallback ho jata hai (PDF kabhi
/// bhi sirf isi wajah se generate hone se nahi rukta).
Future<Uint8List> getSchoolLogoBytes() async {
  final url = SchoolContext.logoUrl;
  if (url != null && url.isNotEmpty) {
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {
      // Neeche default asset par fallback ho jayega.
    }
  }
  final data = await rootBundle.load(kDefaultLogoAsset);
  return data.buffer.asUint8List();
}
