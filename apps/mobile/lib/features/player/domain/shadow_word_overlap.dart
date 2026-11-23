/// Word-bag overlap for shadowing feedback (matches tools/voice `_ae_overlap`).
class ShadowWordOverlap {
  const ShadowWordOverlap({
    required this.score,
    required this.precision,
    required this.recall,
    required this.missingWords,
    required this.extraWords,
    required this.referenceWords,
    required this.hypothesisWords,
  });

  final double score;
  final double precision;
  final double recall;
  final List<String> missingWords;
  final List<String> extraWords;
  final int referenceWords;
  final int hypothesisWords;

  static List<String> tokenize(String text) {
    final RegExp pattern = RegExp(r"[a-z0-9]+(?:'[a-z0-9]+)?");
    return pattern
        .allMatches(text.toLowerCase())
        .map((Match m) => m.group(0)!)
        .toList(growable: false);
  }

  /// Maps reference word positions to substitutions (3) and omissions (2).
  static Map<int, int> referenceErrors(String reference, String hypothesis) {
    final ref = tokenize(reference.replaceAll('’', "'"));
    final hyp = tokenize(hypothesis.replaceAll('’', "'"));
    final costs = List.generate(
      ref.length + 1,
      (_) => List.filled(hyp.length + 1, 0),
    );
    for (var i = 0; i <= ref.length; i++) {
      for (var j = 0; j <= hyp.length; j++) {
        costs[i][j] = i == 0
            ? j
            : j == 0
            ? i
            : _min(
                costs[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1),
                1 + _min(costs[i - 1][j], costs[i][j - 1]),
              );
      }
    }
    final errors = <int, int>{};
    var i = ref.length;
    var j = hyp.length;
    while (i > 0) {
      if (j > 0 && ref[i - 1] == hyp[j - 1]) {
        i--;
        j--;
      } else if (j > 0 && costs[i][j] == costs[i - 1][j - 1] + 1) {
        errors[--i] = 3;
        j--;
      } else if (costs[i][j] == costs[i - 1][j] + 1) {
        errors[--i] = 2;
      } else {
        j--;
      }
    }
    return errors;
  }

  static ShadowWordOverlap compare(String reference, String hypothesis) {
    final List<String> ref = tokenize(reference);
    final List<String> hyp = tokenize(hypothesis);
    if (ref.isEmpty && hyp.isEmpty) {
      return const ShadowWordOverlap(
        score: 1,
        precision: 1,
        recall: 1,
        missingWords: <String>[],
        extraWords: <String>[],
        referenceWords: 0,
        hypothesisWords: 0,
      );
    }
    final Map<String, int> refCounts = _counts(ref);
    final Map<String, int> hypCounts = _counts(hyp);
    int overlap = 0;
    for (final MapEntry<String, int> entry in refCounts.entries) {
      final int shared = _min(entry.value, hypCounts[entry.key] ?? 0);
      overlap += shared;
    }
    final double precision = hyp.isEmpty ? 0 : overlap / hyp.length;
    final double recall = ref.isEmpty ? 0 : overlap / ref.length;
    final double f1 = (precision + recall) == 0
        ? 0
        : 2 * precision * recall / (precision + recall);
    return ShadowWordOverlap(
      score: _round4(f1),
      precision: _round4(precision),
      recall: _round4(recall),
      missingWords: _diffSorted(refCounts, hypCounts),
      extraWords: _diffSorted(hypCounts, refCounts),
      referenceWords: ref.length,
      hypothesisWords: hyp.length,
    );
  }

  static Map<String, int> _counts(List<String> words) {
    final Map<String, int> out = <String, int>{};
    for (final String word in words) {
      out[word] = (out[word] ?? 0) + 1;
    }
    return out;
  }

  static List<String> _diffSorted(
    Map<String, int> left,
    Map<String, int> right,
  ) {
    final List<String> out = <String>[];
    for (final MapEntry<String, int> entry in left.entries) {
      final int remaining = entry.value - (right[entry.key] ?? 0);
      for (int i = 0; i < remaining; i += 1) {
        out.add(entry.key);
      }
    }
    out.sort();
    return out;
  }

  static int _min(int a, int b) => a < b ? a : b;

  static double _round4(double value) =>
      (value * 10000).roundToDouble() / 10000;
}
