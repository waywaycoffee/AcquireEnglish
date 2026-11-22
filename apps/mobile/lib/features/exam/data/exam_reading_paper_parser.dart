import '../domain/exam_reading_paper.dart';
import '../domain/exam_reading_strategy.dart';

/// Heuristic parse of pasted / OCR text into one passage + ABCD questions.
ExamRcPaper? parseExamReadingPaperText(
  String raw, {
  String title = '导入试卷',
}) {
  final String text = raw.replaceAll('\r\n', '\n').trim();
  if (text.length < 40) return null;

  final RegExp qStart = RegExp(
    r'(?:^|\n)\s*(?:Questions?\s+\d+\s*[-–—]\s*\d+[^\n]*\n)?\s*(\d{1,2})[\.\)、]\s+',
    multiLine: true,
  );
  final Match? firstQ = qStart.firstMatch(text);
  String passage;
  String rest;
  if (firstQ != null && firstQ.start > 20) {
    passage = text.substring(0, firstQ.start).trim();
    rest = text.substring(firstQ.start).trim();
  } else {
    final List<String> paras = text
        .split(RegExp(r'\n\s*\n'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    if (paras.length >= 2) {
      passage = paras.first;
      rest = paras.skip(1).join('\n\n');
    } else {
      passage = text;
      rest = '';
    }
  }

  passage = passage
      .replaceFirst(
        RegExp(r'^(Passage|Text|阅读理解|Directions)[^\n]*\n+', caseSensitive: false),
        '',
      )
      .trim();
  if (passage.length < 30) return null;

  final List<ExamRcQuestion> questions = <ExamRcQuestion>[];
  final List<RegExpMatch> starts = qStart.allMatches(rest).toList();
  if (starts.isEmpty) {
    // Fall back: treat whole rest as no questions → fail import of Qs.
    return ExamRcPaper(
      id: 'import_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      passage: passage,
      questions: const <ExamRcQuestion>[],
      source: 'import',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  for (int i = 0; i < starts.length; i++) {
    final int from = starts[i].end;
    final int to = i + 1 < starts.length ? starts[i + 1].start : rest.length;
    final String block = rest.substring(from, to).trim();
    final ExamRcQuestion? q = _parseQuestionBlock(
      id: 'q${starts[i].group(1) ?? '${i + 1}'}',
      block: block,
    );
    if (q != null && q.options.length == 4) {
      questions.add(q);
    }
  }

  return ExamRcPaper(
    id: 'import_${DateTime.now().millisecondsSinceEpoch}',
    title: title,
    passage: passage,
    questions: questions,
    source: 'import',
    createdAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}

ExamRcQuestion? _parseQuestionBlock({
  required String id,
  required String block,
}) {
  final RegExp optRe = RegExp(
    r'(?:^|\n)\s*([A-Da-d])[\.\)、]\s*',
    multiLine: true,
  );
  final List<RegExpMatch> opts = optRe.allMatches(block).toList();
  if (opts.length < 4) return null;
  final String stem = block.substring(0, opts.first.start).trim();
  if (stem.length < 5) return null;
  final List<String> options = <String>[];
  for (int i = 0; i < 4; i++) {
    final int from = opts[i].end;
    final int to = i + 1 < opts.length ? opts[i + 1].start : block.length;
    options.add(block.substring(from, to).trim().replaceAll(RegExp(r'\s+'), ' '));
  }
  String answer = options.first;
  final Match? ans = RegExp(
    r'(?:答案|Answer)\s*[:：]?\s*([A-Da-d])',
    caseSensitive: false,
  ).firstMatch(block);
  if (ans != null) {
    final int idx = ans.group(1)!.toUpperCase().codeUnitAt(0) - 65;
    if (idx >= 0 && idx < 4) answer = options[idx];
  }
  return ExamRcQuestion(
    id: id,
    stem: stem.replaceAll(RegExp(r'\s+'), ' '),
    options: options,
    answer: answer,
    type: detectExamRcQuestionType(stem),
  );
}
