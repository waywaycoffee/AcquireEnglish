import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;

import '../../player/presentation/player_mock_state.dart';
import '../domain/reading_doc.dart';

/// Target words per generated article from video subtitles.
const int kReadingChunkMinWords = 200;
const int kReadingChunkMaxWords = 600;

String cleanSubtitleEnglish(String raw) {
  String text = raw.trim();
  if (text.isEmpty) return '';
  // Drop common SDH / music markers.
  text = text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  text = text.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

int countWords(String text) {
  if (text.trim().isEmpty) return 0;
  return text
      .split(RegExp(r'\s+'))
      .where((String w) => w.trim().isNotEmpty)
      .length;
}

/// Split subtitle lines into readable short articles (200–600 words).
List<ReadingDoc> splitSubtitlesIntoReadingDocs({
  required List<PlayerSubtitleLine> lines,
  required String courseId,
  required String episodeId,
  required String courseTitle,
  required String episodeTitle,
  DateTime? now,
}) {
  final DateTime created = now ?? DateTime.now();
  final List<ReadingSegment> buffer = <ReadingSegment>[];
  int bufferWords = 0;
  final List<ReadingDoc> docs = <ReadingDoc>[];
  int part = 1;

  void flush({bool force = false}) {
    if (buffer.isEmpty) return;
    if (!force && bufferWords < kReadingChunkMinWords) return;
    final String plain = buffer
        .map((ReadingSegment s) => s.text)
        .join(' ')
        .trim();
    if (plain.isEmpty) {
      buffer.clear();
      bufferWords = 0;
      return;
    }
    final String id =
        'video_${episodeId}_p${part}_${created.millisecondsSinceEpoch}';
    docs.add(
      ReadingDoc(
        id: id,
        title: part == 1 && docs.isEmpty
            ? '$courseTitle · $episodeTitle'
            : '$courseTitle · $episodeTitle · 第$part篇',
        sourceType: ReadingSourceType.video,
        plainText: plain,
        segments: List<ReadingSegment>.unmodifiable(buffer),
        courseId: courseId,
        episodeId: episodeId,
        courseTitle: courseTitle,
        episodeTitle: episodeTitle,
        createdAt: created,
      ),
    );
    part += 1;
    buffer.clear();
    bufferWords = 0;
  }

  for (final PlayerSubtitleLine line in lines) {
    final String english = cleanSubtitleEnglish(line.english);
    if (english.isEmpty) continue;
    final int words = countWords(english);
    if (bufferWords > 0 &&
        bufferWords + words > kReadingChunkMaxWords &&
        bufferWords >= kReadingChunkMinWords) {
      flush(force: true);
    }
    buffer.add(
      ReadingSegment(
        text: english,
        startMs: line.startMs,
        endMs: line.endMs,
      ),
    );
    bufferWords += words;
    if (bufferWords >= kReadingChunkMaxWords) {
      flush(force: true);
    }
  }
  flush(force: true);
  // If everything was shorter than min, still keep one doc.
  if (docs.isEmpty && buffer.isNotEmpty) {
    flush(force: true);
  }
  return docs;
}

String parseTxtImport(Uint8List bytes, {String? filename}) {
  String text = utf8.decode(bytes, allowMalformed: true);
  // Strip UTF-8 BOM.
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  return text.trim();
}

/// Extract readable plain text from an EPUB (xhtml/html bodies).
///
/// Also works on Standard Ebooks GitHub source zips (`*/src/epub/text/*.xhtml`).
String parseEpubImport(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
    throw StateError('不是有效的 EPUB/ZIP（可能下载到了网页）');
  }
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  final List<ArchiveFile> htmlFiles = archive.files
      .where((ArchiveFile f) {
        if (!f.isFile) return false;
        final String name = f.name.toLowerCase().replaceAll('\\', '/');
        if (!(name.endsWith('.xhtml') ||
            name.endsWith('.html') ||
            name.endsWith('.htm'))) {
          return false;
        }
        // Skip boilerplate / navigation when present (SE source + many EPUBs).
        final String base = name.split('/').last;
        if (base.startsWith('toc') ||
            base.contains('nav') ||
            base.contains('colophon') ||
            base.contains('imprint') ||
            base.contains('uncopyright') ||
            base.contains('titlepage') ||
            base.contains('cover') ||
            base.contains('dedication') ||
            base.contains('halftitle') ||
            base.contains('epigraph') ||
            base.contains('loi') ||
            base.contains('copyright')) {
          return false;
        }
        return true;
      })
      .toList()
    ..sort((ArchiveFile a, ArchiveFile b) =>
        _naturalEpubPathCompare(a.name, b.name));
  final StringBuffer buf = StringBuffer();
  for (final ArchiveFile file in htmlFiles) {
    final String xml = utf8.decode(file.content as List<int>, allowMalformed: true);
    final String plain = html_parser.parse(xml).body?.text ?? '';
    final String cleaned = plain.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) continue;
    if (buf.isNotEmpty) buf.writeln();
    buf.writeln(cleaned);
  }
  return buf.toString().trim();
}

int _naturalEpubPathCompare(String a, String b) {
  final List<String> pa = a.toLowerCase().replaceAll('\\', '/').split('/');
  final List<String> pb = b.toLowerCase().replaceAll('\\', '/').split('/');
  final String fa = pa.isEmpty ? a : pa.last;
  final String fb = pb.isEmpty ? b : pb.last;
  final RegExp numRe = RegExp(r'(\d+)');
  final Match? ma = numRe.firstMatch(fa);
  final Match? mb = numRe.firstMatch(fb);
  if (ma != null && mb != null) {
    final int na = int.tryParse(ma.group(1)!) ?? 0;
    final int nb = int.tryParse(mb.group(1)!) ?? 0;
    if (na != nb) return na.compareTo(nb);
  }
  return a.compareTo(b);
}

String titleFromFilename(String name) {
  String base = name.trim();
  final int slash = base.lastIndexOf('/');
  final int backslash = base.lastIndexOf(r'\');
  final int cut = slash > backslash ? slash : backslash;
  if (cut >= 0) base = base.substring(cut + 1);
  base = base.replaceAll(
    RegExp(r'\.(txt|epub|md|html?)$', caseSensitive: false),
    '',
  );
  return base.isEmpty ? '导入读物' : base;
}
