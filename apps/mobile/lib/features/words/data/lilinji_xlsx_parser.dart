import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;

import '../domain/syllabus_book.dart';

/// Parse lilinji/English-style vocabulary xlsx (word / phonetic / gloss columns).
List<SyllabusWord> parseLilinjiXlsx(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  final Map<int, String> shared = _readSharedStrings(archive);
  final ArchiveFile? sheet = archive.findFile('xl/worksheets/sheet1.xml') ??
      archive.files.cast<ArchiveFile?>().firstWhere(
        (ArchiveFile? f) =>
            f != null &&
            f.name.startsWith('xl/worksheets/') &&
            f.name.endsWith('.xml'),
        orElse: () => null,
      );
  if (sheet == null) return const <SyllabusWord>[];
  final String xml = utf8.decode(sheet.content as List<int>, allowMalformed: true);
  return _parseSheetXml(xml, shared);
}

List<SyllabusWord> parseLilinjiText(String raw) {
  // Prefer tab-separated word + gloss; fall back to CSV importer.
  final List<SyllabusWord> out = <SyllabusWord>[];
  final Set<String> seen = <String>{};
  final List<String> lines = raw.split(RegExp(r'\r?\n'));
  bool headerSkipped = false;
  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final List<String> parts = trimmed.contains('\t')
        ? trimmed.split('\t')
        : trimmed.split(',');
    if (!headerSkipped && _looksLikeHeader(parts)) {
      headerSkipped = true;
      continue;
    }
    headerSkipped = true;
    final String word = _normalizeLemma(parts.first);
    if (word.isEmpty || !seen.add(word)) continue;
    String gloss = '';
    if (parts.length >= 2) {
      // Skip phonetic-looking columns when present.
      for (int i = 1; i < parts.length; i++) {
        final String cell = parts[i].trim();
        if (cell.isEmpty) continue;
        if (_looksLikePhonetic(cell) && i + 1 < parts.length) continue;
        gloss = cell;
        break;
      }
    }
    out.add(SyllabusWord(word: word, gloss: gloss));
  }
  if (out.isNotEmpty) return out;
  return parseSyllabusImport(raw);
}

Map<int, String> _readSharedStrings(Archive archive) {
  final ArchiveFile? file = archive.findFile('xl/sharedStrings.xml');
  if (file == null) return const <int, String>{};
  final String xml = utf8.decode(file.content as List<int>, allowMalformed: true);
  final Map<int, String> out = <int, String>{};
  final RegExp si = RegExp(r'<si>(.*?)</si>', dotAll: true);
  int index = 0;
  for (final RegExpMatch match in si.allMatches(xml)) {
    out[index++] = _collectTextNodes(match.group(1) ?? '');
  }
  return out;
}

