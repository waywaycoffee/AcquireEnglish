import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/word_root_models.dart';
import '../domain/word_morphology.dart';

const String kWordRootAssetPath = 'assets/data/wordroot/roots_full.json';

/// Offline word-root catalog: load once, query in memory.
class WordRootCatalog {
  WordRootCatalog._({
    required this.roots,
    required this.words,
    required this.rels,
    required this.meta,
  });

  final List<WordRootEntry> roots;
  final List<WordRootWord> words;
  final List<WordRootRel> rels;
  final Map<String, Object?> meta;

  late final Map<String, WordRootEntry> rootsById = <String, WordRootEntry>{
    for (final WordRootEntry r in roots) r.id: r,
  };
  late final Map<String, WordRootWord> wordsByLemma = <String, WordRootWord>{
    for (final WordRootWord w in words) w.word: w,
  };
  late final Map<String, List<WordRootRel>> relsByWord =
      <String, List<WordRootRel>>{};
  late final Map<String, List<WordRootRel>> relsByRootId =
      <String, List<WordRootRel>>{};
  late final Map<String, List<WordRootEntry>> rootsByForm =
      <String, List<WordRootEntry>>{};

  static WordRootCatalog? _instance;
  static Future<WordRootCatalog>? _loading;

  static Future<WordRootCatalog> load() {
    final WordRootCatalog? ready = _instance;
    if (ready != null) return Future<WordRootCatalog>.value(ready);
    return _loading ??= _loadAsset().then((WordRootCatalog catalog) {
      _instance = catalog;
      _loading = null;
      return catalog;
    });
  }

