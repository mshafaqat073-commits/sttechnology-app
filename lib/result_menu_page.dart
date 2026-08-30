import 'package:flutter/material.dart';
import 'enter_result_page.dart'; // Apna Enter Result page
import 'view_result_page.dart';  // Apna View Result page
import 'bulk_enter_result_page.dart'; // Whole-class result entry (fast entry for many students)

class ResultMenuPage extends StatelessWidget {
  const ResultMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Result Management")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ListTile(
            leading: const Icon(Icons.add_box, size: 40, color: Colors.blue),
            title: const Text("Enter New Result", style: TextStyle(fontSize: 18)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const EnterResultPage())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.groups, size: 40, color: Colors.deepPurple),
            title: const Text("Enter Result (Whole Class)", style: TextStyle(fontSize: 18)),
            subtitle: const Text("Enter subjects/marks once, then just type obtained marks"),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BulkEnterResultPage())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.list_alt, size: 40, color: Colors.green),
            title: const Text("View & Print Results", style: TextStyle(fontSize: 18)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ViewResultPage())),
          ),
        ],
      ),
    );
  }
}