List<SyllabusWord> _parseSheetXml(String xml, Map<int, String> shared) {
  final List<Map<int, String>> rows = <Map<int, String>>[];
  final RegExp rowRe = RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true);
  final RegExp cellRe = RegExp(
    r'<c\b([^>]*)>(.*?)</c>|<c\b([^>]*)/>',
    dotAll: true,
  );
  for (final RegExpMatch rowMatch in rowRe.allMatches(xml)) {
    final String rowXml = rowMatch.group(1) ?? '';
    final Map<int, String> cells = <int, String>{};
    for (final RegExpMatch cellMatch in cellRe.allMatches(rowXml)) {
      final String attrs = cellMatch.group(1) ?? cellMatch.group(3) ?? '';
      final String body = cellMatch.group(2) ?? '';
      final Match? ref = RegExp(r'\br="([A-Z]+)(\d+)"').firstMatch(attrs);
      if (ref == null) continue;
      final int col = _columnIndex(ref.group(1)!);
      final String type = RegExp(r'\bt="([^"]+)"').firstMatch(attrs)?.group(1) ?? '';
      String value = '';
      if (type == 'inlineStr') {
        value = _collectTextNodes(body);
      } else if (type == 's') {
        final String? v = RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1);
        final int? idx = int.tryParse(v ?? '');
        value = idx == null ? '' : (shared[idx] ?? '');
      } else {
        value = RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1) ??
            _collectTextNodes(body);
      }
      cells[col] = _decodeXmlEntities(value).trim();
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return const <SyllabusWord>[];

  final Map<int, String> header = rows.first;
  int wordCol = 0;
  int glossCol = -1;
  for (final MapEntry<int, String> e in header.entries) {
    final String h = e.value.toLowerCase();
    if (h.contains('单词') || h == 'word' || h.contains('词汇') || h == 'lemma') {
      wordCol = e.key;
    } else if (h.contains('释义') ||
        h.contains('中文') ||
        h.contains('意思') ||
        h.contains('definition') ||
        h.contains('meaning') ||
        h == 'gloss') {
      glossCol = e.key;
    }
  }
  if (glossCol < 0) {
    // Common layout: word | uk | us | gloss  OR word | phonetic | gloss
    final List<int> cols = header.keys.toList()..sort();
    if (cols.length >= 4) {
      glossCol = cols[3];
    } else if (cols.length >= 3) {
      glossCol = cols[2];
    } else if (cols.length >= 2) {
      glossCol = cols[1];
    }
  }

  final List<SyllabusWord> out = <SyllabusWord>[];
  final Set<String> seen = <String>{};
  final bool hasHeader = _looksLikeHeader(
    header.values.toList(growable: false),
  );
  for (int i = hasHeader ? 1 : 0; i < rows.length; i++) {
    final Map<int, String> row = rows[i];
    final String word = _normalizeLemma(row[wordCol] ?? '');
    if (word.isEmpty || !seen.add(word)) continue;
    final String gloss = glossCol >= 0 ? (row[glossCol] ?? '').trim() : '';
    out.add(SyllabusWord(word: word, gloss: gloss));
  }
  return out;
}

String _collectTextNodes(String fragment) {
  final StringBuffer buf = StringBuffer();
  for (final RegExpMatch m in RegExp(
    r'<t\b[^>]*>(.*?)</t>',
    dotAll: true,
  ).allMatches(fragment)) {
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(m.group(1) ?? '');
  }
  if (buf.isEmpty) {
    // Fallback: strip tags.
    buf.write(fragment.replaceAll(RegExp(r'<[^>]+>'), ''));
  }
  return _decodeXmlEntities(buf.toString());
}

String _decodeXmlEntities(String raw) {
  if (!raw.contains('&')) return raw;
  // html package handles numeric and named entities.
  return html_parser.parseFragment(raw).text ?? raw;
}

int _columnIndex(String letters) {
  int n = 0;
  for (int i = 0; i < letters.length; i++) {
    n = n * 26 + (letters.codeUnitAt(i) - 64);
  }
  return n - 1;
}

bool _looksLikeHeader(List<String> parts) {
  if (parts.isEmpty) return false;
  final String joined = parts.join(' ').toLowerCase();
  return joined.contains('单词') ||
      joined.contains('word') ||
      joined.contains('释义') ||
      joined.contains('音标') ||
      joined.contains('phonetic');
}

bool _looksLikePhonetic(String cell) {
  return cell.startsWith('/') ||
      cell.startsWith('[') ||
      cell.contains('ˈ') ||
      cell.contains('ˌ');
}

String _normalizeLemma(String raw) {
  String word = raw.trim().toLowerCase();
  // Keep multi-word phrases; strip odd punctuation.
  word = word.replaceAll(RegExp(r'[“”"‘’]'), "'");
  word = word.replaceAll(RegExp(r"[^a-z0-9'\-\s]"), ' ');
  word = word.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (word.isEmpty) return '';
  // Drop pure numbers.
  if (RegExp(r'^[0-9]+$').hasMatch(word)) return '';
  return word;
}
