import 'dart:typed_data';

import '../../sync/data/acquire_api_client.dart';
import 'reading_ingest.dart';
import 'reading_pdf_ocr.dart';

class ReadingPdfImportResult {
  const ReadingPdfImportResult({
    required this.text,
    required this.source,
    this.pageCount = 0,
    this.contentSha256 = '',
  });

  final String text;
  /// `text_layer` | `shared_ocr` | `local_ocr`
  final String source;
  final int pageCount;
  final String contentSha256;
}

/// PDF import: embedded text → shared OCR library → on-device OCR (+ optional upload).
///
/// [shareOcr] false：私人教材解构流不读/不写共享 OCR（默认阅读导入仍为 true）。
/// Aligns with 口语入门探索版 / reading source 20MB ceiling.
const int kReadingImportMaxBytes = 20 * 1024 * 1024;

Future<ReadingPdfImportResult> importPdfForReading({
  required Uint8List bytes,
  required String filename,
  required AcquireApiClient api,
  required bool isLoggedIn,
  ReadingPdfOcrProgress? onProgress,
  bool shareOcr = true,
  int maxBytes = kReadingImportMaxBytes,
}) async {
  if (bytes.lengthInBytes > maxBytes) {
    throw StateError(
      '文档超过 ${maxBytes ~/ (1024 * 1024)}MB 上限，请压缩后再导入',
    );
  }
  final String sha = sha256HexOfBytes(bytes);
  final String embedded = parsePdfImport(bytes);
  if (!pdfNeedsOcr(embedded)) {
    return ReadingPdfImportResult(
      text: embedded,
      source: 'text_layer',
      contentSha256: sha,
    );
  }

  if (shareOcr) {
    onProgress?.call(0, 1, '正在查询云端 OCR 图书库…');
    try {
      final SharedOcrBookPack? shared = await api.getSharedOcrBook(
        contentSha256: sha,
      );
      final String sharedText = (shared?.plainText ?? '').trim();
      if (sharedText.length >= 40) {
        return ReadingPdfImportResult(
          text: sharedText,
          source: 'shared_ocr',
          pageCount: shared?.pageCount ?? 0,
          contentSha256: sha,
        );
      }
    } catch (_) {}
  }

  final ({String text, int pageCount, int ocrPages}) ocr = await ocrScannedPdf(
    bytes,
    onProgress: onProgress,
  );

  if (isLoggedIn && shareOcr) {
    onProgress?.call(ocr.ocrPages, ocr.pageCount, '正在上传到云端 OCR 图书库…');
    try {
      await api.putSharedOcrBook(
        contentSha256: sha,
        plainText: ocr.text,
        title: titleFromFilename(filename),
        sourceFilename: filename,
        pageCount: ocr.pageCount,
      );
    } catch (_) {}
  }

  return ReadingPdfImportResult(
    text: ocr.text,
    source: 'local_ocr',
    pageCount: ocr.pageCount,
    contentSha256: sha,
  );
}
