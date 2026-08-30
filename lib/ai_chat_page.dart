import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'school_branding.dart';
import 'secrets.dart';

class AIChatPage extends StatefulWidget {
  // 'admin', 'teacher', ya 'parent' — is se AI ko pata chalta he ke
  // kis role se baat ho rahi he, taake wo har role ke liye sahi
  // limits ke sath jawab de (misal: teacher ko fee/dues info na de,
  // parent ko doosre bacchon/families ki info na de).
  final String role;

  const AIChatPage({super.key, required this.role});

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Ye key ab lib/secrets.dart mein he — wo file GitHub par kabhi nahi
  // jati (.gitignore mein he), isliye secret yahan hardcode nahi kiya.
  static const String apiKey = groqApiKey;

  bool loading = false;
  final List<Map<String, dynamic>> messages = [];

  @override
  void initState() {
    super.initState();
    messages.add({
      "isUser": false,
      "text":
          "👋 Welcome to AEP School Management System AI.\n\nHow can I help you today?",
    });
  }

  void scrollBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // The principal's name now comes from each school's own Settings
  // (currentSchoolPrincipalName(), which reads from the SchoolContext
  // cache). If a school hasn't set a principal name yet, this line is
  // simply hidden instead of the AI stating a wrong/another school's name.
  String _principalLine() {
    final principal = currentSchoolPrincipalName();
    if (principal.isEmpty) return '';
    return 'The principal of the school is $principal${currentSchoolContactNumber().isNotEmpty ? ' (Contact: ${currentSchoolContactNumber()})' : ''}.\n';
  }

  // Role ke hisaab se AI ko batata he ke ye kis se baat kar raha he aur
  // kya cheezen us role ko NAHI batani — taake fee/financial aur doosre
  // logon ki personal info sirf Admin tak mehdood rahe.
  String _roleInstructions() {
    switch (widget.role) {
      case 'teacher':
        return """

IMPORTANT ROLE RESTRICTION: You are talking to a TEACHER, not the Admin.
Teachers do NOT have access to any student's fee, dues, payments, or the
school's financial/profit-loss information. If a teacher asks about any
student's fee, dues, payment status, or school finances, do NOT provide it
— politely tell them this information is only available to the
Admin/Principal and to check the Admin panel or contact the school office.
You may freely help teachers with attendance, results, homework, timetable,
and other teaching-related questions.
""";
      case 'parent':
        return """

IMPORTANT ROLE RESTRICTION: You are talking to a PARENT, not the Admin or a
Teacher. Only discuss general information about the school (as described
above) and, if this conversation itself shares details about the parent's
OWN child, information about that child only. NEVER share information
about any other student, another family's fee or dues, other parents'
contact details, staff personal information, or the school's internal
financial/administrative data. If asked about anything beyond the parent's
own child or general school info, politely decline and suggest the parent
contact the school office directly.
""";
      case 'admin':
      default:
        return """

You are talking to the Admin/Principal, who may ask about any student,
fee, or administrative matter. Help fully within the information above,
and if exact data isn't available here, suggest checking the relevant
section of the app.
""";
    }
  }

  Future<void> sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final String question = _controller.text.trim();

    setState(() {
      messages.add({
        "isUser": true,
        "text": question,
      });
      loading = true;
    });

    _controller.clear();
    scrollBottom();

    // Pichle messages ka context bhi bhejte hain (max last 10) taake AI ko
    // conversation yaad rahe — sirf akela sawal bhejne se AI har baar
    // "bhool" jata tha ke pehle kya baat hui thi.
    final List<Map<String, String>> recentHistory = [];
    final historySource =
        messages.length > 1 ? messages.sublist(0, messages.length - 1) : [];
    final startIndex =
        historySource.length > 10 ? historySource.length - 10 : 0;
    for (var m in historySource.sublist(startIndex)) {
      recentHistory.add({
        "role": (m["isUser"] ?? false) ? "user" : "assistant",
        "content": (m["text"] ?? "").toString(),
      });
    }

