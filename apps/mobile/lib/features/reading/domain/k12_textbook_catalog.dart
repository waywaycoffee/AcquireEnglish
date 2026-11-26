import '../../exam/domain/exam_registry.dart';

/// K12 English textbook shelf metadata only — no copyrighted book bodies.
enum K12TextbookStage { primary, junior, senior }

class K12TextbookEntry {
  const K12TextbookEntry({
    required this.id,
    required this.gradeId,
    required this.stage,
    required this.title,
    required this.titleZh,
    required this.edition,
    required this.volume,
    required this.publisher,
    required this.level,
  });

  /// Stable id used as ReadingDoc.id when opening the ebook reader.
  final String id;
  final String gradeId;
  final K12TextbookStage stage;
  final String title;
  final String titleZh;
  final String edition;
  final String volume;
  final String publisher;
  final String level;

  String get coverSubtitle => '$edition · $volume';

  String get shelfIntro {
    final StringBuffer buf = StringBuffer()
      ..writeln(titleZh.isEmpty ? title : '$title（$titleZh）')
      ..writeln()
      ..writeln('Edition: $edition')
      ..writeln('Volume: $volume')
      ..writeln('Publisher: $publisher')
      ..writeln('Grade shelf: $gradeId')
      ..writeln()
      ..writeln(
        'This shelf entry is a catalog placeholder. Acquire English does not '
        'ship commercial textbook scans. Import a text, EPUB, or PDF you are '
        'allowed to use (school license, personal purchase, or official '
        'platform export), then open it from your reading library.',
      )
      ..writeln()
      ..writeln(
        '本页仅为年级教材目录占位，不含受版权保护的教材正文。'
        '请导入你有权使用的 TXT / EPUB / PDF 后，在阅读书架中打开学习。',
      );
    return buf.toString();
  }
}

String k12TextbookStageLabel(K12TextbookStage stage) => switch (stage) {
  K12TextbookStage.primary => '小学',
  K12TextbookStage.junior => '初中',
  K12TextbookStage.senior => '高中',
};

K12TextbookStage? k12TextbookStageForGradeId(String gradeId) {
  if (gradeId.startsWith('k12_g')) return K12TextbookStage.primary;
  if (gradeId.startsWith('k12_j') || gradeId == 'zhongkao') {
    return K12TextbookStage.junior;
  }
  if (gradeId.startsWith('k12_s') || gradeId == 'gaokao') {
    return K12TextbookStage.senior;
  }
  return null;
}

List<ExamFamily> k12TextbookGradesForStage(K12TextbookStage stage) =>
    switch (stage) {
      K12TextbookStage.primary => k12FamiliesPrimary(),
      K12TextbookStage.junior => k12FamiliesJunior()
          .where((ExamFamily f) => f.id != 'zhongkao')
          .toList(growable: false),
      K12TextbookStage.senior => k12FamiliesSenior()
          .where((ExamFamily f) => f.id != 'gaokao')
          .toList(growable: false),
    };

List<K12TextbookEntry> k12TextbooksForGrade(String gradeId) => kK12TextbookCatalog
    .where((K12TextbookEntry e) => e.gradeId == gradeId)
    .toList(growable: false);

K12TextbookEntry? k12TextbookById(String id) {
  for (final K12TextbookEntry e in kK12TextbookCatalog) {
    if (e.id == id) return e;
  }
  return null;
}

K12TextbookEntry _book({
  required String gradeId,
  required K12TextbookStage stage,
  required String editionKey,
  required String edition,
  required String publisher,
  required String volumeKey,
  required String volume,
  required String titleEn,
  required String titleZh,
  required String level,
}) {
  return K12TextbookEntry(
    id: 'k12-textbook:$editionKey:$gradeId:$volumeKey',
    gradeId: gradeId,
    stage: stage,
    title: titleEn,
    titleZh: titleZh,
    edition: edition,
    volume: volume,
    publisher: publisher,
    level: level,
  );
}

List<K12TextbookEntry> _volumes({
  required String gradeId,
  required K12TextbookStage stage,
  required String editionKey,
  required String edition,
  required String publisher,
  required String gradeLabel,
  required String level,
  bool fullYear = false,
}) {
  if (fullYear) {
    return <K12TextbookEntry>[
      _book(
        gradeId: gradeId,
        stage: stage,
        editionKey: editionKey,
        edition: edition,
        publisher: publisher,
        volumeKey: 'full',
        volume: '全一册',
        titleEn: 'English · $gradeLabel',
        titleZh: '英语 $gradeLabel',
        level: level,
      ),
    ];
  }
  return <K12TextbookEntry>[
    _book(
      gradeId: gradeId,
      stage: stage,
      editionKey: editionKey,
      edition: edition,
      publisher: publisher,
      volumeKey: 'a',
      volume: '上册',
      titleEn: 'English · $gradeLabel Book 1',
      titleZh: '英语 $gradeLabel 上册',
      level: level,
    ),
    _book(
      gradeId: gradeId,
      stage: stage,
      editionKey: editionKey,
      edition: edition,
      publisher: publisher,
      volumeKey: 'b',
      volume: '下册',
      titleEn: 'English · $gradeLabel Book 2',
      titleZh: '英语 $gradeLabel 下册',
      level: level,
    ),
  ];
}

