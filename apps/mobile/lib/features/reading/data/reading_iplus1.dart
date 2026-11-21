import '../domain/reading_doc.dart';
import 'reading_gloss.dart';
import 'reading_vocab_lists.dart';

/// Ideal unknown-token share for comprehensible input (≈95–98% coverage).
const double kReadingIPlus1MinUnknown = 0.02;
const double kReadingIPlus1MaxUnknown = 0.08;

enum ReadingIPlus1Band {
  tooEasy,
  ideal,
  challenging,
  tooHard,
}

extension ReadingIPlus1BandX on ReadingIPlus1Band {
  String get labelCn => switch (this) {
        ReadingIPlus1Band.tooEasy => '偏易',
        ReadingIPlus1Band.ideal => '刚好 i+1',
        ReadingIPlus1Band.challenging => '偏难',
        ReadingIPlus1Band.tooHard => '太难',
      };
}

class ReadingIPlus1Match {
  const ReadingIPlus1Match({
    required this.doc,
    required this.unknownRate,
    required this.fitness,
    required this.band,
  });

  final ReadingDoc doc;
  final double unknownRate;
  final double fitness;
  final ReadingIPlus1Band band;

  String get rateLabel => '${(unknownRate * 100).toStringAsFixed(1)}% 生词';
}

ReadingIPlus1Band bandForUnknownRate(double rate) {
  if (rate < kReadingIPlus1MinUnknown) return ReadingIPlus1Band.tooEasy;
  if (rate <= kReadingIPlus1MaxUnknown) return ReadingIPlus1Band.ideal;
  if (rate < 0.20) return ReadingIPlus1Band.challenging;
  return ReadingIPlus1Band.tooHard;
}

/// 1.0 inside the ideal band; decays toward 0 outside.
double iPlus1Fitness(double unknownRate) {
  final double r = unknownRate.clamp(0.0, 1.0);
  if (r >= kReadingIPlus1MinUnknown && r <= kReadingIPlus1MaxUnknown) {
    return 1.0;
  }
  if (r < kReadingIPlus1MinUnknown) {
    if (kReadingIPlus1MinUnknown <= 0) return 1.0;
    return (r / kReadingIPlus1MinUnknown).clamp(0.0, 1.0);
  }
  // After 8%, fully decay by ~25% unknown.
  const double hardSpan = 0.17;
  final double over = r - kReadingIPlus1MaxUnknown;
  return (1.0 - over / hardSpan).clamp(0.0, 1.0);
}

double unknownWordRateWithLists({
  required Iterable<String> words,
  required ReadingFrequencyLexicon lexicon,
  required int threshold,
  Set<String> known = const <String>{},
  Set<String> focus = const <String>{},
}) {
  int total = 0;
  int hard = 0;
  for (final String raw in words) {
    final String word = raw.trim().toLowerCase().replaceAll('’', "'");
    if (word.length < 2) continue;
    total += 1;
    if (isReadingHardWord(
      word: word,
      lexicon: lexicon,
      threshold: threshold,
      known: known,
      focus: focus,
    )) {
      hard += 1;
    }
  }
  if (total == 0) return 0;
  return hard / total;
}

ReadingIPlus1Match scoreReadingDocForIPlus1({
  required ReadingDoc doc,
  required ReadingFrequencyLexicon lexicon,
  required int threshold,
  Set<String> known = const <String>{},
  Set<String> focus = const <String>{},
}) {
  final List<String> tokens = extractReadingWordTokens(doc.plainText);
  final double rate = unknownWordRateWithLists(
    words: tokens,
    lexicon: lexicon,
    threshold: threshold,
    known: known,
    focus: focus,
  );
  return ReadingIPlus1Match(
    doc: doc,
    unknownRate: rate,
    fitness: iPlus1Fitness(rate),
    band: bandForUnknownRate(rate),
  );
}

/// Rank docs by i+1 fitness (ideal first), then prefer unfinished / shorter.
List<ReadingIPlus1Match> rankDocsForIPlus1({
  required Iterable<ReadingDoc> docs,
  required ReadingFrequencyLexicon lexicon,
  required int threshold,
  Set<String> known = const <String>{},
  Set<String> focus = const <String>{},
  Map<String, double> progressById = const <String, double>{},
  int limit = 5,
}) {
  final List<ReadingIPlus1Match> scored = <ReadingIPlus1Match>[
    for (final ReadingDoc doc in docs)
      if (doc.plainText.trim().isNotEmpty)
        scoreReadingDocForIPlus1(
          doc: doc,
          lexicon: lexicon,
          threshold: threshold,
          known: known,
          focus: focus,
        ),
  ];
  scored.sort((ReadingIPlus1Match a, ReadingIPlus1Match b) {
    final int byFit = b.fitness.compareTo(a.fitness);
    if (byFit != 0) return byFit;
    final double pa = progressById[a.doc.id] ?? 0;
    final double pb = progressById[b.doc.id] ?? 0;
    // Prefer not-yet-finished.
    final bool aDone = pa >= 0.95;
    final bool bDone = pb >= 0.95;
    if (aDone != bDone) return aDone ? 1 : -1;
    final int byBand = a.band.index.compareTo(b.band.index);
    if (byBand != 0) return byBand;
    return a.doc.wordCount.compareTo(b.doc.wordCount);
  });
  if (scored.length <= limit) return scored;
  return scored.sublist(0, limit);
}
