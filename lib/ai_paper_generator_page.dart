import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'school_branding.dart';
import 'pdf_preview_helper.dart';
import 'secrets.dart';

// XFile + uske bytes ek sath rakhta hai taake web aur mobile
// dono pr Image.memory se preview dikhaya ja sake (Image.file web pr
// support nahi hota).
class _PickedImage {
  final XFile file;
  final Uint8List bytes;
  _PickedImage(this.file, this.bytes);
}

class AiPaperGeneratorPage extends StatefulWidget {
  const AiPaperGeneratorPage({super.key});

  @override
  State<AiPaperGeneratorPage> createState() => _AiPaperGeneratorPageState();
}

class _AiPaperGeneratorPageState extends State<AiPaperGeneratorPage> {
  final List<_PickedImage> _selectedImages = [];
  final TextEditingController _mcqController = TextEditingController();
  final TextEditingController _shortController = TextEditingController();
  final TextEditingController _longController = TextEditingController();
  final TextEditingController _extraInfoController = TextEditingController();
  final TextEditingController _schoolNameController =
      TextEditingController(text: currentSchoolDisplayName());

  bool _isGenerating = false;
  bool _isGeneratingPdf = false;
  String _generatedPaperResult = '';
  String _generationStatus = '';

  @override
  void dispose() {
    _mcqController.dispose();
    _shortController.dispose();
    _longController.dispose();
    _extraInfoController.dispose();
    _schoolNameController.dispose();
    super.dispose();
  }

  static const int _maxImages = 10;

