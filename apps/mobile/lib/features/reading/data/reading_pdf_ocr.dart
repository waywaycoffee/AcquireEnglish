import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_ocr_native/flutter_ocr_native.dart';

typedef ReadingPdfOcrProgress = void Function(int page, int total, String message);

/// Max pages OCR'd in one import (keeps battery/time bounded).
const int kReadingPdfOcrMaxPages = 120;

String sha256HexOfBytes(Uint8List bytes) => sha256.convert(bytes).toString();

/// On-device OCR for scanned / image-only PDFs (native page render + OCR).
Future<({String text, int pageCount, int ocrPages})> ocrScannedPdf(
  Uint8List pdfBytes, {
  ReadingPdfOcrProgress? onProgress,
  int maxPages = kReadingPdfOcrMaxPages,
}) async {
  final int totalPages = await OcrDocumentSaver.getPdfPageCount(pdfBytes);
  if (totalPages <= 0) {
    throw StateError('无法读取 PDF 页数（平台可能不支持渲染）');
  }
  final int limit = totalPages.clamp(1, maxPages < 1 ? 1 : maxPages);
  final OcrReader reader = OcrReader();
  final StringBuffer buf = StringBuffer();
  try {
    for (int page = 0; page < limit; page++) {
      onProgress?.call(page + 1, limit, 'OCR 第 ${page + 1}/$limit 页…');
      try {
        final OcrResult result = await reader.readFromPdf(
          pdfBytes,
          page: page,
        );
        final String pageText = result.text.trim();
        if (pageText.isEmpty) continue;
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln(pageText);
      } catch (_) {
        // Skip failed pages; continue the rest.
      }
    }
  } finally {
    await reader.dispose();
  }
  final String text = buf
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (text.length < 40) {
    throw StateError('OCR 未能识别出足够正文（可能是空白页或图片过糊）');
  }
  return (text: text, pageCount: totalPages, ocrPages: limit);
}
