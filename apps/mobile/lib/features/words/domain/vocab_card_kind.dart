/// Vocabulary card kinds for 单词 / 词组 / 句型.
enum VocabCardKind { word, phrase, pattern }

extension VocabCardKindLabel on VocabCardKind {
  String get labelCn {
    switch (this) {
      case VocabCardKind.word:
        return '单词';
      case VocabCardKind.phrase:
        return '词组';
      case VocabCardKind.pattern:
        return '句型';
    }
  }
}

VocabCardKind vocabCardKindForLexeme(String text) {
  final int words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .length;
  if (words <= 1) {
    return VocabCardKind.word;
  }
  if (words <= 4) {
    return VocabCardKind.phrase;
  }
  return VocabCardKind.pattern;
}

enum VocabEnrichmentStatus { none, pending, ready, failed }

VocabEnrichmentStatus vocabEnrichmentStatusFromName(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'pending':
      return VocabEnrichmentStatus.pending;
    case 'ready':
      return VocabEnrichmentStatus.ready;
    case 'failed':
      return VocabEnrichmentStatus.failed;
    default:
      return VocabEnrichmentStatus.none;
  }
}
