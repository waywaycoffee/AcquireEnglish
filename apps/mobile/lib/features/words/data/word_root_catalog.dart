import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/word_root_models.dart';

/// Offline catalog loaded from assets/data/wordroot (prefer roots_app.json / v2).
class WordRootCatalog {
  WordRootCatalog._({
    required this.version,
    required this.generatedAt,
    required this.meta,
    required List<WordRootEntry> roots,
    required List<WordRootWord> words,
    required List<WordRootRel> rels,
  })  : roots = List<WordRootEntry>.unmodifiable(roots),
        words = List<WordRootWord>.unmodifiable(words),
        rels = List<WordRootRel>.unmodifiable(rels),
        _rootById = <String, WordRootEntry>{
          for (final WordRootEntry r in roots) r.id: r,
        },
        _wordByKey = <String, WordRootWord>{
          for (final WordRootWord w in words) w.word: w,
        },
        _relsByWord = <String, List<WordRootRel>>{},
        _wordsByRootId = <String, List<WordRootWord>>{} {
    for (final WordRootRel rel in rels) {
      (_relsByWord[rel.word] ??= <WordRootRel>[]).add(rel);
    }
    for (final WordRootWord w in words) {
      for (final String rid in w.rootIds) {
        (_wordsByRootId[rid] ??= <WordRootWord>[]).add(w);
      }
    }
  }

  static const String assetPath = 'assets/data/wordroot/roots_app.json';
  static const String legacyAssetPath = 'assets/data/wordroot/roots_full.json';

  /// Preferred asset path (tests / callers).
  static const String kAssetPath = assetPath;

  final String version;
  final String generatedAt;
  final Map<String, dynamic> meta;
  final List<WordRootEntry> roots;
  final List<WordRootWord> words;
  final List<WordRootRel> rels;

  final Map<String, WordRootEntry> _rootById;
  final Map<String, WordRootWord> _wordByKey;
  final Map<String, List<WordRootRel>> _relsByWord;
  final Map<String, List<WordRootWord>> _wordsByRootId;

  static WordRootCatalog? _instance;
  static Future<WordRootCatalog>? _loading;

