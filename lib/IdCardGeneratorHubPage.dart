import 'package:flutter/material.dart';
import 'student_id_card_page.dart';
import 'teacher_id_card_page.dart';
import 'letterhead_page.dart';
import 'slc_generator.dart';
import 'character_certificate_page.dart';
import 'experience_certificate_page.dart';

class IdCardGeneratorHubPage extends StatelessWidget {
  const IdCardGeneratorHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ID Card & Documents Hub"),
        backgroundColor: Colors.indigo[800],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _hubCard(
              context,
              title: "Student ID Card Generator",
              subtitle: "Search student & generate ID card",
              icon: Icons.school,
              color: Colors.teal,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const StudentIdCardPage()),
                );
              },
            ),
            const SizedBox(height: 20),
            _hubCard(
              context,
              title: "Teacher / Staff ID Card Generator",
              subtitle: "Search staff & generate ID card",
              icon: Icons.co_present,
              color: Colors.deepPurple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const TeacherIdCardPage()),
                );
              },
            ),
            const SizedBox(height: 20),
            _hubCard(
              context,
              title: "Auto Letterhead Generator",
              subtitle: "Create official letters & notices with school header",
              icon: Icons.description,
              color: Colors.blueGrey,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const LetterheadPage()),
                );
              },
            ),
            const SizedBox(height: 20),
            // SLC Generator Card Added Here
            _hubCard(
              context,
              title: "School Leaving Certificate (SLC)",
              subtitle: "Generate student leaving certificates",
              icon: Icons.exit_to_app,
              color: Colors.orange[800]!,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SLCGenerator()),
                );
              },
            ),
            const SizedBox(height: 20),
            _hubCard(
              context,
              title: "Character Certificate",
              subtitle: "Search a student and generate their character certificate",
              icon: Icons.verified,
              color: Colors.indigo[800]!,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const CharacterCertificatePage()),
                );
              },
            ),
            const SizedBox(height: 20),
            _hubCard(
              context,
              title: "Teacher Experience Certificate",
              subtitle: "Search a staff member and generate their experience certificate",
              icon: Icons.workspace_premium,
              color: Colors.teal[800]!,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          const ExperienceCertificatePage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _hubCard(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  const SizedBox(height: 5),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
