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
