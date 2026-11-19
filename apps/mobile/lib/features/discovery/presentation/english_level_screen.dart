import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../player/presentation/widgets/pronunciation_assessment_dialog.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../../words/presentation/vocabulary_placement_provider.dart';

const List<String> englishLevels = <String>[
  '零基础',
  '学龄前',
  'A1',
  'A2',
  'B1',
  'B2',
  'C1',
  'C2',
];

class EnglishLevelScreen extends ConsumerStatefulWidget {
  const EnglishLevelScreen({super.key});

  @override
  ConsumerState<EnglishLevelScreen> createState() => _EnglishLevelScreenState();
}

class _EnglishLevelScreenState extends ConsumerState<EnglishLevelScreen> {
  late final String _key;
  String? _stage;
  String? _work;
  int? _reading;
  double? _speaking;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final String email = ref
        .read(authSessionProvider)
        .email
        .trim()
        .toLowerCase();
    _key = 'englishLevelAssessment:v1:$email';
    if (!Hive.isBoxOpen('prefs')) return;
    try {
      final Map<String, dynamic> data =
          jsonDecode(Hive.box<String>('prefs').get(_key) ?? '{}')
              as Map<String, dynamic>;
      _stage = data['stage'] as String?;
      _work = data['work'] as String?;
      _reading = data['reading'] as int?;
      _speaking = (data['speaking'] as num?)?.toDouble();
    } catch (_) {}
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      _key,
      jsonEncode(<String, Object?>{
        'stage': _stage,
        'work': _work,
        'reading': _reading,
        'speaking': _speaking,
      }),
    );
  }

  String? _estimate(int? vocabulary) {
    if (vocabulary == null || _reading == null || _speaking == null)
      return null;
    final int vocabularyBand = <int>[
      100,
      300,
      800,
      1600,
      3200,
      5500,
      8500,
    ].where((int cutoff) => vocabulary >= cutoff).length;
    final double readingBand = _reading! * 7 / _readingQuestions.length;
    final double speakingBand = _speaking!.clamp(0, 100) * 7 / 100;
    return englishLevels[(vocabularyBand * 0.4 +
            readingBand * 0.35 +
            speakingBand * 0.25)
        .round()
        .clamp(0, 7)];
  }

  Future<void> _apply(String level) async {
    setState(() => _saving = true);
    try {
      final AcquirePreferencesDto current = ref.read(
        learningPreferencesProvider,
      );
      await ref
          .read(learningPreferencesProvider.notifier)
          .save(current.copyWith(level: level, dailyQuota: 10));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _read() async {
    final int? score = await Navigator.of(
      context,
    ).push<int>(MaterialPageRoute<int>(builder: (_) => const _ReadingQuiz()));
    if (!mounted || score == null) return;
    setState(() => _reading = score);
    await _persist();
  }

  Future<void> _speak() async {
    double? score;
    await showDialog<void>(
      context: context,
      builder: (_) => PronunciationAssessmentDialog(
        target: const PronunciationAssessmentTarget(
          text:
              'I used to take the bus to work, but now I walk whenever the '
              'weather is pleasant. It gives me time to plan my day and notice '
              'things I would otherwise miss.',
          videoSource: '',
          startMs: 0,
          endMs: 20000,
          videoDuration: Duration(seconds: 20),
        ),
        onResult: (PronunciationAssessmentResult result) =>
            score = result.suggestedScore ?? result.accuracy,
      ),
    );
    if (!mounted || score == null) return;
    setState(() => _speaking = score);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final int? vocabulary = ref.watch(
      vocabularyPlacementProvider.select(
        (PlacementRow profile) => profile['estimate'] as int?,
      ),
    );
    final String? estimate = _estimate(vocabulary);
    final String current = ref.watch(learningPreferencesProvider).level;
    return Scaffold(
      appBar: AppBar(title: const Text('英语水平评估')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ListTile(
            title: const Text('词汇量测试'),
            trailing: Text(vocabulary == null ? '开始' : '约 $vocabulary 词形'),
            onTap: () => context.push(SGRoute.vocabularyPlacement.route),
          ),
          ListTile(
            title: const Text('AI 口语朗读评测'),
            subtitle: const Text('朗读一段英文，使用已配置的发音评测服务'),
            trailing: Text(
              _speaking == null ? '开始' : '${_speaking!.round()} / 100',
            ),
            onTap: _speak,
          ),
          ListTile(
            title: const Text('英语阅读测试'),
            trailing: Text(
              _reading == null
                  ? '开始'
                  : '$_reading / ${_readingQuestions.length}',
            ),
            onTap: _read,
          ),
          const Divider(),
          Text(
            estimate == null ? '完成三项测试后显示综合估计' : '综合估计 · $estimate',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text('估计用于选择学习材料。口语项评估朗读表现。'),
          if (estimate != null)
            TextButton(
              onPressed: _saving ? null : () => _apply(estimate),
              child: const Text('用估计水平推荐视频'),
            ),
          const SizedBox(height: 16),
          Text('我的水平 · $current'),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final String level in englishLevels)
                ChoiceChip(
                  label: Text(level),
                  selected: current == level,
                  onSelected: _saving ? null : (_) => _apply(level),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _stage,
            decoration: const InputDecoration(labelText: '当前年级 / 学段'),
            items:
                const <String>[
                      '学龄前',
                      '小学一年级',
                      '小学二年级',
                      '小学三年级',
                      '小学四年级',
                      '小学五年级',
                      '小学六年级',
                      '初一',
                      '初二',
                      '初三',
                      '高一',
                      '高二',
                      '高三',
                      '大学',
                      '研究生',
                      '已毕业',
                    ]
                    .map(
                      (String value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
            onChanged: (String? value) async {
              setState(() => _stage = value);
              await _persist();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _work,
            decoration: const InputDecoration(labelText: '工作 / 职业'),
            items:
                const <String>[
                      '学生',
                      '教育',
                      '科技',
                      '商务与金融',
                      '医疗',
                      '服务业',
                      '自由职业',
                      '其他',
                    ]
                    .map(
                      (String value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
            onChanged: (String? value) async {
              setState(() => _work = value);
              await _persist();
            },
          ),
        ],
      ),
    );
  }
}

typedef _ReadingQuestion = ({
  String passage,
  String question,
  List<String> choices,
  int answer,
});

const List<_ReadingQuestion> _readingQuestions = <_ReadingQuestion>[
  (
    passage: 'Mia has a red bag. She takes it to school.',
    question: 'What does Mia take to school?',
    choices: <String>['A red bag', 'A blue coat', 'A book'],
    answer: 0,
  ),
  (
    passage:
        'The library closes at six, except on Thursdays, when it stays open until eight.',
    question: 'When does the library close on Thursday?',
    choices: <String>['At six', 'At eight', 'At seven'],
    answer: 1,
  ),
  (
    passage:
        'Ben had planned to cycle to work. When he saw how heavily it was raining, he left his bike at home and caught the bus instead.',
    question: 'Why did Ben take the bus?',
    choices: <String>[
      'His bike was broken',
      'He was meeting a friend',
      'The weather changed his plan',
    ],
    answer: 2,
  ),
  (
    passage:
        'Although the new timetable leaves fewer trains after midnight, the city argues that longer services during the evening will benefit more passengers overall.',
    question: 'What trade-off does the city describe?',
    choices: <String>[
      'Less late-night service for better evening service',
      'Cheaper tickets for slower trains',
      'Fewer evening trains for shorter trips',
    ],
    answer: 0,
  ),
  (
    passage:
        'The report attributes the rise in sales to the campaign. Yet a rival withdrew from the market during the same period, so the data do not isolate the campaign’s effect.',
    question: 'What is the main objection?',
    choices: <String>[
      'Sales actually fell',
      'Another event could explain part of the rise',
      'The campaign was never launched',
    ],
    answer: 1,
  ),
  (
    passage:
        'The reviewer grants that the novel’s fragmented chronology can feel arbitrary. She nevertheless argues that its refusal to supply a stable sequence forces readers to confront the limits of the narrator’s recollection.',
    question: 'How does the reviewer interpret the fragmented chronology?',
    choices: <String>[
      'As proof the narrator remembers everything',
      'As an accidental flaw with no purpose',
      'As a device that reveals the limitations of memory',
    ],
    answer: 2,
  ),
];

class _ReadingQuiz extends StatefulWidget {
  const _ReadingQuiz();
  @override
  State<_ReadingQuiz> createState() => _ReadingQuizState();
}

class _ReadingQuizState extends State<_ReadingQuiz> {
  int _index = 0;
  int _score = 0;

  void _answer(int answer) {
    if (answer == _readingQuestions[_index].answer) _score++;
    if (_index + 1 == _readingQuestions.length) {
      Navigator.of(context).pop(_score);
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final _ReadingQuestion item = _readingQuestions[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('阅读测试 · ${_index + 1} / ${_readingQuestions.length}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(item.passage, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(item.question),
          const SizedBox(height: 12),
          for (int i = 0; i < item.choices.length; i++)
            OutlinedButton(
              onPressed: () => _answer(i),
              child: Text(item.choices[i]),
            ),
          TextButton(onPressed: () => _answer(-1), child: const Text('不确定')),
        ],
      ),
    );
  }
}
