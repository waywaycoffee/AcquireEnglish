/// Word-level dictation grading (miss / extra / wrong) for video study.
class DictationTokenMark {
  const DictationTokenMark({
    required this.expected,
    required this.actual,
    required this.kind,
  });

  final String expected;
  final String actual;
  final DictationTokenKind kind;
}

enum DictationTokenKind { correct, missing, extra, wrong }

class DictationDiffResult {
  const DictationDiffResult({
    required this.exact,
    required this.marks,
    required this.missingWords,
    required this.extraWords,
    required this.wrongWords,
  });

  final bool exact;
  final List<DictationTokenMark> marks;

  /// Expected tokens the learner omitted.
  final List<String> missingWords;

  /// Tokens the learner typed that were not in the expected line.
  final List<String> extraWords;

  /// Expected tokens that were substituted (also listed in [wrongWords] as
  /// the expected form, suitable for vocabulary enqueue).
  final List<String> wrongWords;

  /// Lexemes worth sending into the word book / FSRS.
  List<String> get reviewWords {
    final Set<String> out = <String>{};
    for (final String w in missingWords) {
      if (_isLexeme(w)) out.add(w);
    }
    for (final String w in wrongWords) {
      if (_isLexeme(w)) out.add(w);
    }
    return out.toList(growable: false);
  }

  static bool _isLexeme(String raw) {
    final String w = raw.trim().toLowerCase();
    if (w.length < 2) return false;
    if (!RegExp(r"^[a-z]+(?:'[a-z]+)?$").hasMatch(w)) return false;
    const Set<String> stop = <String>{
      'a',
      'an',
      'the',
      'to',
      'of',
      'in',
      'on',
      'at',
      'is',
      'are',
      'am',
      'be',
      'and',
      'or',
      'i',
      'you',
      'he',
      'she',
      'it',
      'we',
      'they',
    };
    return !stop.contains(w);
  }
}

List<String> tokenizeDictation(String raw) {
  final String normalized = raw
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) return const <String>[];
  return normalized.split(' ');
}

/// Align [actual] against [expected] with a simple LCS-based pass.
DictationDiffResult diffDictation({
  required String expected,
  required String actual,
}) {
  final List<String> exp = tokenizeDictation(expected);
  final List<String> act = tokenizeDictation(actual);
  if (exp.isEmpty && act.isEmpty) {
    return const DictationDiffResult(
      exact: true,
      marks: <DictationTokenMark>[],
      missingWords: <String>[],
      extraWords: <String>[],
      wrongWords: <String>[],
    );
  }
  final List<List<int>> dp = List<List<int>>.generate(
    exp.length + 1,
    (_) => List<int>.filled(act.length + 1, 0),
  );
  for (int i = 1; i <= exp.length; i++) {
    for (int j = 1; j <= act.length; j++) {
      if (exp[i - 1] == act[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }

  final List<DictationTokenMark> marks = <DictationTokenMark>[];
  final List<String> missing = <String>[];
  final List<String> extra = <String>[];
  final List<String> wrong = <String>[];
  int i = exp.length;
  int j = act.length;
  final List<DictationTokenMark> reversed = <DictationTokenMark>[];
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && exp[i - 1] == act[j - 1]) {
      reversed.add(
        DictationTokenMark(
          expected: exp[i - 1],
          actual: act[j - 1],
          kind: DictationTokenKind.correct,
        ),
      );
      i--;
      j--;
    } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
      reversed.add(
        DictationTokenMark(
          expected: '',
          actual: act[j - 1],
          kind: DictationTokenKind.extra,
        ),
      );
      extra.add(act[j - 1]);
      j--;
    } else if (i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j])) {
      // Peek: treat adjacent extra+missing as a substitution when possible.
      if (j > 0 &&
          reversed.isNotEmpty &&
          reversed.last.kind == DictationTokenKind.extra) {
        final DictationTokenMark prev = reversed.removeLast();
        extra.removeLast();
        reversed.add(
          DictationTokenMark(
            expected: exp[i - 1],
            actual: prev.actual,
            kind: DictationTokenKind.wrong,
          ),
        );
        wrong.add(exp[i - 1]);
      } else {
        reversed.add(
          DictationTokenMark(
            expected: exp[i - 1],
            actual: '',
            kind: DictationTokenKind.missing,
          ),
        );
        missing.add(exp[i - 1]);
      }
      i--;
    }
  }
  marks.addAll(reversed.reversed);

  final bool exact =
      missing.isEmpty && extra.isEmpty && wrong.isEmpty && exp.isNotEmpty;
  return DictationDiffResult(
    exact: exact || (exp.isEmpty && act.isEmpty),
    marks: marks,
    missingWords: missing,
    extraWords: extra,
    wrongWords: wrong,
  );
}
