import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../sync/data/vocab_sync_service.dart';
import '../data/offline_word_dictionary.dart';
import '../domain/sm2_scheduler.dart';
import '../domain/vocab_card_kind.dart';

export '../domain/vocab_card_kind.dart';

const String _wordBookStorageKey = 'word_book_v1';
const String _reviewStreakKey = 'word_review_streak_v1';

final NotifierProvider<WordBookNotifier, List<WordEntry>> wordBookProvider =
    NotifierProvider<WordBookNotifier, List<WordEntry>>(WordBookNotifier.new);

class WordOccurrence {
  const WordOccurrence({
    required this.episodeId,
    this.videoFileName,
    required this.course,
    required this.episode,
    required this.time,
    required this.sentence,
    required this.chinese,
    required this.count,
    required this.lineKeys,
    required this.contexts,
  });

  factory WordOccurrence.fromJson(Map<String, Object?> json) => WordOccurrence(
    episodeId: json['episodeId']! as String,
    videoFileName: json['videoFileName'] as String?,
    course: json['course']! as String,
    episode: json['episode']! as String,
    time: json['time']! as String,
    sentence: json['sentence']! as String,
    chinese: json['chinese'] as String? ?? '',
    count: json['count'] as int? ?? 1,
    lineKeys: (json['lineKeys'] as List<Object?>? ?? <Object?>[json['time']])
        .cast<String>(),
    contexts:
        (json['contexts'] as List<Object?>?)
            ?.cast<Map<String, Object?>>()
            .map(WordContext.fromJson)
            .toList(growable: false) ??
        <WordContext>[
          WordContext(
            lineKey:
                ((json['lineKeys'] as List<Object?>? ?? <Object?>[json['time']])
                        .first
                    as String?) ??
                json['time']! as String,
            time: json['time']! as String,
            sentence: json['sentence']! as String,
            chinese: json['chinese'] as String? ?? '',
            count: json['count'] as int? ?? 1,
          ),
        ],
  );

  final String episodeId;
  final String? videoFileName;
  final String course;
  final String episode;
  final String time;
  final String sentence;
  final String chinese;
  final int count;
  final List<String> lineKeys;
  final List<WordContext> contexts;

  WordOccurrence copyWith({
    String? episodeId,
    String? course,
    String? episode,
    String? videoFileName,
    int? count,
    List<String>? lineKeys,
    List<WordContext>? contexts,
  }) => WordOccurrence(
    episodeId: episodeId ?? this.episodeId,
    course: course ?? this.course,
    episode: episode ?? this.episode,
    videoFileName: videoFileName ?? this.videoFileName,
    time: time,
    sentence: sentence,
    chinese: chinese,
    count: count ?? this.count,
    lineKeys: lineKeys ?? this.lineKeys,
    contexts: contexts ?? this.contexts,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'episodeId': episodeId,
    'videoFileName': videoFileName,
    'course': course,
    'episode': episode,
    'time': time,
    'sentence': sentence,
    'chinese': chinese,
    'count': count,
    'lineKeys': lineKeys,
    'contexts': contexts.map((WordContext item) => item.toJson()).toList(),
  };
}

class WordContext {
  const WordContext({
    required this.lineKey,
    required this.time,
    required this.sentence,
    required this.chinese,
    required this.count,
    this.apiTranslationCn,
  });

  factory WordContext.fromJson(Map<String, Object?> json) => WordContext(
    lineKey: json['lineKey']! as String,
    time: json['time']! as String,
    sentence: json['sentence']! as String,
    chinese: json['chinese'] as String? ?? '',
    count: json['count'] as int? ?? 1,
    apiTranslationCn: json['apiTranslationCn'] as String?,
  );

  final String lineKey;
  final String time;
  final String sentence;
  final String chinese;
  final int count;
  final String? apiTranslationCn;

  WordContext copyWith({String? apiTranslationCn}) => WordContext(
    lineKey: lineKey,
    time: time,
    sentence: sentence,
    chinese: chinese,
    count: count,
    apiTranslationCn: apiTranslationCn ?? this.apiTranslationCn,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'lineKey': lineKey,
    'time': time,
    'sentence': sentence,
    'chinese': chinese,
    'count': count,
    'apiTranslationCn': apiTranslationCn,
  };
}

class WordEntry {
  const WordEntry({
    required this.word,
    required this.favorite,
    required this.occurrences,
    this.kind = VocabCardKind.word,
    this.definitionCn,
    this.offlineDefinitionCn,
    this.phonetic,
    this.partOfSpeech,
    this.definitionEn,
    this.analysisCn,
    this.mnemonicCn,
    this.aiExampleEn,
    this.aiExampleCn,
    this.enrichmentStatus = VocabEnrichmentStatus.none,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.dueAtMs,
    this.mastery = WordMastery.fresh,
  });