  Future<void> _pickImages(ImageSource source) async {
    if (_selectedImages.length >= _maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("You can select a maximum of $_maxImages images."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      final pickedFiles = await picker.pickMultiImage(
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 50,
      );
      if (pickedFiles.isNotEmpty) {
        int remainingSlots = _maxImages - _selectedImages.length;
        final toAdd = pickedFiles.take(remainingSlots).toList();
        final newImages = <_PickedImage>[];
        for (var f in toAdd) {
          newImages.add(_PickedImage(f, await f.readAsBytes()));
        }
        if (!mounted) return;
        setState(() {
          if (pickedFiles.length > remainingSlots) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    "Only $remainingSlots more image(s) could be added (max $_maxImages total). Extra selections were ignored."),
                backgroundColor: Colors.orange,
              ),
            );
          }
          _selectedImages.addAll(newImages);
          _generatedPaperResult = '';
        });
      }
    } else {
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 50,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        if (!mounted) return;
        setState(() {
          _selectedImages.add(_PickedImage(pickedFile, bytes));
          _generatedPaperResult = '';
        });
      }
    }
  }

  Future<void> _generatePaperUsingGemini() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one image!")),
      );
      return;
    }

    final totalMcq = int.tryParse(_mcqController.text.trim()) ?? 0;
    final totalShort = int.tryParse(_shortController.text.trim()) ?? 0;
    final totalLong = int.tryParse(_longController.text.trim()) ?? 0;
    final extraInfo = _extraInfoController.text.trim();

    setState(() {
      _isGenerating = true;
      _generatedPaperResult = '';
      _generationStatus = "Generating paper ...";
    });

    try {
      // Apni Gemini API Key yahan enter karein
      // Ye key ab lib/secrets.dart mein he — wo file GitHub par kabhi
      // nahi jati (.gitignore mein he), isliye secret yahan hardcode
      // nahi kiya.
      const apiKey = openRouterApiKey;

      List<Map<String, dynamic>> content = [];

// Prompt
      content.add({
        "type": "text",
        "text": "Read these book/notes page images carefully.\n"
            "Generate a professional assessment paper.\n"
            "- Exactly $totalMcq MCQs (A,B,C,D)\n"
            "- Exactly $totalShort Short Questions\n"
            "- Exactly $totalLong Long Questions\n"
            "Additional Instructions: $extraInfo"
      });

// Images
      for (var img in _selectedImages) {
        content.add({
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,${base64Encode(img.bytes)}"
          }
        });
      }

      final response = await http.post(
        Uri.parse("https://openrouter.ai/api/v1/chat/completions"),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "openrouter/free",
          "messages": [
            {
              "role": "user",
              "content": content,
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _generatedPaperResult =
              data["choices"][0]["message"]["content"] ?? "No result.";
          _isGenerating = false;
          _generationStatus = "";
        });
      } else {
        throw Exception(response.body);
      }

      final data = jsonDecode(response.body);

      setState(() {
        _generatedPaperResult =
            data["choices"][0]["message"]["content"] ?? "No result generated.";
        _isGenerating = false;
        _generationStatus = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Paper successfully generated !"),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _generationStatus = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ai Error: $e"), backgroundColor: Colors.red),
        );
      }
      debugPrint("Ai Error: $e");
    }
  }

  Future<void> _downloadPdf() async {
    if (_generatedPaperResult.isEmpty) return;
    setState(() => _isGeneratingPdf = true);

    try {
      pw.ImageProvider? schoolLogo;
      try {
        final Uint8List logoBytes = await getSchoolLogoBytes();
        schoolLogo = pw.MemoryImage(logoBytes);
      } catch (e) {
        debugPrint("⚠️ Could not load school logo: $e");
      }

      // Urdu font ko load karna.
      // NOTE: Nastaliq style fonts (jaise NotoNastaliqUrdu) mein har
      // character doosre se jud kar (ligatures ke zariye) apni shape
      // badalta hai — ye "complex script shaping" Flutter ke 'pdf'
      // package ka simple text renderer support nahi karta, isliye
      // bohat se characters ke liye glyph na milne se box (□) dikhta
      // he. Naskh style font (jese Noto Naskh Arabic) seedhe/linear
      // tareeke se jurta he, is liye 'pdf' package ke sath reliably
      // kaam karta he.
      pw.Font? urduFont;
      try {
        final urduFontData = await rootBundle
            .load('assets/fonts/static/NotoNaskhArabic-Regular.ttf');
        urduFont = pw.Font.ttf(urduFontData);
      } catch (e) {
        debugPrint("⚠️ Urdu font load error: $e");
      }

      final pdf = pw.Document(
        theme: urduFont != null
            ? pw.ThemeData.withFont(
                base: urduFont,
                fontFallback: [urduFont],
              )
            : null,
      );

      String schoolName = _schoolNameController.text.trim().isEmpty
          ? "School"
          : _schoolNameController.text.trim();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) {
            if (context.pageNumber != 1) return pw.Container();
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    if (schoolLogo != null)
                      pw.Container(
                        width: 45,
                        height: 45,
                        margin: const pw.EdgeInsets.only(right: 10),
                        child: pw.Image(schoolLogo),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolName,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            font: urduFont,
                          ),
                        ),
                        if (currentSchoolContactEmail().isNotEmpty)
                          pw.Text(
                            currentSchoolContactEmail(),
                            style: const pw.TextStyle(
                              fontSize: 12,
                              color: PdfColors.teal800,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 1.5, color: PdfColors.teal800),
                pw.SizedBox(height: 10),
              ],
            );
          },
          footer: (context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              "Page ${context.pageNumber} of ${context.pagesCount}",
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ),
          build: (pw.Context context) {
            final paragraphs = _generatedPaperResult
                .split('\n')
                .where((p) => p.trim().isNotEmpty)
                .toList();

            return paragraphs.map((p) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  p.trim(),
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 12,
                    font: urduFont,
                  ),
                ),
              );
            }).toList();
          },
        ),
      );

      await showPdfPreviewPage(
        context,
        title: "Paper Preview",
        build: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      debugPrint("❌ PDF Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("PDF Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI Paper Generator ")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImages(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text("Gallery"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImages(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Camera"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "${_selectedImages.length}/$_maxImages images selected",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (_selectedImages.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Stack(
                      children: [
                        Image.memory(_selectedImages[index].bytes,
                            width: 80, height: 100, fit: BoxFit.cover),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedImages.removeAt(index);
                              });
                            },
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.close,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mcqController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "MCQs", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _shortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Short Qs", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _longController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Long Qs", border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _schoolNameController,
              decoration: const InputDecoration(
                labelText: "School Name (for PDF header)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _extraInfoController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Other Information / Instructions",
                hintText: "e.g., short question 3 marks each, total marks 15",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isGenerating ? null : _generatePaperUsingGemini,
              child: Text(
                _isGenerating
                    ? (_generationStatus.isNotEmpty
                        ? _generationStatus
                        : "Processing Images...")
                    : "Generate Paper",
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (_generatedPaperResult.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text("Generated Paper Result:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: SelectableText(
                  _generatedPaperResult,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              // Leave room so the last line of the result isn't hidden
              // behind the sticky "Download PDF" bar below.
              const SizedBox(height: 90),
            ]
          ],
        ),
      ),
      // Sticky bottom bar: keeps the "Download PDF" button reachable as
      // soon as a paper is generated, instead of making the user scroll
      // all the way to the bottom of a long result.
      bottomNavigationBar: _generatedPaperResult.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _isGeneratingPdf ? null : _downloadPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(
                      _isGeneratingPdf ? "Creating PDF..." : "Download PDF"),
                ),
              ),
            ),
    );
  }
}
