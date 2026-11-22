import 'exam_reading_strategy.dart';

class ExamRcQuestion {
  const ExamRcQuestion({
    required this.id,
    required this.stem,
    required this.options,
    required this.answer,
    this.explain = '',
    this.type = ExamRcQuestionType.unknown,
    this.evidence = '',
  });

  factory ExamRcQuestion.fromJson(Map<String, dynamic> json) {
    final List<String> options =
        (json['options'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => '$e')
            .toList(growable: false);
    return ExamRcQuestion(
      id: '${json['id'] ?? ''}',
      stem: '${json['stem'] ?? json['prompt'] ?? ''}',
      options: options,
      answer: '${json['answer'] ?? ''}',
      explain: '${json['explain'] ?? json['explanation'] ?? ''}',
      type: ExamRcQuestionTypeX.fromStorage('${json['type'] ?? ''}'),
      evidence: '${json['evidence'] ?? json['evidence_sentence'] ?? ''}',
    );
  }

  final String id;
  final String stem;
  final List<String> options;
  final String answer;
  final String explain;
  final ExamRcQuestionType type;
  final String evidence;

  ExamRcQuestionType get resolvedType =>
      type == ExamRcQuestionType.unknown ? detectExamRcQuestionType(stem) : type;

  int get answerIndex {
    final int byText = options.indexWhere((String o) => o == answer);
    if (byText >= 0) return byText;
    final int asInt = int.tryParse(answer.trim()) ?? -1;
    if (asInt >= 0 && asInt < options.length) return asInt;
    return 0;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'stem': stem,
        'options': options,
        'answer': answer,
        'explain': explain,
        'type': type.storageValue,
        'evidence': evidence,
      };

  ExamRcQuestion copyWith({
    String? stem,
    List<String>? options,
    String? answer,
    String? explain,
    ExamRcQuestionType? type,
    String? evidence,
  }) =>
      ExamRcQuestion(
        id: id,
        stem: stem ?? this.stem,
        options: options ?? this.options,
        answer: answer ?? this.answer,
        explain: explain ?? this.explain,
        type: type ?? this.type,
        evidence: evidence ?? this.evidence,
      );
}

class ExamRcPaper {
  const ExamRcPaper({
    required this.id,
    required this.title,
    required this.passage,
    required this.questions,
    this.source = 'import',
    this.createdAtMs = 0,
  });

  factory ExamRcPaper.fromJson(Map<String, dynamic> json) => ExamRcPaper(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? '阅读理解'}',
        passage: '${json['passage'] ?? ''}',
        questions: (json['questions'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (Map e) => ExamRcQuestion.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(growable: false),
        source: '${json['source'] ?? 'import'}',
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String title;
  final String passage;
  final List<ExamRcQuestion> questions;
  final String source;
  final int createdAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'passage': passage,
        'questions': questions.map((ExamRcQuestion q) => q.toJson()).toList(),
        'source': source,
        'createdAtMs': createdAtMs,
      };

  ExamRcPaper copyWith({
    String? title,
    String? passage,
    List<ExamRcQuestion>? questions,
  }) =>
      ExamRcPaper(
        id: id,
        title: title ?? this.title,
        passage: passage ?? this.passage,
        questions: questions ?? this.questions,
        source: source,
        createdAtMs: createdAtMs,
      );
}

/// Built-in demo paper for the three-step guided flow.
ExamRcPaper get kExamRcDemoPaper => ExamRcPaper(
      id: 'demo_rc_campus_clubs',
      title: '示范卷 · Campus Clubs',
      source: 'demo',
      createdAtMs: 0,
      passage:
          'Many universities encourage students to join clubs. Clubs help students '
          'make friends, practice skills, and manage time. However, joining too many '
          'clubs can hurt academic performance. In 2019, Dr. Smith surveyed 1,200 '
          'freshmen and found that students with two carefully chosen activities '
          'usually kept higher grades. Experts therefore suggest choosing two '
          'activities that match long-term goals rather than collecting memberships.',
      questions: <ExamRcQuestion>[
        ExamRcQuestion(
          id: 'demo_q1',
          stem: 'According to the passage, what is one benefit of clubs?',
          options: <String>[
            'Making friends',
            'Higher tuition',
            'Less homework',
            'Shorter semesters',
          ],
          answer: 'Making friends',
          type: ExamRcQuestionType.detail,
          evidence:
              'Clubs help students make friends, practice skills, and manage time.',
          explain: '细节题：定位 clubs help…make friends，同义对应 Making friends。',
        ),
        ExamRcQuestion(
          id: 'demo_q2',
          stem: 'What do experts suggest students should do?',
          options: <String>[
            'Join every available club',
            'Choose two activities matching long-term goals',
            'Avoid all clubs completely',
            'Only study alone in the library',
          ],
          answer: 'Choose two activities matching long-term goals',
          type: ExamRcQuestionType.detail,
          evidence:
              'Experts therefore suggest choosing two activities that match long-term goals',
          explain: '细节题：suggest 后即答案所在；注意 however 后的警告不是建议本身。',
        ),
        ExamRcQuestion(
          id: 'demo_q3',
          stem: 'What can be inferred from Dr. Smith’s 2019 survey?',
          options: <String>[
            'Every freshman must join exactly two clubs',
            'Careful selection of activities may relate to better grades',
            'Clubs always improve academic performance',
            'Dr. Smith proves online learning is useless',
          ],
          answer: 'Careful selection of activities may relate to better grades',
          type: ExamRcQuestionType.inference,
          evidence:
              'students with two carefully chosen activities usually kept higher grades',
          explain: '推断题：用 may/relate 的保守表述；带 always/must/proves 的多为干扰。',
        ),
        ExamRcQuestion(
          id: 'demo_q4',
          stem: 'What is the main idea of the passage?',
          options: <String>[
            'Universities should ban all clubs',
            'Clubs can help, but students should choose them wisely',
            'Dr. Smith only studied tuition fees',
            'Freshmen never join clubs',
          ],
          answer: 'Clubs can help, but students should choose them wisely',
          type: ExamRcQuestionType.mainIdea,
          evidence:
              'However, joining too many clubs can hurt academic performance.',
          explain: '主旨题：好处 + however 转折后的建议，贯穿全文。',
        ),
      ],
    );