  static Future<WordRootCatalog> load() {
    if (_instance != null) return Future<WordRootCatalog>.value(_instance);
    return _loading ??= _loadInternal().then((WordRootCatalog c) {
      _instance = c;
      _loading = null;
      return c;
    });
  }

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
    _loading = null;
  }

  static Future<WordRootCatalog> _loadInternal() async {
    String raw;
    try {
      raw = await rootBundle.loadString(assetPath);
    } catch (_) {
      raw = await rootBundle.loadString(legacyAssetPath);
    }
    return compute(_parseCatalogJson, raw);
  }

  static WordRootCatalog _parseCatalogJson(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('wordroot catalog must be a JSON object');
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
    final Map<String, dynamic> meta = map['meta'] is Map
        ? Map<String, dynamic>.from(map['meta'] as Map)
        : <String, dynamic>{};

    final List<WordRootEntry> roots = <WordRootEntry>[];
    final Object? rootsRaw = map['roots'];
    if (rootsRaw is List) {
      for (final Object? item in rootsRaw) {
        if (item is Map) {
          roots.add(WordRootEntry.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final List<WordRootWord> words = <WordRootWord>[];
    final Object? wordsRaw = map['words'];
    if (wordsRaw is List) {
      for (final Object? item in wordsRaw) {
        if (item is Map) {
          words.add(WordRootWord.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    // Prefer explicit top-level rels (v1); else flatten embedded word.roots (v2).
    final List<WordRootRel> rels = <WordRootRel>[];
    final Object? relsRaw = map['rels'];
    if (relsRaw is List && relsRaw.isNotEmpty) {
      for (final Object? item in relsRaw) {
        if (item is Map) {
          rels.add(WordRootRel.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else {
      for (final WordRootWord w in words) {
        for (final WordRootRel rel in w.embeddedRels) {
          rels.add(
            WordRootRel(
              word: rel.word,
              rootId: rel.rootId,
              root: rel.root,
              typeCn: rel.typeCn,
              matchedForm: rel.matchedForm,
              position: rel.position,
              rootCn: rel.rootCn,
              rootSense: rel.rootSense,
              wordGloss: w.gloss,
              senseSource: rel.senseSource,
              type: rel.type,
            ),
          );
        }
      }
    }

    return WordRootCatalog._(
      version: '${map['version'] ?? meta['version'] ?? ''}'.trim(),
      generatedAt: '${map['generatedAt'] ?? meta['generated_at'] ?? ''}'.trim(),
      meta: meta,
      roots: roots,
      words: words,
      rels: rels,
    );
  }

  WordRootEntry? rootById(String id) => _rootById[id];

  WordRootWord? wordEntry(String word) =>
      _wordByKey[word.trim().toLowerCase()];

  List<WordRootRel> relsForWord(String word) =>
      List<WordRootRel>.unmodifiable(
        _relsByWord[word.trim().toLowerCase()] ?? const <WordRootRel>[],
      );

  List<WordRootWord> wordsForRoot(String rootId, {int limit = 40}) {
    final List<WordRootWord> list =
        _wordsByRootId[rootId] ?? const <WordRootWord>[];
    if (list.length <= limit) return List<WordRootWord>.unmodifiable(list);
    return List<WordRootWord>.unmodifiable(list.take(limit));
  }

  List<WordRootEntry> findRoots(String raw) {
    final String needle = raw.trim().toLowerCase();
    if (needle.isEmpty) return const <WordRootEntry>[];
    final List<WordRootEntry> exact = <WordRootEntry>[];
    final List<WordRootEntry> fuzzy = <WordRootEntry>[];
    for (final WordRootEntry r in roots) {
      final List<String> forms = r.variantForms
          .map((String f) => f.toLowerCase())
          .toList(growable: false);
      if (r.id.toLowerCase() == needle || forms.contains(needle)) {
        exact.add(r);
        continue;
      }
      if (forms.any(
        (String f) => f.startsWith(needle) || needle.startsWith(f),
      )) {
        fuzzy.add(r);
      }
    }
    if (exact.isNotEmpty) return List<WordRootEntry>.unmodifiable(exact);
    return List<WordRootEntry>.unmodifiable(fuzzy);
  }

  List<WordRootWord> queryRootWords(
    String rootQuery, {
    String? level,
    int limit = 80,
  }) {
    final List<WordRootEntry> matched = findRoots(rootQuery);
    if (matched.isEmpty) return const <WordRootWord>[];
    final Set<String> ids = matched.map((WordRootEntry r) => r.id).toSet();
    final List<WordRootWord> out = <WordRootWord>[];
    final Set<String> seen = <String>{};
    for (final String id in ids) {
      for (final WordRootWord w in wordsForRoot(id, limit: limit * 2)) {
        if (!seen.add(w.word)) continue;
        if (level != null &&
            level.isNotEmpty &&
            w.level.isNotEmpty &&
            w.level != level &&
            !w.level.contains(level)) {
          continue;
        }
        out.add(w);
        if (out.length >= limit) {
          return List<WordRootWord>.unmodifiable(out);
        }
      }
    }
    return List<WordRootWord>.unmodifiable(out);
  }

  List<WordRootEntry> topRoots({int limit = 40, String? level}) {
    final List<WordRootEntry> list = roots
        .where(
          (WordRootEntry r) =>
              level == null ||
              level.isEmpty ||
              r.level == level ||
              r.level.contains(level),
        )
        .toList()
      ..sort(
        (WordRootEntry a, WordRootEntry b) =>
            b.exampleCount.compareTo(a.exampleCount),
      );
    // Fallback: when exampleCount is unset (v2), prefer core then id.
    if (list.isNotEmpty && list.every((WordRootEntry r) => r.exampleCount == 0)) {
      list.sort((WordRootEntry a, WordRootEntry b) {
        final int byLevel = _levelRank(a.level).compareTo(_levelRank(b.level));
        if (byLevel != 0) return byLevel;
        return a.root.compareTo(b.root);
      });
    }
    return list.take(limit).toList(growable: false);
  }

  static int _levelRank(String level) {
    switch (level) {
      case '高频':
      case 'core':
        return 0;
      case '进阶':
      case 'advanced':
        return 1;
      default:
        return 2;
    }
  }

  /// Curated parse only — empty when word is not in the annotated catalog.
  WordRootDetail? queryWordDetail(String rawWord) {
    final String word = rawWord.trim().toLowerCase();
    if (word.isEmpty) return null;
    final WordRootWord? entry = _wordByKey[word];
    final List<WordRootRel> wordRels = _relsByWord[word] ?? const <WordRootRel>[];
    if (entry == null && wordRels.isEmpty) return null;

    final List<WordRootParsePart> parse = _partsFromRels(wordRels);
    final List<WordRootWord> related = _sameRootWords(
      word,
      parse.map((WordRootParsePart p) => p.rootId).where((String id) => id.isNotEmpty),
    );

    return WordRootDetail(
      word: word,
      gloss: entry?.gloss ?? (wordRels.isNotEmpty ? wordRels.first.wordGloss : ''),
      level: entry?.level ?? '',
      parse: parse,
      sameRootWords: related,
      isManual: true,
      wordId: entry?.wordId ?? '',
    );
  }

  /// Curated first; optional heuristic guess for lookup/detail only.
  WordRootDetail? resolveWord(String rawWord, {bool allowGuess = true}) {
    final WordRootDetail? curated = queryWordDetail(rawWord);
    if (curated != null && curated.parse.isNotEmpty) return curated;
    if (!allowGuess) return curated;
    return guessWordDetail(rawWord) ?? curated;
  }

  WordRootDetail? guessWordDetail(String rawWord) {
    final String word = rawWord.trim().toLowerCase();
    if (word.length < 4) return null;

    final List<_SpanHit> hits = <_SpanHit>[];
    for (final WordRootEntry root in roots) {
      for (final String form in root.variantForms) {
        final String f = form.trim().toLowerCase();
        if (f.length < 2) continue;
        int from = 0;
        while (true) {
          final int idx = word.indexOf(f, from);
          if (idx < 0) break;
          hits.add(_SpanHit(start: idx, end: idx + f.length, root: root, form: f));
          from = idx + 1;
        }
      }
    }
    if (hits.isEmpty) return null;

    hits.sort((a, b) {
      final int byLen = (b.end - b.start).compareTo(a.end - a.start);
      if (byLen != 0) return byLen;
      return a.start.compareTo(b.start);
    });

    final List<_SpanHit> chosen = <_SpanHit>[];
    final Set<int> covered = <int>{};
    for (final _SpanHit hit in hits) {
      bool overlap = false;
      for (int i = hit.start; i < hit.end; i++) {
        if (covered.contains(i)) {
          overlap = true;
          break;
        }
      }
      if (overlap) continue;
      for (int i = hit.start; i < hit.end; i++) {
        covered.add(i);
      }
      chosen.add(hit);
    }
    if (chosen.isEmpty) return null;
    chosen.sort((a, b) => a.start.compareTo(b.start));

    final List<WordRootParsePart> parse = chosen
        .map(
          (_SpanHit h) => WordRootParsePart(
            rootText: h.root.root,
            cnMeaning: h.root.cn,
            type: h.root.type,
            typeCn: h.root.typeCn,
            position: h.start == 0
                ? '词首'
                : (h.end >= word.length ? '词尾' : '词中'),
            matchedForm: h.form,
            rootSense: '',
            rootId: h.root.id,
            senseSource: WordRootSenseSource.unknown,
          ),
        )
        .toList(growable: false);

    final WordRootWord? entry = _wordByKey[word];
    return WordRootDetail(
      word: word,
      gloss: entry?.gloss ?? '',
      level: entry?.level ?? '',
      parse: parse,
      sameRootWords: _sameRootWords(
        word,
        parse.map((WordRootParsePart p) => p.rootId),
      ),
      isManual: false,
      warning: '未收录词，以下为自动猜测，仅供参考',
      wordId: entry?.wordId ?? '',
    );
  }

  List<WordRootSpellCandidate> spellSuggest(String rawWord, {int limit = 8}) {
    final String word = rawWord.trim().toLowerCase();
    if (word.length < 3) return const <WordRootSpellCandidate>[];
    final List<WordRootSpellCandidate> out = <WordRootSpellCandidate>[];
    for (final WordRootWord w in words) {
      if ((w.word.length - word.length).abs() > 2) continue;
      final int d = _levenshtein(word, w.word);
      if (d <= 0 || d > 2) continue;
      out.add(
        WordRootSpellCandidate(
          word: w.word,
          distance: d,
          gloss: w.gloss,
          level: w.level,
        ),
      );
    }
    out.sort((a, b) {
      final int byDist = a.distance.compareTo(b.distance);
      if (byDist != 0) return byDist;
      return a.word.compareTo(b.word);
    });
    if (out.length <= limit) return out;
    return out.take(limit).toList(growable: false);
  }

  List<WordRootEntry> searchRoots(String query, {int limit = 40}) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return roots.take(limit).toList(growable: false);
    }
    final List<WordRootEntry> out = <WordRootEntry>[];
    for (final WordRootEntry r in roots) {
      if (r.root.toLowerCase().contains(q) ||
          r.cn.contains(q) ||
          r.variants.toLowerCase().contains(q) ||
          r.id.toLowerCase().contains(q)) {
        out.add(r);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  List<WordRootWord> searchWords(String query, {int limit = 40}) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return words.take(limit).toList(growable: false);
    }
    final List<WordRootWord> out = <WordRootWord>[];
    for (final WordRootWord w in words) {
      if (w.word.contains(q) || w.gloss.contains(q)) {
        out.add(w);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  List<WordRootParsePart> _partsFromRels(List<WordRootRel> wordRels) {
    final List<WordRootRel> ordered = List<WordRootRel>.from(wordRels)
      ..sort((a, b) {
        final int byPos =
            _positionRank(a.position).compareTo(_positionRank(b.position));
        if (byPos != 0) return byPos;
        return a.rootId.compareTo(b.rootId);
      });

    return ordered
        .map((WordRootRel rel) {
          final WordRootEntry? root = _rootById[rel.rootId];
          final String type = rel.type.isNotEmpty
              ? rel.type
              : (root?.type ?? '');
          final String typeCn = rel.typeCn.isNotEmpty
              ? rel.typeCn
              : (root?.typeCn ?? '');
          return WordRootParsePart(
            rootText: rel.root.isNotEmpty ? rel.root : (root?.root ?? ''),
            cnMeaning: rel.rootCn.isNotEmpty ? rel.rootCn : (root?.cn ?? ''),
            type: type,
            typeCn: typeCn,
            position: rel.position,
            matchedForm: rel.matchedForm.isNotEmpty
                ? rel.matchedForm
                : (rel.root.isNotEmpty ? rel.root : (root?.root ?? '')),
            rootSense: rel.rootSense,
            rootId: rel.rootId,
            senseSource: rel.senseSource,
          );
        })
        .toList(growable: false);
  }

  List<WordRootWord> _sameRootWords(String word, Iterable<String> rootIds) {
    final Set<String> seen = <String>{word};
    final List<WordRootWord> related = <WordRootWord>[];
    for (final String rid in rootIds) {
      if (rid.isEmpty) continue;
      for (final WordRootWord other in wordsForRoot(rid, limit: 12)) {
        if (seen.add(other.word)) {
          related.add(other);
          if (related.length >= 24) return related;
        }
      }
    }
    return related;
  }

  static int _positionRank(String position) {
    switch (position) {
      case '词首':
        return 0;
      case '词中':
        return 1;
      case '词尾':
        return 2;
      default:
        return 3;
    }
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final List<int> prev = List<int>.generate(b.length + 1, (int i) => i);
    final List<int> curr = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final int cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        curr[j + 1] = <int>[
          curr[j] + 1,
          prev[j + 1] + 1,
          prev[j] + cost,
        ].reduce((int x, int y) => x < y ? x : y);
      }
      for (int j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }
    return prev[b.length];
  }
}

class _SpanHit {
  const _SpanHit({
    required this.start,
    required this.end,
    required this.root,
    required this.form,
  });

  final int start;
  final int end;
  final WordRootEntry root;
  final String form;
}