  factory WordEntry.fromJson(Map<String, Object?> json) {
    final String word = json['word']! as String;
    final String? kindRaw = json['kind'] as String?;
    final VocabCardKind kind = kindRaw == null || kindRaw.isEmpty
        ? vocabCardKindForLexeme(word)
        : VocabCardKind.values.firstWhere(
            (VocabCardKind k) => k.name == kindRaw,
            orElse: () => vocabCardKindForLexeme(word),
          );
    return WordEntry(
      word: word,
      favorite: json['favorite'] as bool? ?? false,
      kind: kind,
      definitionCn: json['definitionCn'] as String?,
      offlineDefinitionCn: json['offlineDefinitionCn'] as String?,
      phonetic: json['phonetic'] as String?,
      partOfSpeech: json['partOfSpeech'] as String?,
      definitionEn: json['definitionEn'] as String?,
      analysisCn: json['analysisCn'] as String?,
      mnemonicCn: json['mnemonicCn'] as String?,
      aiExampleEn: json['aiExampleEn'] as String?,
      aiExampleCn: json['aiExampleCn'] as String?,
      enrichmentStatus: vocabEnrichmentStatusFromName(
        json['enrichmentStatus'] as String?,
      ),
      occurrences: (json['occurrences'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map(WordOccurrence.fromJson)
          .toList(growable: false),
      ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
      intervalDays: json['intervalDays'] as int? ?? 0,
      repetitions: json['repetitions'] as int? ?? 0,
      dueAtMs: (json['dueAtMs'] as num?)?.toInt(),
      mastery: Sm2Scheduler.masteryFromName(json['mastery'] as String?),
    );
  }

  final String word;
  final bool favorite;
  final VocabCardKind kind;
  final String? definitionCn;
  final String? offlineDefinitionCn;
  final String? phonetic;
  final String? partOfSpeech;
  final String? definitionEn;
  final String? analysisCn;
  final String? mnemonicCn;
  final String? aiExampleEn;
  final String? aiExampleCn;
  final VocabEnrichmentStatus enrichmentStatus;
  final List<WordOccurrence> occurrences;
  final double ease;
  final int intervalDays;
  final int repetitions;
  final int? dueAtMs;
  final WordMastery mastery;

  int get videoCount => occurrences.length;
  int get occurrenceCount => occurrences.fold<int>(
    0,
    (int total, WordOccurrence item) => total + item.count,
  );

  String get sourceSentence {
    if (occurrences.isEmpty) {
      return '';
    }
    final WordOccurrence first = occurrences.first;
    if (first.contexts.isNotEmpty) {
      return first.contexts.first.sentence.trim();
    }
    return first.sentence.trim();
  }

  String get sourceSentenceCn {
    if (occurrences.isEmpty) {
      return '';
    }
    final WordOccurrence first = occurrences.first;
    if (first.contexts.isNotEmpty) {
      return first.contexts.first.chinese.trim();
    }
    return first.chinese.trim();
  }

  bool get isDue {
    if (dueAtMs == null) {
      return true;
    }
    return DateTime.now().millisecondsSinceEpoch >= dueAtMs!;
  }

  Sm2State get sm2 => Sm2State(
    ease: ease,
    intervalDays: intervalDays,
    repetitions: repetitions,
    dueAt: dueAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(dueAtMs!),
    mastery: mastery,
  );

  WordEntry copyWith({
    bool? favorite,
    VocabCardKind? kind,
    List<WordOccurrence>? occurrences,
    String? definitionCn,
    String? offlineDefinitionCn,
    String? phonetic,
    String? partOfSpeech,
    String? definitionEn,
    String? analysisCn,
    String? mnemonicCn,
    String? aiExampleEn,
    String? aiExampleCn,
    VocabEnrichmentStatus? enrichmentStatus,
    double? ease,
    int? intervalDays,
    int? repetitions,
    int? dueAtMs,
    WordMastery? mastery,
  }) => WordEntry(
    word: word,
    favorite: favorite ?? this.favorite,
    kind: kind ?? this.kind,
    occurrences: occurrences ?? this.occurrences,
    definitionCn: definitionCn ?? this.definitionCn,
    offlineDefinitionCn: offlineDefinitionCn ?? this.offlineDefinitionCn,
    phonetic: phonetic ?? this.phonetic,
    partOfSpeech: partOfSpeech ?? this.partOfSpeech,
    definitionEn: definitionEn ?? this.definitionEn,
    analysisCn: analysisCn ?? this.analysisCn,
    mnemonicCn: mnemonicCn ?? this.mnemonicCn,
    aiExampleEn: aiExampleEn ?? this.aiExampleEn,
    aiExampleCn: aiExampleCn ?? this.aiExampleCn,
    enrichmentStatus: enrichmentStatus ?? this.enrichmentStatus,
    ease: ease ?? this.ease,
    intervalDays: intervalDays ?? this.intervalDays,
    repetitions: repetitions ?? this.repetitions,
    dueAtMs: dueAtMs ?? this.dueAtMs,
    mastery: mastery ?? this.mastery,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'word': word,
    'favorite': favorite,
    'kind': kind.name,
    'definitionCn': definitionCn,
    'offlineDefinitionCn': offlineDefinitionCn,
    'phonetic': phonetic,
    'partOfSpeech': partOfSpeech,
    'definitionEn': definitionEn,
    'analysisCn': analysisCn,
    'mnemonicCn': mnemonicCn,
    'aiExampleEn': aiExampleEn,
    'aiExampleCn': aiExampleCn,
    'enrichmentStatus': enrichmentStatus.name,
    'occurrences': occurrences
        .map((WordOccurrence item) => item.toJson())
        .toList(),
    'ease': ease,
    'intervalDays': intervalDays,
    'repetitions': repetitions,
    'dueAtMs': dueAtMs,
    'mastery': mastery.name,
  };
}

class WordBookNotifier extends Notifier<List<WordEntry>> {
  final Set<String> _pendingOfflineDefinitions = <String>{};
  @override
  List<WordEntry> build() {
    if (!Hive.isBoxOpen('prefs')) return const <WordEntry>[];
    final String? stored = Hive.box<String>('prefs').get(_wordBookStorageKey);
    if (stored == null || stored.isEmpty) return const <WordEntry>[];
    try {
      return (jsonDecode(stored) as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(WordEntry.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <WordEntry>[];
    }
  }

  Future<void> recordLine({
    required String english,
    required String episodeId,
    String? videoFileName,
    required String course,
    required String episode,
    required String time,
    required String lineKey,
    required String chinese,
    Map<String, String> generatedDefinitions = const <String, String>{},
  }) async {
    final Map<String, int> rawWordCounts = <String, int>{};
    for (final String word in tokenizeWords(english)) {
      rawWordCounts[word] = (rawWordCounts[word] ?? 0) + 1;
    }
    if (rawWordCounts.isEmpty) return;
    final OfflineWordDictionary dictionary = ref.read(
      offlineWordDictionaryProvider,
    );
    final List<OfflineWordDefinition?> definitions = await Future.wait(
      rawWordCounts.keys.map(dictionary.lookup),
    );
    final Map<String, int> wordCounts = <String, int>{
      for (int index = 0; index < rawWordCounts.length; index++)
        if (definitions[index] != null)
          rawWordCounts.keys.elementAt(index): rawWordCounts.values.elementAt(
            index,
          ),
    };
    if (wordCounts.isEmpty) return;
    final Map<String, WordEntry> entries = <String, WordEntry>{
      for (final WordEntry item in state) item.word: item,
    };
    bool changed = false;
    for (final MapEntry<String, int> entry in wordCounts.entries) {
      final String word = entry.key;
      final WordEntry? current = entries[word];
      final int occurrenceIndex =
          current?.occurrences.indexWhere(
            (WordOccurrence item) => item.episodeId == episodeId,
          ) ??
          -1;
      if (occurrenceIndex >= 0 &&
          current!.occurrences[occurrenceIndex].lineKeys.contains(lineKey)) {
        continue;
      }
      if (occurrenceIndex < 0) {
        final WordOccurrence occurrence = WordOccurrence(
          episodeId: episodeId,
          videoFileName: videoFileName,
          course: course,
          episode: episode,
          time: time,
          sentence: english.trim(),
          chinese: chinese.trim(),
          count: entry.value,
          lineKeys: <String>[lineKey],
          contexts: <WordContext>[
            WordContext(
              lineKey: lineKey,
              time: time,
              sentence: english.trim(),
              chinese: chinese.trim(),
              count: entry.value,
            ),
          ],
        );
        entries[word] = current == null
            ? WordEntry(
                word: word,
                favorite: false,
                occurrences: <WordOccurrence>[occurrence],
              )
            : current.copyWith(
                occurrences: <WordOccurrence>[
                  ...current.occurrences,
                  occurrence,
                ],
              );
      } else {
        final List<WordOccurrence> occurrences = <WordOccurrence>[
          ...current!.occurrences,
        ];
        final WordOccurrence previous = occurrences[occurrenceIndex];
        occurrences[occurrenceIndex] = previous.copyWith(
          count: previous.count + entry.value,
          lineKeys: <String>[...previous.lineKeys, lineKey],
          contexts: <WordContext>[
            ...previous.contexts,
            WordContext(
              lineKey: lineKey,
              time: time,
              sentence: english.trim(),
              chinese: chinese.trim(),
              count: entry.value,
            ),
          ],
        );
        entries[word] = current.copyWith(occurrences: occurrences);
      }
      changed = true;
    }
    bool definitionsChanged = false;
    for (final String word in wordCounts.keys) {
      final String? definition = generatedDefinitions[word]?.trim();
      final WordEntry? entry = entries[word];
      if (entry != null &&
          entry.definitionCn == null &&
          definition != null &&
          definition.isNotEmpty) {
        entries[word] = entry.copyWith(definitionCn: definition);
        definitionsChanged = true;
      }
    }
    if (!changed && !definitionsChanged) return;
    state = entries.values.toList()
      ..sort((WordEntry a, WordEntry b) => a.word.compareTo(b.word));
    unawaited(_persist());
    unawaited(_fillOfflineDefinitions(wordCounts.keys));
  }

  bool? toggleFavorite(String rawWord) {
    final String word = normalizeLexeme(rawWord);
    if (word.isEmpty) return null;
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (index < 0) return null;
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(favorite: !next[index].favorite);
    state = next;
    unawaited(_persist());
    final WordEntry updated = state[index];
    if (updated.favorite) {
      unawaited(ref.read(vocabSyncServiceProvider).pushEntry(updated));
    }
    return updated.favorite;
  }

  bool addFavoriteWord({
    required String rawWord,
    required String episodeId,
    String? videoFileName,
    required String course,
    required String episode,
    required String time,
    required String lineKey,
    required String sentence,
    required String chinese,
    String? generatedDefinition,
    VocabCardKind? cardKind,
  }) {
    final String word = normalizeLexeme(rawWord);
    if (word.isEmpty || (cardKind == null && !_isFavoriteableLexeme(word))) {
      return false;
    }
    final String? definition = generatedDefinition?.trim();
    final String? validDefinition = definition == null || definition.isEmpty
        ? null
        : definition;
    final int count = tokenizeWords(
      sentence,
    ).where((String item) => item == word).length;
    final int entryIndex = state.indexWhere(
      (WordEntry item) => item.word == word,
    );
    final WordContext context = WordContext(
      lineKey: lineKey,
      time: time,
      sentence: sentence.trim(),
      chinese: chinese.trim(),
      count: count == 0 ? 1 : count,
    );
    final VocabCardKind kind = cardKind ?? vocabCardKindForLexeme(word);
    if (entryIndex < 0) {
      state = <WordEntry>[
        WordEntry(
          word: word,
          favorite: true,
          kind: kind,
          definitionCn: validDefinition,
          enrichmentStatus: VocabEnrichmentStatus.pending,
          occurrences: <WordOccurrence>[
            WordOccurrence(
              episodeId: episodeId,
              videoFileName: videoFileName,
              course: course,
              episode: episode,
              time: time,
              sentence: sentence.trim(),
              chinese: chinese.trim(),
              count: context.count,
              lineKeys: <String>[lineKey],
              contexts: <WordContext>[context],
            ),
          ],
        ),
        ...state,
      ];
    } else {
      final WordEntry entry = state[entryIndex];
      final List<WordOccurrence> occurrences = entry.occurrences
          .map((WordOccurrence occurrence) {
            if (occurrence.episodeId != episodeId ||
                occurrence.lineKeys.contains(lineKey)) {
              return occurrence;
            }
            return occurrence.copyWith(
              count: occurrence.count + context.count,
              lineKeys: <String>[...occurrence.lineKeys, lineKey],
              contexts: <WordContext>[...occurrence.contexts, context],
            );
          })
          .toList(growable: true);
      if (!occurrences.any(
        (WordOccurrence item) => item.episodeId == episodeId,
      )) {
        occurrences.add(
          WordOccurrence(
            episodeId: episodeId,
            videoFileName: videoFileName,
            course: course,
            episode: episode,
            time: time,
            sentence: sentence.trim(),
            chinese: chinese.trim(),
            count: context.count,
            lineKeys: <String>[lineKey],
            contexts: <WordContext>[context],
          ),
        );
      }
      final List<WordEntry> next = <WordEntry>[...state];
      next[entryIndex] = entry.copyWith(
        favorite: true,
        kind: entry.kind == VocabCardKind.word ? kind : entry.kind,
        occurrences: occurrences,
        definitionCn: entry.definitionCn ?? validDefinition,
        enrichmentStatus:
            entry.enrichmentStatus == VocabEnrichmentStatus.ready
            ? VocabEnrichmentStatus.ready
            : VocabEnrichmentStatus.pending,
      );
      state = next;
    }
    unawaited(_persist());
    unawaited(_fillOfflineDefinitions(<String>[word]));
    final int favIndex = state.indexWhere((WordEntry e) => e.word == word);
    if (favIndex >= 0 && state[favIndex].favorite) {
      unawaited(ref.read(vocabSyncServiceProvider).pushEntry(state[favIndex]));
    }
    return true;
  }

  void markEnrichmentPending(String rawWord) {
    final String word = normalizeLexeme(rawWord);
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (index < 0) {
      return;
    }
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(
      enrichmentStatus: VocabEnrichmentStatus.pending,
    );
    state = next;
    unawaited(_persist());
  }

  void applyEnrichment({
    required String rawWord,
    String? phonetic,
    String? partOfSpeech,
    String? definitionCn,
    String? definitionEn,
    String? analysisCn,
    String? mnemonicCn,
    String? aiExampleEn,
    String? aiExampleCn,
    required VocabEnrichmentStatus status,
  }) {
    final String word = normalizeLexeme(rawWord);
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (index < 0) {
      return;
    }
    final WordEntry entry = state[index];
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = entry.copyWith(
      phonetic: _prefer(phonetic, entry.phonetic),
      partOfSpeech: _prefer(partOfSpeech, entry.partOfSpeech),
      definitionCn: _prefer(definitionCn, entry.definitionCn),
      definitionEn: _prefer(definitionEn, entry.definitionEn),
      analysisCn: _prefer(analysisCn, entry.analysisCn),
      mnemonicCn: _prefer(mnemonicCn, entry.mnemonicCn),
      aiExampleEn: _prefer(aiExampleEn, entry.aiExampleEn),
      aiExampleCn: _prefer(aiExampleCn, entry.aiExampleCn),
      enrichmentStatus: status,
    );
    state = next;
    unawaited(_persist());
  }

  static String? _prefer(String? incoming, String? existing) {
    final String? next = incoming?.trim();
    if (next != null && next.isNotEmpty) {
      return next;
    }
    return existing;
  }

  Future<void> relinkEpisode({
    required String oldEpisodeId,
    required String newEpisodeId,
    required String course,
    required String episode,
    required String videoFileName,
  }) async {
    final List<WordEntry> previous = state;
    final List<WordEntry> updated = state.map((WordEntry entry) {
      if (!entry.occurrences.any(
        (WordOccurrence o) => o.episodeId == oldEpisodeId,
      )) {
        return entry;
      }
      final List<WordOccurrence> occurrences = <WordOccurrence>[];
      for (final WordOccurrence old in entry.occurrences) {
        final WordOccurrence item = old.episodeId == oldEpisodeId
            ? old.copyWith(
                episodeId: newEpisodeId,
                course: course,
                episode: episode,
                videoFileName: videoFileName,
              )
            : old;
        final int index = occurrences.indexWhere(
          (WordOccurrence o) => o.episodeId == item.episodeId,
        );
        if (index < 0) {
          occurrences.add(item);
          continue;
        }
        final WordOccurrence existing = occurrences[index];
        final Map<String, WordContext> contexts = <String, WordContext>{
          for (final WordContext c in existing.contexts) c.lineKey: c,
        };
        for (final WordContext c in item.contexts) {
          final WordContext? stored = contexts[c.lineKey];
          contexts[c.lineKey] = stored == null
              ? c
              : stored.copyWith(
                  apiTranslationCn:
                      stored.apiTranslationCn ?? c.apiTranslationCn,
                );
        }
        occurrences[index] = existing.copyWith(
          course: item.episodeId == newEpisodeId ? course : null,
          episode: item.episodeId == newEpisodeId ? episode : null,
          videoFileName: item.episodeId == newEpisodeId ? videoFileName : null,
          contexts: contexts.values.toList(),
          lineKeys: <String>{...existing.lineKeys, ...item.lineKeys}.toList(),
          count: contexts.values.fold<int>(
            0,
            (int n, WordContext c) => n + c.count,
          ),
        );
      }
      return entry.copyWith(occurrences: occurrences);
    }).toList();
    // Write the complete replacement once; leave current state intact on failure.
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(
        _wordBookStorageKey,
        jsonEncode(updated.map((WordEntry e) => e.toJson()).toList()),
      );
    }
    if (identical(state, previous)) {
      state = updated;
    } else {
      await relinkEpisode(
        oldEpisodeId: oldEpisodeId,
        newEpisodeId: newEpisodeId,
        course: course,
        episode: episode,
        videoFileName: videoFileName,
      );
    }
  }

  void setDefinition(String rawWord, String definitionCn) {
    final String word = normalizeWord(rawWord);
    final String definition = definitionCn.trim();
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (definition.isEmpty ||
        index < 0 ||
        state[index].definitionCn == definition) {
      return;
    }
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(definitionCn: definition);
    state = next;
    unawaited(_persist());
  }

  bool editWord({
    required String rawWord,
    required String nextWord,
    required String definitionCn,
  }) {
    final String word = normalizeWord(rawWord);
    final String updatedWord = normalizeWord(nextWord);
    final int index = state.indexWhere((WordEntry entry) => entry.word == word);
    if (updatedWord.isEmpty || index < 0) return false;
    if (updatedWord != word &&
        state.any((WordEntry item) => item.word == updatedWord)) {
      return false;
    }
    final WordEntry entry = state[index];
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = entry.copyWith(
      definitionCn: definitionCn.trim().isEmpty ? null : definitionCn.trim(),
      offlineDefinitionCn: updatedWord == word
          ? entry.offlineDefinitionCn
          : null,
      kind: updatedWord == word
          ? entry.kind
          : vocabCardKindForLexeme(updatedWord),
    );
    // Renaming requires a fresh WordEntry because `word` is final.
    if (updatedWord != word) {
      next[index] = WordEntry(
        word: updatedWord,
        favorite: entry.favorite,
        kind: vocabCardKindForLexeme(updatedWord),
        occurrences: entry.occurrences,
        definitionCn: definitionCn.trim().isEmpty ? null : definitionCn.trim(),
        offlineDefinitionCn: null,
        phonetic: entry.phonetic,
        partOfSpeech: entry.partOfSpeech,
        definitionEn: entry.definitionEn,
        analysisCn: entry.analysisCn,
        mnemonicCn: entry.mnemonicCn,
        aiExampleEn: entry.aiExampleEn,
        aiExampleCn: entry.aiExampleCn,
        enrichmentStatus: entry.enrichmentStatus,
        ease: entry.ease,
        intervalDays: entry.intervalDays,
        repetitions: entry.repetitions,
        dueAtMs: entry.dueAtMs,
        mastery: entry.mastery,
      );
    }
    next.sort((WordEntry a, WordEntry b) => a.word.compareTo(b.word));
    state = next;
    unawaited(_persist());
    if (updatedWord != word) {
      unawaited(_fillOfflineDefinitions(<String>[updatedWord]));
    }
    return true;
  }

  bool deleteWord(String rawWord) {
    final String word = normalizeWord(rawWord);
    final List<WordEntry> next = state
        .where((WordEntry entry) => entry.word != word)
        .toList(growable: false);
    if (next.length == state.length) return false;
    state = next;
    unawaited(_persist());
    return true;
  }

  void refreshOfflineDefinitions() {
    unawaited(
      _removeInvalidWords().then((_) {
        return _fillOfflineDefinitions(
          state.map((WordEntry entry) => entry.word),
        );
      }),
    );
  }

  Future<void> _removeInvalidWords() async {
    final List<WordEntry> candidates = state
        .where((WordEntry entry) => _isIndependentEnglishWord(entry.word))
        .toList(growable: false);
    try {
      final OfflineWordDictionary dictionary = ref.read(
        offlineWordDictionaryProvider,
      );
      final List<OfflineWordDefinition?> definitions = await Future.wait(
        candidates.map((WordEntry entry) => dictionary.lookup(entry.word)),
      );
      final Set<String> validWords = <String>{
        for (int index = 0; index < candidates.length; index++)
          if (definitions[index] != null) candidates[index].word,
      };
      final List<WordEntry> next = state
          // A dictionary miss is not evidence that a saved word is invalid.
          // Favorites are user data, including inflections and custom entries.
          .where(
            (WordEntry entry) =>
                entry.favorite || validWords.contains(entry.word),
          )
          .toList(growable: false);
      if (next.length == state.length) return;
      state = next;
      unawaited(_persist());
    } catch (_) {
      // Keep existing entries if the optional offline dictionary is unavailable.
    }
  }

  Future<void> _fillOfflineDefinitions(Iterable<String> words) async {
    final List<String> pending = words
        .where(
          (String word) =>
              state.any(
                (WordEntry entry) =>
                    entry.word == word && entry.offlineDefinitionCn == null,
              ) &&
              _pendingOfflineDefinitions.add(word),
        )
        .toList(growable: false);
    if (pending.isEmpty) return;
    try {
      final OfflineWordDictionary dictionary = ref.read(
        offlineWordDictionaryProvider,
      );
      final List<OfflineWordDefinition?> definitions = await Future.wait(
        pending.map(dictionary.lookup),
      );
      final Map<String, String> translations = <String, String>{
        for (int index = 0; index < pending.length; index++)
          if (definitions[index]?.translation.isNotEmpty ?? false)
            pending[index]: definitions[index]!.translation,
      };
      if (translations.isEmpty) return;
      state = state
          .map(
            (WordEntry entry) => translations.containsKey(entry.word)
                ? entry.copyWith(offlineDefinitionCn: translations[entry.word])
                : entry,
          )
          .toList(growable: false);
      unawaited(_persist());
    } catch (_) {
      // The word is still saved even if the optional offline dictionary is unavailable.
    } finally {
      _pendingOfflineDefinitions.removeAll(pending);
    }
  }

  void setContextTranslation({
    required String rawWord,
    required String episodeId,
    required String lineKey,
    required String translation,
  }) {
    final int wordIndex = state.indexWhere(
      (WordEntry item) => item.word == normalizeWord(rawWord),
    );
    if (wordIndex < 0 || translation.trim().isEmpty) return;
    final WordEntry entry = state[wordIndex];
    final List<WordOccurrence> occurrences = entry.occurrences
        .map((WordOccurrence occurrence) {
          if (occurrence.episodeId != episodeId) return occurrence;
          return occurrence.copyWith(
            contexts: occurrence.contexts
                .map((WordContext context) {
                  return context.lineKey == lineKey
                      ? context.copyWith(apiTranslationCn: translation.trim())
                      : context;
                })
                .toList(growable: false),
          );
        })
        .toList(growable: false);
    final List<WordEntry> next = <WordEntry>[...state];
    next[wordIndex] = entry.copyWith(occurrences: occurrences);
    state = next;
    unawaited(_persist());
  }

  List<WordEntry> dueQueue({int newWordLimit = 20}) {
    final List<WordEntry> due = state
        .where((WordEntry e) => e.isDue)
        .toList(growable: false)
      ..sort((WordEntry a, WordEntry b) {
        final int byMastery = a.mastery.index.compareTo(b.mastery.index);
        if (byMastery != 0) return byMastery;
        return (a.dueAtMs ?? 0).compareTo(b.dueAtMs ?? 0);
      });
    final List<WordEntry> fresh = due
        .where((WordEntry e) => e.mastery == WordMastery.fresh)
        .take(newWordLimit)
        .toList(growable: false);
    final List<WordEntry> review = due
        .where((WordEntry e) => e.mastery != WordMastery.fresh)
        .toList(growable: false);
    return <WordEntry>[...fresh, ...review];
  }

  Future<WordEntry?> reviewWithGrade(String word, Sm2Grade grade) async {
    const Sm2Scheduler scheduler = Sm2Scheduler();
    WordEntry? updated;
    state = state
        .map((WordEntry entry) {
          if (entry.word != word) {
            return entry;
          }
          final Sm2State next = scheduler.review(entry.sm2, grade);
          updated = entry.copyWith(
            ease: next.ease,
            intervalDays: next.intervalDays,
            repetitions: next.repetitions,
            dueAtMs: next.dueAt?.millisecondsSinceEpoch,
            mastery: next.mastery,
            favorite: true,
          );
          return updated!;
        })
        .toList(growable: false);
    await _persist();
    await _bumpStreak();
    return updated;
  }

  /// Import a cloud favorite; keep local SRS when local reps are ahead.
  Future<void> mergeRemoteFavorite({
    required String word,
    String? contextSentence,
  }) async {
    await mergeRemoteSrs(
      word: word,
      mastery: WordMastery.fresh,
      ease: 2.5,
      intervalDays: 0,
      repetitions: 0,
      dueAtMs: null,
      contextSentence: contextSentence,
      favoriteOnly: true,
    );
  }

  /// Merge cloud SM-2 fields. Local wins when it has more repetitions.
  Future<void> mergeRemoteSrs({
    required String word,
    required WordMastery mastery,
    required double ease,
    required int intervalDays,
    required int repetitions,
    int? dueAtMs,
    String? contextSentence,
    bool favoriteOnly = false,
  }) async {
    final String key = word.trim().toLowerCase();
    if (key.isEmpty) {
      return;
    }
    final int index = state.indexWhere(
      (WordEntry e) => e.word.toLowerCase() == key,
    );
    if (index >= 0) {
      final WordEntry existing = state[index];
      final List<WordEntry> next = List<WordEntry>.from(state);
      final bool keepLocalSrs =
          favoriteOnly || existing.repetitions >= repetitions;
      next[index] = existing.copyWith(
        favorite: true,
        ease: keepLocalSrs ? existing.ease : ease,
        intervalDays: keepLocalSrs ? existing.intervalDays : intervalDays,
        repetitions: keepLocalSrs ? existing.repetitions : repetitions,
        dueAtMs: keepLocalSrs ? existing.dueAtMs : dueAtMs,
        mastery: keepLocalSrs ? existing.mastery : mastery,
      );
      state = next;
      await _persist();
      return;
    }
    state = <WordEntry>[
      ...state,
      WordEntry(
        word: key,
        favorite: true,
        mastery: favoriteOnly ? WordMastery.fresh : mastery,
        ease: favoriteOnly ? 2.5 : ease,
        intervalDays: favoriteOnly ? 0 : intervalDays,
        repetitions: favoriteOnly ? 0 : repetitions,
        dueAtMs: favoriteOnly ? null : dueAtMs,
        occurrences: contextSentence == null || contextSentence.isEmpty
            ? const <WordOccurrence>[]
            : <WordOccurrence>[
                WordOccurrence(
                  episodeId: 'remote',
                  course: '云同步',
                  episode: '',
                  time: '',
                  sentence: contextSentence,
                  chinese: '',
                  count: 1,
                  lineKeys: const <String>['remote'],
                  contexts: <WordContext>[
                    WordContext(
                      lineKey: 'remote',
                      time: '',
                      sentence: contextSentence,
                      chinese: '',
                      count: 1,
                    ),
                  ],
                ),
              ],
      ),
    ];
    await _persist();
  }

  int reviewStreak() {
    if (!Hive.isBoxOpen('prefs')) {
      return 0;
    }
    final String? raw = Hive.box<String>('prefs').get(_reviewStreakKey);
    if (raw == null || raw.isEmpty) {
      return 0;
    }
    try {
      final Map<String, dynamic> json =
          jsonDecode(raw) as Map<String, dynamic>;
      return json['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _bumpStreak() async {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    final String today = DateTime.now().toIso8601String().substring(0, 10);
    final Box<String> box = Hive.box<String>('prefs');
    final String? raw = box.get(_reviewStreakKey);
    int count = 0;
    String? lastDay;
    if (raw != null && raw.isNotEmpty) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(raw) as Map<String, dynamic>;
        count = json['count'] as int? ?? 0;
        lastDay = json['day'] as String?;
      } catch (_) {}
    }
    if (lastDay == today) {
      return;
    }
    final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    final String y = yesterday.toIso8601String().substring(0, 10);
    count = lastDay == y ? count + 1 : 1;
    await box.put(
      _reviewStreakKey,
      jsonEncode(<String, Object?>{'day': today, 'count': count}),
    );
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      _wordBookStorageKey,
      jsonEncode(state.map((WordEntry item) => item.toJson()).toList()),
    );
  }
}

List<String> tokenizeWords(String sentence) =>
    RegExp("(?<![A-Za-z'’])[A-Za-z]{2,}(?![A-Za-z'’])")
        .allMatches(sentence)
        .map((Match match) => normalizeWord(match.group(0)!))
        .where(_isIndependentEnglishWord)
        .toList(growable: false);

String normalizeWord(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'^[^A-Za-z0-9_]+|[^A-Za-z0-9_]+$'), '');

/// Single word or short English phrase for vocabulary cards.
String normalizeLexeme(String value) {
  final String trimmed = value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[^a-z0-9\s']+"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (!trimmed.contains(' ')) {
    return normalizeWord(trimmed);
  }
  return trimmed;
}

bool _isIndependentEnglishWord(String word) =>
    RegExp(r'^[a-z]{2,}$').hasMatch(word);

bool _isFavoriteableLexeme(String word) {
  if (_isIndependentEnglishWord(word)) {
    return true;
  }
  // Up to ~12 tokens so short sentence patterns can live on 词卡.
  return RegExp(r"^[a-z]{2,}(?:\s+[a-z']{1,}){1,11}$").hasMatch(word);
}