    try {
      final response = await http
          .post(
            Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
            headers: {
              "Authorization": "Bearer $apiKey",
              "Content-Type": "application/json",
            },
        body: jsonEncode({
          // llama-3.1-8b-instant was decommissioned by Groq (June 2026),
          // which made every chat request fail with a "model_decommissioned"
          // error. openai/gpt-oss-20b is Groq's recommended replacement.
          "model": "openai/gpt-oss-20b",
          "messages": [
            {
              "role": "system",
              // The school name, principal name, and contact number are all
              // now dynamic (from Settings, i.e. the per-school Firestore
              // doc) — any school can set Settings > School Name / Principal
              // Name / WhatsApp Number in its own app instance and AI Chat
              // will automatically give that school's correct information.
              // The old hardcoded "AEP School System"-specific details
              // (year established, the "only institute in Khushab" claim,
              // and YouTube/Facebook links) have been removed here since
              // they were only correct for one specific school — if needed,
              // these can also be turned into new Settings fields and made
              // dynamic later.
              "content": """
You are the official AI Assistant of ${currentSchoolDisplayName()}.
${_principalLine()}
${currentSchoolDisplayName()} is built with Flutter and Firebase.

Your users are:
• Principal
• Admin
• Teachers
• School Staff

Modules:
• Student Management
• Admissions
• Fee Management
• Staff Management
• Attendance
• Expenses
• Profit & Loss
• Results
• SLC Generator

Class / Subject Offerings:
[TODO: Yahan apni school ki classes (Playgroup se Ten/Matric tak) aur har
class mein parhaye jane wale subjects likhein. Example:
"Classes Playgroup to Five (Primary): English, Urdu, Math, Islamiat, Science.
Classes Six to Eight (Middle): + Computer Science, Social Studies.
Classes Nine-Ten (Matric): Science group (Physics, Chemistry, Biology/
Computer) and Arts group available."]

School Timings & Holidays:
[TODO: Yahan school ke opening/closing time, working days, aur holidays
likhein. Example: "School timing: Monday-Saturday, 8:00 AM to 2:00 PM.
Friday: 8:00 AM to 12:30 PM. Weekly off: Sunday. Summer/Winter vacation
dates announced separately each year."]

Admission Process & Requirements:
[TODO: Yahan admission ka process aur zaroori documents likhein. Example:
"Admission process: Visit school office, fill admission form, submit
documents (B-Form copy x2, Father CNIC copy x2, 3 passport-size photos,
previous school leaving certificate if applicable). Admission test may
apply for classes Six and above."]

Fee Structure & Payment Methods:
[TODO: Yahan fee structure aur payment ka tareeqa likhein. Example:
"Monthly fee varies by class (contact office for exact amount). Fee is
due by the 10th of each month. Payment accepted in cash at school office.
Late fee may apply after due date. One-time admission fee applies for
new students."]

Always answer professionally and briefly. If asked about specific amounts
or dates not listed above, politely advise the person to contact the
school office for the most current information.
${_roleInstructions()}"""
            },
            ...recentHistory,
            {"role": "user", "content": question}
          ]
        }),
      )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data["choices"][0]["message"]["content"] ?? "No response";

        setState(() {
          messages.add({
            "isUser": false,
            "text": reply,
          });
        });
      } else {
        setState(() {
          messages.add({
            "isUser": false,
            "text": "API Error ${response.statusCode}\n${response.body}",
            "isError": true,
          });
        });
      }
    } on TimeoutException {
      setState(() {
        messages.add({
          "isUser": false,
          "text":
              "⏱️ Response is taking too long. Please check your internet connection and try again.",
          "isError": true,
        });
      });
    } catch (e) {
      setState(() {
        messages.add({
          "isUser": false,
          "text": "Error: $e",
          "isError": true,
        });
      });
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }

    scrollBottom();
  }

  void _clearChat() {
    setState(() {
      messages.clear();
      messages.add({
        "isUser": false,
        "text":
            "👋 Welcome to AEP School Management System AI.\n\nHow can I help you today?",
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("AI Assistant"),
        backgroundColor: Colors.teal,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: "New Chat",
            onPressed: messages.length <= 1
                ? null
                : () async {
                    bool? confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Start New Chat?"),
                        content: const Text(
                            "This will clear the current conversation."),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text("Cancel")),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text("Clear")),
                        ],
                      ),
                    );
                    if (confirm == true) _clearChat();
                  },
          ),
        ],
      ),
      body: SafeArea(child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final bool isUser = msg["isUser"] ?? false;
                final bool isError = msg["isError"] ?? false;
                final String text = msg["text"] ?? "";

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Copied to clipboard"),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(14),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * .80,
                      ),
                      decoration: BoxDecoration(
                        color: isError
                            ? Colors.red.shade50
                            : (isUser ? Colors.teal : Colors.white),
                        borderRadius: BorderRadius.circular(18),
                        border: isError
                            ? Border.all(color: Colors.red.shade200)
                            : null,
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 4,
                            color: Colors.black12,
                          )
                        ],
                      ),
                      child: Text(
                        text,
                        style: TextStyle(
                          color: isError
                              ? Colors.red.shade800
                              : (isUser ? Colors.white : Colors.black87),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text("AI is typing...")
                ],
              ),
            ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => sendMessage(),
                    decoration: InputDecoration(
                      hintText: "Ask anything...",
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.teal,
                  child: IconButton(
                    onPressed: loading ? null : sendMessage,
                    icon: const Icon(
                      Icons.send,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
