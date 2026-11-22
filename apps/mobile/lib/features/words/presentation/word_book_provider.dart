import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../idle_jobs/idle_job_queue.dart';
import '../../idle_jobs/idle_job_scheduler.dart';
import '../../sync/data/schedule_device_cloud_sync.dart';
import '../../sync/data/vocab_sync_service.dart';
import '../data/offline_word_dictionary.dart';
import '../domain/sm2_scheduler.dart';
import '../domain/vocab_card_kind.dart';
import '../domain/vocab_entry.dart';

import 'vocabulary_placement_provider.dart';

export '../domain/vocab_card_kind.dart';
export '../domain/vocab_entry.dart';

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

  /// Video / article / book badge for multi-source labels.
  String get mediaKind {
    final String id = episodeId.trim();
    final String c = course.trim();
    if (id.startsWith('scene:') || c == '数字人识物') return '拍照';
    if (id.startsWith('reading:') || c.startsWith('阅读')) {
      return '文章';
    }
    if (id.startsWith('book:') ||
        c.contains('词书') ||
        c.contains('书籍') ||
        c.contains('Syllabus') ||
        c.startsWith('公共词库')) {
      return '书籍';
    }
    if (id.isEmpty) return '其他';
    return '视频';
  }

  /// Earliest timeline hit in this episode (same video → first clip).
  WordContext? get earliestContext {
    if (contexts.isEmpty) return null;
    WordContext best = contexts.first;
    int? bestMs = contextStartMs(best);
    for (final WordContext ctx in contexts.skip(1)) {
      final int? ms = contextStartMs(ctx);
      if (ms == null) continue;
      if (bestMs == null || ms < bestMs) {
        best = ctx;
        bestMs = ms;
      }
    }
    return best;
  }

  static int? contextStartMs(WordContext ctx) {
    final Match? match = RegExp(r'^(\d+)').firstMatch(ctx.lineKey.trim());
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return _parseClockToMs(ctx.time);
  }

  static int? _parseClockToMs(String raw) {
    final String time = raw.trim();
    if (time.isEmpty) return null;
    final List<int?> parts = time
        .split(':')
        .map((String part) => int.tryParse(part.trim()))
        .toList(growable: false);
    if (parts.isEmpty || parts.any((int? part) => part == null)) return null;
    if (parts.length == 3) {
      return ((parts[0]! * 60 + parts[1]!) * 60 + parts[2]!) * 1000;
    }
    if (parts.length == 2) {
      return (parts[0]! * 60 + parts[1]!) * 1000;
    }
    return null;
  }

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
    this.rootsAffixesCn,
    this.etymologyCn,
    this.aiExampleEn,
    this.aiExampleCn,
    this.enrichmentStatus = VocabEnrichmentStatus.none,
    this.scheduleStatus = VocabScheduleStatus.pending,
    this.tags = const <String>[],
    this.groupIds = const <String>[],
    this.note = '',
    this.senses = const <VocabSense>[],
    this.freqRank,
    this.cefr,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.dueAtMs,
    this.mastery = WordMastery.fresh,
    this.updatedAtMs,
    this.collectedAtMs,
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
    final bool favorite = json['favorite'] as bool? ?? false;
    final int? freqRank = (json['freqRank'] as num?)?.toInt();
    return WordEntry(
      word: word,
      favorite: favorite,
      kind: kind,
      definitionCn: json['definitionCn'] as String?,
      offlineDefinitionCn: json['offlineDefinitionCn'] as String?,
      phonetic: json['phonetic'] as String?,
      partOfSpeech: json['partOfSpeech'] as String?,
      definitionEn: json['definitionEn'] as String?,
      analysisCn: json['analysisCn'] as String?,
      mnemonicCn: json['mnemonicCn'] as String?,
      rootsAffixesCn: json['rootsAffixesCn'] as String?,
      etymologyCn: json['etymologyCn'] as String?,
      aiExampleEn: json['aiExampleEn'] as String?,
      aiExampleCn: json['aiExampleCn'] as String?,
      enrichmentStatus: vocabEnrichmentStatusFromName(
        json['enrichmentStatus'] as String?,
      ),
      scheduleStatus: VocabScheduleStatusX.parse(
        json['scheduleStatus'] as String?,
        favorite: favorite,
      ),
      tags: (json['tags'] as List<Object?>? ?? const <Object?>[])
          .map((Object? e) => '$e')
          .where((String t) => t.isNotEmpty)
          .toList(growable: false),
      groupIds: (json['groupIds'] as List<Object?>? ?? const <Object?>[])
          .map((Object? e) => '$e')
          .where((String t) => t.isNotEmpty)
          .toList(growable: false),
      note: json['note'] as String? ?? '',
      senses: (json['senses'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map(VocabSense.fromJson)
          .toList(growable: false),
      freqRank: freqRank,
      cefr: json['cefr'] as String? ?? cefrFromFreqRank(freqRank),
      occurrences: (json['occurrences'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map(WordOccurrence.fromJson)
          .toList(growable: false),
      ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
      intervalDays: json['intervalDays'] as int? ?? 0,
      repetitions: json['repetitions'] as int? ?? 0,
      dueAtMs: (json['dueAtMs'] as num?)?.toInt(),
      mastery: Sm2Scheduler.masteryFromName(json['mastery'] as String?),
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt(),
      collectedAtMs: (json['collectedAtMs'] as num?)?.toInt(),
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
  final String? rootsAffixesCn;
  final String? etymologyCn;
  final String? aiExampleEn;
  final String? aiExampleCn;
  final VocabEnrichmentStatus enrichmentStatus;
  final VocabScheduleStatus scheduleStatus;
  final List<String> tags;
  final List<String> groupIds;
  final String note;
  final List<VocabSense> senses;
  final int? freqRank;
  final String? cefr;
  final List<WordOccurrence> occurrences;
  final double ease;
  final int intervalDays;
  final int repetitions;
  final int? dueAtMs;
  final WordMastery mastery;

  /// Client clock for cross-device LWW merge; optional for legacy rows.
  final int? updatedAtMs;
  final int? collectedAtMs;

  String get entryId => vocabEntryIdForLemma(word);

  /// Pending favorites still join the daily queue (video/阅读收藏后应能复习);
  /// only 斩掉/归档 leaves the schedule.
  bool get isSchedulable =>
      favorite && scheduleStatus != VocabScheduleStatus.archived;

  bool get hasVideoContext => occurrences.any(
    (WordOccurrence o) => o.episodeId.trim().isNotEmpty,
  );

  String get primaryGloss {
    for (final VocabSense sense in senses) {
      if (sense.isPrimary && sense.gloss.trim().isNotEmpty) {
        return sense.gloss.trim();
      }
    }
    if (senses.isNotEmpty && senses.first.gloss.trim().isNotEmpty) {
      return senses.first.gloss.trim();
    }
    final String def = (definitionCn ?? offlineDefinitionCn ?? '').trim();
    return def;
  }

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
    final WordContext? ctx = first.earliestContext;
    if (ctx != null) {
      return ctx.sentence.trim();
    }
    return first.sentence.trim();
  }

  String get sourceSentenceCn {
    if (occurrences.isEmpty) {
      return '';
    }
    final WordOccurrence first = occurrences.first;
    final WordContext? ctx = first.earliestContext;
    if (ctx != null) {
      return ctx.chinese.trim();
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
    String? rootsAffixesCn,
    String? etymologyCn,
    String? aiExampleEn,
    String? aiExampleCn,
    VocabEnrichmentStatus? enrichmentStatus,
    VocabScheduleStatus? scheduleStatus,
    List<String>? tags,
    List<String>? groupIds,
    String? note,
    List<VocabSense>? senses,
    int? freqRank,
    String? cefr,
    double? ease,
    int? intervalDays,
    int? repetitions,
    int? dueAtMs,
    WordMastery? mastery,
    int? updatedAtMs,
    int? collectedAtMs,
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
    rootsAffixesCn: rootsAffixesCn ?? this.rootsAffixesCn,
    etymologyCn: etymologyCn ?? this.etymologyCn,
    aiExampleEn: aiExampleEn ?? this.aiExampleEn,
    aiExampleCn: aiExampleCn ?? this.aiExampleCn,
    enrichmentStatus: enrichmentStatus ?? this.enrichmentStatus,
    scheduleStatus: scheduleStatus ?? this.scheduleStatus,
    tags: tags ?? this.tags,
    groupIds: groupIds ?? this.groupIds,
    note: note ?? this.note,
    senses: senses ?? this.senses,
    freqRank: freqRank ?? this.freqRank,
    cefr: cefr ?? this.cefr,
    ease: ease ?? this.ease,
    intervalDays: intervalDays ?? this.intervalDays,
    repetitions: repetitions ?? this.repetitions,
    dueAtMs: dueAtMs ?? this.dueAtMs,
    mastery: mastery ?? this.mastery,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    collectedAtMs: collectedAtMs ?? this.collectedAtMs,
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
    'rootsAffixesCn': rootsAffixesCn,
    'etymologyCn': etymologyCn,
    'aiExampleEn': aiExampleEn,
    'aiExampleCn': aiExampleCn,
    'enrichmentStatus': enrichmentStatus.name,
    'scheduleStatus': scheduleStatus.name,
    'tags': tags,
    'groupIds': groupIds,
    'note': note,
    'senses': senses.map((VocabSense s) => s.toJson()).toList(),
    'freqRank': freqRank,
    'cefr': cefr,
    'occurrences': occurrences
        .map((WordOccurrence item) => item.toJson())
        .toList(),
    'ease': ease,
    'intervalDays': intervalDays,
    'repetitions': repetitions,
    'dueAtMs': dueAtMs,
    'mastery': mastery.name,
    if (updatedAtMs != null) 'updatedAtMs': updatedAtMs,
    if (collectedAtMs != null) 'collectedAtMs': collectedAtMs,
  };
}

class WordBookNotifier extends Notifier<List<WordEntry>> {
  final Set<String> _pendingOfflineDefinitions = <String>{};
  String _studyAccount = '';

  @override
  List<WordEntry> build() {
    _studyAccount = ref.watch(studyAccountProvider);
    if (!Hive.isBoxOpen('prefs')) {
      _lastPersistedPayload = <String, String>{};
      return const <WordEntry>[];
    }
    final String? stored = readStudyStorage(_wordBookStorageKey, _studyAccount);
    if (stored == null || stored.isEmpty) {
      _lastPersistedPayload = <String, String>{};
      return const <WordEntry>[];
    }
    try {
      final List<WordEntry> loaded = (jsonDecode(stored) as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(WordEntry.fromJson)
          .toList(growable: false);
      _lastPersistedPayload = <String, String>{
        for (final WordEntry item in loaded) item.word: _entryPayload(item),
      };
      return loaded;
    } catch (_) {
      _lastPersistedPayload = <String, String>{};
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
    final String account = _studyAccount;
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
    if (_studyAccount != account) return;
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
    final WordEntry current = next[index];
    final bool becomingFavorite = !current.favorite;
    final int now = DateTime.now().millisecondsSinceEpoch;
    next[index] = current.copyWith(
      favorite: becomingFavorite,
      collectedAtMs: becomingFavorite ? now : null,
      updatedAtMs: now,
      scheduleStatus: becomingFavorite
          ? VocabScheduleStatus.active
          : VocabScheduleStatus.archived,
    );
    state = next;
    unawaited(_persist());
    final WordEntry updated = next[index];
    // Always push — unfavorite must delete/clear the cloud vocab row, otherwise
    // the next pull resurrected favorite=true from an older snapshot.
    unawaited(ref.read(vocabSyncServiceProvider).pushEntry(updated));
    return updated.favorite;
  }

  /// Move a pending/archived favorite onto the FSRS schedule.
  bool enrollForReview(String rawWord) {
    final String word = normalizeLexeme(rawWord);
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (index < 0) return false;
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(
      favorite: true,
      scheduleStatus: VocabScheduleStatus.active,
    );
    state = next;
    unawaited(_persist());
    unawaited(ref.read(vocabSyncServiceProvider).pushEntry(next[index]));
    return true;
  }

  /// Keep the word in the book but drop it from the daily queue.
  ///
  /// Syllabus / recommended 「斩掉」often hits lemmas that were never favorited.
  /// Upsert an archived+known row so coveredLemmas excludes them from 新学.
  bool archiveWord(String rawWord) {
    final String word = normalizeLexeme(rawWord);
    if (word.isEmpty) return false;
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (index < 0) {
      state = <WordEntry>[
        ...state,
        WordEntry(
          word: word,
          favorite: true,
          occurrences: const <WordOccurrence>[],
          scheduleStatus: VocabScheduleStatus.archived,
          mastery: WordMastery.known,
          updatedAtMs: now,
          collectedAtMs: now,
        ),
      ];
      unawaited(_persist());
      return true;
    }
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(
      scheduleStatus: VocabScheduleStatus.archived,
      // Mark known so 词书/推荐不会把同一 lemma 再当「新学」塞回今日路径.
      mastery: next[index].mastery.index >= WordMastery.known.index
          ? next[index].mastery
          : WordMastery.known,
      updatedAtMs: now,
    );
    state = next;
    unawaited(_persist());
    return true;
  }

  bool setWordNote(String rawWord, String note) {
    final String word = normalizeLexeme(rawWord);
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (index < 0) return false;
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(note: note.trim());
    state = next;
    unawaited(_persist());
    return true;
  }

  bool addWordTag(String rawWord, String tag) {
    final String word = normalizeLexeme(rawWord);
    final String clean = tag.trim();
    if (clean.isEmpty) return false;
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (index < 0) return false;
    final WordEntry entry = state[index];
    if (entry.tags.contains(clean)) return true;
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = entry.copyWith(tags: <String>[...entry.tags, clean]);
    state = next;
    unawaited(_persist());
    return true;
  }

  bool setScheduleStatus(String rawWord, VocabScheduleStatus status) {
    final String word = normalizeLexeme(rawWord);
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (index < 0) return false;
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(
      favorite: true,
      scheduleStatus: status,
    );
    state = next;
    unawaited(_persist());
    return true;
  }

  /// True when this English line is already a favorited sentence card.
  bool containsFavoriteSentence({
    required String english,
    String? lineKey,
    String? episodeId,
  }) {
    final String en = normalizeLexeme(english);
    if (en.isEmpty) {
      return false;
    }
    final String key = (lineKey ?? '').trim();
    final String ep = (episodeId ?? '').trim();
    return state.any((WordEntry entry) {
      if (!entry.favorite || entry.kind != VocabCardKind.pattern) {
        return false;
      }
      if (entry.word != en) {
        return false;
      }
      if (key.isEmpty && ep.isEmpty) {
        return true;
      }
      return entry.occurrences.any((WordOccurrence o) {
        final bool keyOk = key.isEmpty || o.lineKeys.contains(key);
        final bool epOk = ep.isEmpty || o.episodeId == ep;
        return keyOk && epOk;
      });
    });
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
    final int collectedAt = DateTime.now().millisecondsSinceEpoch;
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
    final String sourceTag = course.trim().isEmpty
        ? ''
        : course.trim();
    final List<VocabSense> defaultSenses = validDefinition == null
        ? const <VocabSense>[]
        : <VocabSense>[
            VocabSense(
              gloss: validDefinition,
              isPrimary: true,
              register: '语境',
            ),
          ];
    if (entryIndex < 0) {
      state = <WordEntry>[
        WordEntry(
          word: word,
          favorite: true,
          collectedAtMs: collectedAt,
          kind: kind,
          definitionCn: validDefinition,
          enrichmentStatus: VocabEnrichmentStatus.pending,
          // Collecting from video/阅读 immediately joins the daily review queue.
          scheduleStatus: VocabScheduleStatus.active,
          tags: sourceTag.isEmpty
              ? const <String>[]
              : <String>[sourceTag],
          senses: defaultSenses,
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
      final List<String> tags = <String>[...entry.tags];
      if (sourceTag.isNotEmpty && !tags.contains(sourceTag)) {
        tags.add(sourceTag);
      }
      final List<VocabSense> senses = entry.senses.isNotEmpty
          ? entry.senses
          : defaultSenses;
      final List<WordEntry> next = <WordEntry>[...state];
      next[entryIndex] = entry.copyWith(
        favorite: true,
        collectedAtMs: entry.favorite ? entry.collectedAtMs : collectedAt,
        // Keep existing schedule status; first-time favorite enrolls immediately.
        scheduleStatus: entry.favorite
            ? entry.scheduleStatus
            : VocabScheduleStatus.active,
        kind: entry.kind == VocabCardKind.word ? kind : entry.kind,
        occurrences: occurrences,
        tags: tags,
        senses: senses,
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
      if (idleJobsEnabled()) {
        unawaited(
          IdleJobQueue.shared.enqueue(
            kind: IdleJobKind.vocabEnrich,
            key: word,
          ),
        );
        unawaited(scheduleIdleJobs());
      }
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
    String? rootsAffixesCn,
    String? etymologyCn,
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
      rootsAffixesCn: _prefer(rootsAffixesCn, entry.rootsAffixesCn),
      etymologyCn: _prefer(etymologyCn, entry.etymologyCn),
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
        studyStorageKey(_wordBookStorageKey, _studyAccount),
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
        rootsAffixesCn: entry.rootsAffixesCn,
        etymologyCn: entry.etymologyCn,
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
    final String account = _studyAccount;
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
      if (_studyAccount != account) return;
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
    final String account = _studyAccount;
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
      if (_studyAccount != account) return;
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

  List<WordEntry> dueQueue({
    int newWordLimit = 20,
    int reviewWordLimit = 50,
  }) {
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
        .take(newWordLimit.clamp(0, 200))
        .toList(growable: false);
    final List<WordEntry> review = due
        .where((WordEntry e) => e.mastery != WordMastery.fresh)
        .take(reviewWordLimit.clamp(0, 500))
        .toList(growable: false);
    return <WordEntry>[...review, ...fresh];
  }

  /// Counts used by the words home / plan summary.
  ({int dueReviews, int dueNew}) dueCounts() {
    int dueReviews = 0;
    int dueNew = 0;
    for (final WordEntry e in state) {
      if (!e.isDue) {
        continue;
      }
      if (e.mastery == WordMastery.fresh) {
        dueNew += 1;
      } else {
        dueReviews += 1;
      }
    }
    return (dueReviews: dueReviews, dueNew: dueNew);
  }

  Future<WordEntry?> reviewWithGrade(String word, Sm2Grade grade) async {
    const Sm2Scheduler scheduler = Sm2Scheduler();
    WordEntry? updated;
    final VocabularyPlacement placement = ref.read(vocabularyPlacementProvider.notifier);
    final String account = placement.accountKey;
    bool newlyKnown = false;
    state = state
        .map((WordEntry entry) {
          if (entry.word != word) {
            return entry;
          }
          final Sm2State next = scheduler.review(entry.sm2, grade);
          newlyKnown = entry.kind == VocabCardKind.word &&
              entry.mastery.index < WordMastery.known.index &&
              next.mastery.index >= WordMastery.known.index &&
              (grade == Sm2Grade.good || grade == Sm2Grade.easy);
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
    if (newlyKnown) {
      await placement.recordLearnedWord(word, accountAtReview: account);
    }
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
      // Respect an explicit local unfavorite — do not resurrect from /api/vocab.
      if (!existing.favorite &&
          existing.scheduleStatus == VocabScheduleStatus.archived) {
        return;
      }
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

  /// Public wrapper so FSRS grading can keep the words-page streak accurate.
  Future<void> bumpReviewStreak() => _bumpStreak();

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

  /// Replace-or-insert entries (used by demo seed). Does not push cloud sync.
  Future<void> upsertEntries(List<WordEntry> entries) async {
    if (entries.isEmpty) return;
    final Map<String, WordEntry> byWord = <String, WordEntry>{
      for (final WordEntry e in state) e.word: e,
    };
    for (final WordEntry entry in entries) {
      byWord[entry.word] = entry;
    }
    state = byWord.values.toList(growable: false)
      ..sort((WordEntry a, WordEntry b) => a.word.compareTo(b.word));
    await _persist();
  }

  Future<void> removeWords(Set<String> words) async {
    if (words.isEmpty) return;
    final Set<String> keys = words
        .map(normalizeLexeme)
        .where((String w) => w.isNotEmpty)
        .toSet();
    final int before = state.length;
    state = state
        .where((WordEntry e) => !keys.contains(e.word))
        .toList(growable: false);
    if (state.length != before) {
      await _persist();
    }
  }

  Map<String, String> _lastPersistedPayload = <String, String>{};

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, String> prevPayload = _lastPersistedPayload;
    final List<WordEntry> next = <WordEntry>[
      for (final WordEntry item in state)
        if (prevPayload[item.word] != _entryPayload(item))
          item.copyWith(updatedAtMs: now)
        else
          item,
    ];
    state = List<WordEntry>.unmodifiable(next);
    _lastPersistedPayload = <String, String>{
      for (final WordEntry item in state) item.word: _entryPayload(item),
    };
    await Hive.box<String>('prefs').put(
      studyStorageKey(_wordBookStorageKey, _studyAccount),
      jsonEncode(state.map((WordEntry item) => item.toJson()).toList()),
    );
    scheduleDeviceCloudSync(key: 'wordbook');
  }

  static String _entryPayload(WordEntry item) {
    final Map<String, Object?> json = Map<String, Object?>.from(item.toJson());
    json.remove('updatedAtMs');
    return jsonEncode(json);
  }

  /// Replace local word book after cloud merge (does not bump [updatedAtMs]).
  Future<void> replaceFromCloud(List<WordEntry> entries) async {
    state = List<WordEntry>.unmodifiable(entries);
    _lastPersistedPayload = <String, String>{
      for (final WordEntry item in state) item.word: _entryPayload(item),
    };
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      studyStorageKey(_wordBookStorageKey, _studyAccount),
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
