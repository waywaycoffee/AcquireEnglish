/// Guided AI 外教课 steps for selected source material (not free chat).
enum TutorLessonStep {
  intro,
  demo,
  shadow,
  substitute,
  dialogue,
  summary,
}

extension TutorLessonStepX on TutorLessonStep {
  int get index1 => index + 1;

  String get title => switch (this) {
    TutorLessonStep.intro => '开场',
    TutorLessonStep.demo => '示范',
    TutorLessonStep.shadow => '跟读',
    TutorLessonStep.substitute => '替换',
    TutorLessonStep.dialogue => '场景对话',
    TutorLessonStep.summary => '小结',
  };

  String get detail => switch (this) {
    TutorLessonStep.intro => '了解今天要学会的表达',
    TutorLessonStep.demo => '外教演示来源中的真实句子',
    TutorLessonStep.shadow => '放慢语速，分句开口',
    TutorLessonStep.substitute => '换词说出自己的句子',
    TutorLessonStep.dialogue => '和外教完成 2～3 轮交流',
    TutorLessonStep.summary => '查看表现并领取复习任务',
  };

  static const List<TutorLessonStep> all = TutorLessonStep.values;
}

List<String> tutorSourceLines(String raw) {
  return raw
      .split(RegExp(r'[\n。.!?]'))
      .map((String s) => s.trim())
      .where((String s) => s.length >= 3)
      .take(4)
      .toList(growable: false);
}

/// Rough speaking score 0–100 from token overlap (guided shadow / substitute).
int tutorUtteranceScore(String target, String attempt) {
  final Set<String> want = RegExp(r"[A-Za-z']+")
      .allMatches(target.toLowerCase())
      .map((Match m) => m.group(0)!)
      .where((String w) => w.length > 1)
      .toSet();
  if (want.isEmpty) return attempt.trim().isEmpty ? 0 : 70;
  final Set<String> got = RegExp(r"[A-Za-z']+")
      .allMatches(attempt.toLowerCase())
      .map((Match m) => m.group(0)!)
      .where((String w) => w.length > 1)
      .toSet();
  if (got.isEmpty) return 0;
  final int hit = want.where(got.contains).length;
  return ((hit / want.length) * 100).round().clamp(0, 100);
}

List<String> tutorKeyExpressions(List<String> lines) {
  final List<String> out = <String>[];
  for (final String line in lines) {
    for (final Match m in RegExp(r"[A-Za-z][A-Za-z'-]{3,}").allMatches(line)) {
      final String w = m.group(0)!.toLowerCase();
      if (const <String>{
        'this',
        'that',
        'with',
        'from',
        'have',
        'been',
        'were',
        'what',
        'when',
        'your',
        'they',
        'them',
        'there',
        'about',
        'hello',
        'welcome',
        'name',
        'english',
        'first',
        'episode',
        'learning',
      }.contains(w)) {
        continue;
      }
      if (!out.contains(w)) out.add(w);
      if (out.length >= 8) return out;
    }
  }
  return out;
}
