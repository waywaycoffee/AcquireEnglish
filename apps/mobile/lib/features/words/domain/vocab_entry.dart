import 'word_review_settings.dart';

/// FSRS enrollment lifecycle for a vocabulary entry.
enum VocabScheduleStatus {
  /// In the word book, not yet on the FSRS schedule.
  pending,

  /// Actively scheduled (new or due reviews).
  active,

  /// Kept in the book but removed from the daily queue.
  archived,
}

extension VocabScheduleStatusX on VocabScheduleStatus {
  String get label => switch (this) {
    VocabScheduleStatus.pending => '待学习',
    VocabScheduleStatus.active => '复习中',
    VocabScheduleStatus.archived => '已归档',
  };

  static VocabScheduleStatus parse(String? raw, {required bool favorite}) {
    switch (raw) {
      case 'pending':
        return VocabScheduleStatus.pending;
      case 'archived':
        return VocabScheduleStatus.archived;
      case 'active':
        return VocabScheduleStatus.active;
      default:
        // Legacy favorites were already in the FSRS queue.
        return favorite
            ? VocabScheduleStatus.active
            : VocabScheduleStatus.pending;
    }
  }
}

class VocabSense {
  const VocabSense({
    required this.gloss,
    this.pos = '',
    this.register = '',
    this.isPrimary = false,
  });

  factory VocabSense.fromJson(Map<String, Object?> json) => VocabSense(
    gloss: json['gloss'] as String? ?? '',
    pos: json['pos'] as String? ?? '',
    register: json['register'] as String? ?? '',
    isPrimary: json['isPrimary'] as bool? ?? false,
  );

  final String gloss;
  final String pos;
  final String register;
  final bool isPrimary;

  Map<String, Object?> toJson() => <String, Object?>{
    'gloss': gloss,
    'pos': pos,
    'register': register,
    'isPrimary': isPrimary,
  };
}

/// Stable entry id for a lemma (one orthographic form, one sense pack for now).
String vocabEntryIdForLemma(String lemma) {
  final String key = lemma.trim().toLowerCase().replaceAll('’', "'");
  return key;
}

/// Per-card-type FSRS key: `entry:{lemma}:{mode}`.
String vocabFsrsKey(String lemma, WordPracticeMode mode) {
  return 'entry:${vocabEntryIdForLemma(lemma)}:${mode.name}';
}

String legacyWordFsrsKey(String lemma) => 'word:${vocabEntryIdForLemma(lemma)}';

/// Parse lemma from review keys used in the daily queue.
///
/// Supports `entry:foo:recognize`, `word:foo`, `syllabus:{book}:foo`,
/// and `recommended:foo`. Syllabus / recommended cards must resolve here so
/// 「斩掉」can archive the lemma and stop re-queuing it as 新学.
String? lemmaFromReviewKey(String key) {
  if (key.startsWith('entry:')) {
    final List<String> parts = key.split(':');
    if (parts.length >= 3) {
      return parts.sublist(1, parts.length - 1).join(':');
    }
  }
  if (key.startsWith('word:')) {
    return key.substring('word:'.length);
  }
  if (key.startsWith('syllabus:')) {
    final List<String> parts = key.split(':');
    if (parts.length >= 3) {
      return parts.sublist(2).join(':').trim().toLowerCase();
    }
  }
  if (key.startsWith('recommended:')) {
    return key.substring('recommended:'.length).trim().toLowerCase();
  }
  return null;
}

WordPracticeMode? modeFromReviewKey(String key) {
  if (!key.startsWith('entry:')) return null;
  final int idx = key.lastIndexOf(':');
  if (idx <= 0) return null;
  return WordPracticeModeX.tryParse(key.substring(idx + 1));
}

/// Rough CEFR from SUBTLEX-style frequency rank (1 = most common).
String? cefrFromFreqRank(int? rank) {
  if (rank == null || rank <= 0) return null;
  if (rank <= 500) return 'A1';
  if (rank <= 1500) return 'A2';
  if (rank <= 3000) return 'B1';
  if (rank <= 6000) return 'B2';
  if (rank <= 10000) return 'C1';
  return 'C2';
}