/// Popular edition catalog for the grade bookshelf (metadata only).
final List<K12TextbookEntry> kK12TextbookCatalog = <K12TextbookEntry>[
  // —— 小学 ——
  ..._primaryEdition(
    editionKey: 'pep-y1',
    edition: '人教版（一年级起点）',
    publisher: '人民教育出版社',
    fromGrade: 1,
  ),
  ..._primaryEdition(
    editionKey: 'pep-y3',
    edition: '人教版 PEP（三年级起点）',
    publisher: '人民教育出版社',
    fromGrade: 3,
  ),
  ..._primaryEdition(
    editionKey: 'fltrp-y3',
    edition: '外研社版（三年级起点）',
    publisher: '外语教学与研究出版社',
    fromGrade: 3,
  ),
  ..._primaryEdition(
    editionKey: 'yilin-y3',
    edition: '译林版（三年级起点）',
    publisher: '译林出版社',
    fromGrade: 3,
  ),
  ..._primaryEdition(
    editionKey: 'beijing',
    edition: '北京版',
    publisher: '北京出版社',
    fromGrade: 1,
  ),
  // —— 初中 ——
  ..._juniorEdition(
    editionKey: 'pep-go',
    edition: '人教版 Go for it!',
    publisher: '人民教育出版社',
  ),
  ..._juniorEdition(
    editionKey: 'fltrp-junior',
    edition: '外研社版初中英语',
    publisher: '外语教学与研究出版社',
  ),
  ..._juniorEdition(
    editionKey: 'yilin-junior',
    edition: '译林版初中英语',
    publisher: '译林出版社',
  ),
  // —— 高中 ——
  ..._seniorEdition(
    editionKey: 'pep-senior',
    edition: '人教版高中英语',
    publisher: '人民教育出版社',
  ),
  ..._seniorEdition(
    editionKey: 'fltrp-senior',
    edition: '外研社版高中英语',
    publisher: '外语教学与研究出版社',
  ),
  ..._seniorEdition(
    editionKey: 'yilin-senior',
    edition: '译林版高中英语',
    publisher: '译林出版社',
  ),
];

List<K12TextbookEntry> _primaryEdition({
  required String editionKey,
  required String edition,
  required String publisher,
  required int fromGrade,
}) {
  const List<(String id, String label, String level)> grades =
      <(String, String, String)>[
    ('k12_g1', '一年级', 'A1'),
    ('k12_g2', '二年级', 'A1'),
    ('k12_g3', '三年级', 'A1'),
    ('k12_g4', '四年级', 'A1'),
    ('k12_g5', '五年级', 'A2'),
    ('k12_g6', '六年级', 'A2'),
  ];
  final List<K12TextbookEntry> out = <K12TextbookEntry>[];
  for (int i = 0; i < grades.length; i++) {
    final int gradeNum = i + 1;
    if (gradeNum < fromGrade) continue;
    final (String id, String label, String level) = grades[i];
    out.addAll(
      _volumes(
        gradeId: id,
        stage: K12TextbookStage.primary,
        editionKey: editionKey,
        edition: edition,
        publisher: publisher,
        gradeLabel: label,
        level: level,
      ),
    );
  }
  return out;
}

List<K12TextbookEntry> _juniorEdition({
  required String editionKey,
  required String edition,
  required String publisher,
}) {
  const List<(String id, String label, String level)> grades =
      <(String, String, String)>[
    ('k12_j1', '七年级', 'A2'),
    ('k12_j2', '八年级', 'A2'),
    ('k12_j3', '九年级', 'B1'),
  ];
  final List<K12TextbookEntry> out = <K12TextbookEntry>[];
  for (final (String id, String label, String level) in grades) {
    out.addAll(
      _volumes(
        gradeId: id,
        stage: K12TextbookStage.junior,
        editionKey: editionKey,
        edition: edition,
        publisher: publisher,
        gradeLabel: label,
        level: level,
      ),
    );
  }
  return out;
}

List<K12TextbookEntry> _seniorEdition({
  required String editionKey,
  required String edition,
  required String publisher,
}) {
  const List<(String id, String label, String level)> grades =
      <(String, String, String)>[
    ('k12_s1', '高一', 'B1'),
    ('k12_s2', '高二', 'B1'),
    ('k12_s3', '高三', 'B2'),
  ];
  final List<K12TextbookEntry> out = <K12TextbookEntry>[];
  for (final (String id, String label, String level) in grades) {
    out.addAll(
      _volumes(
        gradeId: id,
        stage: K12TextbookStage.senior,
        editionKey: editionKey,
        edition: edition,
        publisher: publisher,
        gradeLabel: label,
        level: level,
      ),
    );
  }
  return out;
}