  static Future<WordRootCatalog> _loadAsset() async {
    final String raw = await rootBundle.loadString(kWordRootAssetPath);
    final Map<String, dynamic> json = Map<String, dynamic>.from(
      jsonDecode(raw) as Map,
    );
    final List<WordRootEntry> roots = <WordRootEntry>[];
    final Object? rootsRaw = json['roots'];
    if (rootsRaw is List) {
      for (final Object? item in rootsRaw) {
        if (item is Map) {
          roots.add(
            WordRootEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final List<WordRootWord> words = <WordRootWord>[];
    final Object? wordsRaw = json['words'];
    if (wordsRaw is List) {
      for (final Object? item in wordsRaw) {
        if (item is Map) {
          final WordRootWord word = WordRootWord.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (word.word.isNotEmpty) words.add(word);
        }
      }
    }
    final List<WordRootRel> rels = <WordRootRel>[];
    final Object? relsRaw = json['rels'];
    if (relsRaw is List) {
      for (final Object? item in relsRaw) {
        if (item is Map) {
          final WordRootRel rel = WordRootRel.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (rel.word.isNotEmpty && rel.rootId.isNotEmpty) {
            rels.add(rel);
          }
        }
      }
    }
    final WordRootCatalog catalog = WordRootCatalog._(
      roots: List<WordRootEntry>.unmodifiable(roots),
      words: List<WordRootWord>.unmodifiable(words),
      rels: List<WordRootRel>.unmodifiable(rels),
      meta: Map<String, Object?>.from(json['meta'] as Map? ?? const <String, Object?>{}),
    );
    catalog._buildIndexes();
    return catalog;
  }

  void _buildIndexes() {
    for (final WordRootRel rel in rels) {
      relsByWord.putIfAbsent(rel.word, () => <WordRootRel>[]).add(rel);
      relsByRootId.putIfAbsent(rel.rootId, () => <WordRootRel>[]).add(rel);
    }
    for (final WordRootEntry root in roots) {
      for (final String form in root.variantForms) {
        final String key = _normalizeForm(form);
        if (key.isEmpty) continue;
        rootsByForm.putIfAbsent(key, () => <WordRootEntry>[]).add(root);
      }
    }
  }

  static String _normalizeForm(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'^-+|-+$'), '');

  static String _normalizeWord(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');

  WordRootDetail? queryWordDetail(String raw) {
    final String word = _normalizeWord(raw);
    if (word.isEmpty) return null;
    final WordRootWord? meta = wordsByLemma[word];
    final List<WordRootRel> wordRels = relsByWord[word] ?? const <WordRootRel>[];
    if (meta == null && wordRels.isEmpty) return null;

    final List<WordRootParsePart> parse = <WordRootParsePart>[];
    final Set<String> rootIds = <String>{};
    for (final WordRootRel rel in wordRels) {
      final WordRootEntry? root = rootsById[rel.rootId];
      rootIds.add(rel.rootId);
      parse.add(
        WordRootParsePart(
          rootText: rel.root.isNotEmpty ? rel.root : (root?.root ?? ''),
          cnMeaning: rel.rootCn.isNotEmpty ? rel.rootCn : (root?.cn ?? ''),
          type: root?.type ?? '',
          typeCn: rel.typeCn.isNotEmpty ? rel.typeCn : (root?.typeCn ?? ''),
          position: rel.position,
          matchedForm: rel.matchedForm,
          rootSense: rel.rootSense,
          rootId: rel.rootId,
        ),
      );
    }
    const Map<String, int> posRank = <String, int>{
      '词首': 0,
      '词中': 1,
      '词尾': 2,
    };
    parse.sort(
      (WordRootParsePart a, WordRootParsePart b) =>
          (posRank[a.position] ?? 9).compareTo(posRank[b.position] ?? 9),
    );

    final List<WordRootWord> same = <WordRootWord>[];
    final Set<String> seen = <String>{word};
    for (final String rid in rootIds) {
      for (final WordRootRel rel in relsByRootId[rid] ?? const <WordRootRel>[]) {
        if (!seen.add(rel.word)) continue;
        final WordRootWord? other = wordsByLemma[rel.word];
        same.add(
          other ??
              WordRootWord(
                word: rel.word,
                gloss: rel.wordGloss,
                level: '',
                rootIds: <String>[rid],
              ),
        );
      }
    }
    const Map<String, int> levelRank = <String, int>{'高频': 0, '进阶': 1};
    same.sort((WordRootWord a, WordRootWord b) {
      final int byLevel =
          (levelRank[a.level] ?? 9).compareTo(levelRank[b.level] ?? 9);
      return byLevel != 0 ? byLevel : a.word.compareTo(b.word);
    });

    return WordRootDetail(
      word: word,
      gloss: meta?.gloss ?? (wordRels.isEmpty ? '' : wordRels.first.wordGloss),
      level: meta?.level ?? '',
      parse: List<WordRootParsePart>.unmodifiable(parse),
      sameRootWords: List<WordRootWord>.unmodifiable(same),
    );
  }

  List<WordRootEntry> findRoots(String raw) {
    final String needle = _normalizeForm(raw);
    if (needle.isEmpty) return const <WordRootEntry>[];
    final List<WordRootEntry>? exact = rootsByForm[needle];
    if (exact != null && exact.isNotEmpty) {
      return List<WordRootEntry>.unmodifiable(exact);
    }
    // Prefix / contains fallback for short queries.
    final List<WordRootEntry> fuzzy = <WordRootEntry>[];
    final Set<String> seen = <String>{};
    for (final MapEntry<String, List<WordRootEntry>> e in rootsByForm.entries) {
      if (e.key == needle || e.key.startsWith(needle) || needle.startsWith(e.key)) {
        for (final WordRootEntry root in e.value) {
          if (seen.add(root.id)) fuzzy.add(root);
        }
      }
    }
    fuzzy.sort(
      (WordRootEntry a, WordRootEntry b) =>
          b.exampleCount.compareTo(a.exampleCount),
    );
    return List<WordRootEntry>.unmodifiable(fuzzy);
  }

  List<WordRootWord> queryRootWords(
    String rootText, {
    String? level,
    int limit = 80,
  }) {
    final List<WordRootEntry> matched = findRoots(rootText);
    if (matched.isEmpty) return const <WordRootWord>[];
    final Set<String> ids = matched.map((WordRootEntry r) => r.id).toSet();
    final List<WordRootWord> out = <WordRootWord>[];
    final Set<String> seen = <String>{};
    for (final String id in ids) {
      for (final WordRootRel rel in relsByRootId[id] ?? const <WordRootRel>[]) {
        if (!seen.add(rel.word)) continue;
        final WordRootWord? meta = wordsByLemma[rel.word];
        final WordRootWord word = meta ??
            WordRootWord(
              word: rel.word,
              gloss: rel.wordGloss,
              level: '',
              rootIds: <String>[id],
            );
        if (level != null &&
            level.isNotEmpty &&
            word.level.isNotEmpty &&
            word.level != level &&
            !word.level.contains(level) &&
            !level.contains(word.level)) {
          continue;
        }
        out.add(word);
      }
    }
    const Map<String, int> levelRank = <String, int>{'高频': 0, '进阶': 1};
    out.sort((WordRootWord a, WordRootWord b) {
      final int byLevel =
          (levelRank[a.level] ?? 9).compareTo(levelRank[b.level] ?? 9);
      return byLevel != 0 ? byLevel : a.word.compareTo(b.word);
    });
    if (out.length <= limit) {
      return List<WordRootWord>.unmodifiable(out);
    }
    return List<WordRootWord>.unmodifiable(out.take(limit));
  }

  List<WordRootSpellCandidate> spellSuggest(
    String raw, {
    int maxCandidates = 5,
    int maxDist = 2,
  }) {
    final String input = _normalizeWord(raw);
    if (input.isEmpty) return const <WordRootSpellCandidate>[];
    if (wordsByLemma.containsKey(input)) {
      final WordRootWord hit = wordsByLemma[input]!;
      return <WordRootSpellCandidate>[
        WordRootSpellCandidate(
          word: hit.word,
          distance: 0,
          gloss: hit.gloss,
          level: hit.level,
        ),
      ];
    }
    final List<WordRootSpellCandidate> candidates = <WordRootSpellCandidate>[];
    for (final WordRootWord w in words) {
      if ((w.word.length - input.length).abs() > maxDist) continue;
      final int d = _levenshtein(input, w.word, maxDist);
      if (d < 0 || d > maxDist) continue;
      candidates.add(
        WordRootSpellCandidate(
          word: w.word,
          distance: d,
          gloss: w.gloss,
          level: w.level,
        ),
      );
    }
    candidates.sort((WordRootSpellCandidate a, WordRootSpellCandidate b) {
      final int byDist = a.distance.compareTo(b.distance);
      return byDist != 0
          ? byDist
          : a.word.length.compareTo(b.word.length);
    });
    return candidates.take(maxCandidates).toList(growable: false);
  }

  /// Convert catalog parse into AffixHit chips used by existing UI.
  List<AffixHit> affixHitsFor(String raw) {
    final WordRootDetail? detail = queryWordDetail(raw);
    if (detail == null || detail.parse.isEmpty) {
      return const <AffixHit>[];
    }
    final List<AffixHit> hits = <AffixHit>[];
    for (final WordRootParsePart part in detail.parse) {
      final String kind = switch (part.type) {
        'prefix' => 'prefix',
        'suffix' => 'suffix',
        _ => part.typeCn == '前缀'
            ? 'prefix'
            : part.typeCn == '后缀'
                ? 'suffix'
                : 'root',
      };
      final List<String> examples = queryRootWords(
        part.rootText,
        limit: 3,
      ).map((WordRootWord w) => w.word).where((String w) => w != detail.word).toList();
      hits.add(
        AffixHit(
          part: part.matchedForm.isNotEmpty ? part.matchedForm : part.rootText,
          kind: kind,
          meaningCn: part.displayMeaning,
          examples: examples,
        ),
      );
    }
    return hits;
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
    return list.take(limit).toList(growable: false);
  }

  /// Bounded Levenshtein; returns -1 when distance exceeds [maxDist].
  static int _levenshtein(String a, String b, int maxDist) {
    if (a == b) return 0;
    final int la = a.length;
    final int lb = b.length;
    if ((la - lb).abs() > maxDist) return -1;
    List<int> prev = List<int>.generate(lb + 1, (int j) => j);
    for (int i = 1; i <= la; i++) {
      final List<int> cur = List<int>.filled(lb + 1, 0);
      cur[0] = i;
      int rowMin = cur[0];
      for (int j = 1; j <= lb; j++) {
        final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = <int>[
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((int x, int y) => x < y ? x : y);
        if (cur[j] < rowMin) rowMin = cur[j];
      }
      if (rowMin > maxDist) return -1;
      prev = cur;
    }
    final int dist = prev[lb];
    return dist > maxDist ? -1 : dist;
  }
}
