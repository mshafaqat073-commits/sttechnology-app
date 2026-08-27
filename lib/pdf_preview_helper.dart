import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// ROOT CAUSE of "print preview doesn't show up on desktop":
/// `Printing.layoutPdf()` does NOT show any preview screen by itself —
/// it goes straight to the platform's native print handler:
///   - Web: the browser's own print preview (which is why it works fine
///     there)
///   - Android: the OS's own native print-preview dialog (which is why
///     it works fine there too)
///   - Windows/macOS/Linux (Desktop): there is no built-in preview at
///     all — it opens the OS's plain "choose a printer" dialog (which
///     doesn't show the PDF page), and if no printer is configured at
///     that moment, sometimes nothing visible happens at all.
///
/// Fix: instead of `Printing.layoutPdf()`, use this helper to show an
/// in-app preview SCREEN (built on the `PdfPreview` widget) — this gives
/// a guaranteed, identical preview on all three platforms
/// (mobile/desktop/web), and Print and Share/Send both work from the
/// same screen.
///
/// Usage — where you previously had:
///   await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
/// now write:
///   await showPdfPreviewPage(context, title: "Admission Slip",
///       build: (format) async => pdfBytes);
Future<void> showPdfPreviewPage(
  BuildContext context, {
  required String title,
  required Future<Uint8List> Function(PdfPageFormat format) build,
  String? shareFileName,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _PdfPreviewScreen(
        title: title,
        pdfBuilder: build,
        shareFileName: shareFileName,
      ),
    ),
  );
}

class _PdfPreviewScreen extends StatelessWidget {
  final String title;
  final Future<Uint8List> Function(PdfPageFormat format) pdfBuilder;
  final String? shareFileName;

  const _PdfPreviewScreen({
    required this.title,
    required this.pdfBuilder,
    this.shareFileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: pdfBuilder,
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        pdfFileName: shareFileName,
        // If PDF generation itself throws (e.g. a missing font/image),
        // this shows a clear error instead of a silently blank screen.
        onError: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "PDF preview error: $error",
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ),
    );
  }
}
