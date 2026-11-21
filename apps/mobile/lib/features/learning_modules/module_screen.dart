import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import '../authentication/presentation/account_storage.dart';
import '../shared/data/word_pronunciation_service.dart';
import '../phrases/presentation/phrase_book_provider.dart';

class ModuleLesson {
  const ModuleLesson(
    this.title,
    this.lines,
    this.meanings,
    this.question,
    this.answer,
    this.choices,
  );
  final String title, question, answer;
  final List<String> lines, meanings, choices;
}

const moduleLessons = <String, List<ModuleLesson>>{
  'ipa': [
    ModuleLesson(
      '/ɪ/ 和 /iː/',
      ['ship', 'sheep', 'I see a sheep.'],
      ['短元音 /ɪ/', '长元音 /iː/', '我看见一只羊。'],
      '哪个词含 /iː/？',
      'sheep',
      ['ship', 'sheep'],
    ),
    ModuleLesson(
      '/æ/ 和 /e/',
      ['bad', 'bed', 'The bag is on the bed.'],
      ['/æ/', '/e/', '包在床上。'],
      '哪个词含 /æ/？',
      'bad',
      ['bed', 'bad'],
    ),
  ],
  'phonics': [
    ModuleLesson(
      '短元音 a',
      ['cat', 'cat', 'map', 'bag'],
      ['c /k/ + a /æ/ + t /t/；按钮示范合音后的词', '猫', '地图', '包'],
      'cat 中 a 的发音？',
      '/æ/',
      ['/æ/', '/eɪ/'],
    ),
    ModuleLesson(
      '字母组合 sh',
      ['ship', 'ship', 'shop', 'fish'],
      ['sh 对应 /ʃ/；在完整词 ship 中听组合音', '船', '商店', '鱼'],
      '哪个单词含 sh？',
      'fish',
      ['cat', 'fish'],
    ),
  ],
  'chunks': [
    ModuleLesson(
      '礼貌请求',
      [
        'Could you help me with this form?',
        'Could you help me with my luggage?',
      ],
      ['你能帮我填这张表吗？', '你能帮我拿行李吗？'],
      '请求帮忙时使用？',
      'Could you help me with…?',
      ['Could you help me with…?', 'Good night.'],
    ),
    ModuleLesson(
      '表达想要',
      ['I would like a cup of tea.', 'I would like some water.'],
      ['我想要一杯茶。', '我想要一些水。'],
      '礼貌表达想要？',
      'I would like…',
      ['I would like…', 'See you.'],
    ),
  ],
  'listening': [
    ModuleLesson(
      'Morning routine',
      [
        'I get up at seven.',
        'I make a cup of tea.',
        'Then I walk to the station.',
      ],
      ['我七点起床。', '我泡一杯茶。', '然后我走到车站。'],
      '说话者怎样去车站？',
      '步行',
      ['步行', '开车'],
    ),
    ModuleLesson(
      'At the cafe',
      [
        'I would like a coffee, please.',
        'For here or to go?',
        'To go, please.',
      ],
      ['请给我一杯咖啡。', '堂食还是外带？', '请外带。'],
      '顾客选择了？',
      '外带',
      ['堂食', '外带'],
    ),
  ],
  'dialogue': [
    ModuleLesson(
      '咖啡店点单',
      [
        'What would you like?',
        'I would like a latte, please.',
        'For here or to go?',
        'To go, please.',
      ],
      ['你想要什么？', '请给我一杯拿铁。', '堂食还是外带？', '请外带。'],
      '顾客要了什么？',
      '拿铁',
      ['拿铁', '茶'],
    ),
    ModuleLesson(
      '酒店入住',
      [
        'Do you have a reservation?',
        'Yes, under the name Lee.',
        'May I see your passport?',
        'Here you are.',
      ],
      ['你有预订吗？', '有，以Lee的名字预订。', '可以看一下护照吗？', '给你。'],
      '客人是否有预订？',
      '有',
      ['有', '没有'],
    ),
  ],
};
const moduleTitles = {
  'ipa': '国际音标',
  'phonics': '自然拼读',
  'chunks': '常用应用语块',
  'listening': '磨耳朵',
  'dialogue': '场景对话库',
};

class ModuleScreen extends ConsumerStatefulWidget {
  const ModuleScreen({super.key, required this.kind});
  final String kind;
  @override
  ConsumerState<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends ConsumerState<ModuleScreen>
    with WidgetsBindingObserver {
  int lesson = 0, line = 0, role = 1;
  bool reveal = false, playing = false, repeat = false;
  String? selected, error;
  int sequence = 0;
  Timer? sleep;
  final expression = TextEditingController();
  final scroll = ScrollController();
  double speed = 0.75;
  WordPronunciationService? speech;
  List<ModuleLesson> get lessons => moduleLessons[widget.kind] ?? const [];
  String get key => studyStorageKey(
    'module-v1:${widget.kind}',
    ref.read(studyAccountProvider),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(load);
  }

  void load() {
    if (!mounted) return;
    final raw = Hive.isBoxOpen('prefs')
        ? Hive.box<String>('prefs').get(key)
        : null;
    setState(
      () =>
          lesson = (int.tryParse(raw ?? '') ?? 0).clamp(0, lessons.length - 1),
    );
  }

  void stop() {
    sequence++;
    sleep?.cancel();
    unawaited(speech?.stop());
    if (mounted) setState(() => playing = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void dispose() {
    sequence++;
    sleep?.cancel();
    unawaited(speech?.stop());
    expression.dispose();
    scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> play({bool all = false}) async {
    if (playing) {
      stop();
      return;
    }
    final generation = ++sequence;
    final item = lessons[lesson];
    speech = WordPronunciationService(selectedRate: speed);
    setState(() {
      playing = true;
      error = null;
    });
    try {
      do {
        for (
          int i = all ? 0 : line;
          i < (all ? item.lines.length : line + 1);
          i++
        ) {
          if (!mounted || generation != sequence) return;
          setState(() => line = i);
          await speech!.speak(item.lines[i]);
        }
      } while (all && repeat && mounted && generation == sequence);
    } catch (_) {
      if (mounted) setState(() => error = '播放失败，请检查系统英语语音引擎后重试。');
    } finally {
      if (mounted && generation == sequence) setState(() => playing = false);
    }
  }

  Future<void> complete() async {
    if (selected != lessons[lesson].answer) return;
    final next = (lesson + 1) % lessons.length;
    try {
      if (!Hive.isBoxOpen('prefs')) throw StateError('storage');
      await Hive.box<String>('prefs').put(key, '$next');
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
      if (mounted)
        setState(() {
          lesson = next;
          line = 0;
          selected = null;
          reveal = false;
        });
    } catch (_) {
      if (mounted) setState(() => error = '进度未保存，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(studyAccountProvider, (_, __) {
      stop();
      expression.clear();
      setState(() {
        line = 0;
        selected = null;
        reveal = false;
      });
      load();
    });
    final item = lessons[lesson];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF141414) : const Color(0xFFF5F5F5),
      appBar: AppBar(title: Text(moduleTitles[widget.kind] ?? '学习')),
      body: ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '入门课程 · ${lesson + 1} / ${lessons.length}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          DropdownButton<int>(
            value: lesson,
            isExpanded: true,
            items: [
              for (int i = 0; i < lessons.length; i++)
                DropdownMenuItem(value: i, child: Text(lessons[i].title)),
            ],
            onChanged: (v) {
              stop();
              setState(() {
                lesson = v!;
                line = 0;
                selected = null;
                reveal = false;
              });
            },
          ),
          if (widget.kind == 'dialogue')
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('角色 A')),
                ButtonSegment(value: 1, label: Text('角色 B')),
              ],
              selected: {role},
              onSelectionChanged: (v) => setState(() => role = v.first),
            ),
          const SizedBox(height: 12),
          Text(
            widget.kind == 'ipa'
                ? '先听示范词，分辨音素，再读例句。'
                : widget.kind == 'phonics'
                ? '先听字母组合，再尝试合成完整单词。'
                : '先听示范，再尝试用自己的话表达。',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.kind == 'dialogue'
                        ? '${line % 2 == 0 ? 'A' : 'B'}${line % 2 == role ? ' · 轮到你说' : ''}'
                        : '第 ${line + 1} 句',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.kind == 'listening' && !reveal
                        ? '先听一遍，再展开字幕'
                        : item.lines[line],
                    style: const TextStyle(fontSize: 25),
                  ),
                  if (reveal) ...[
                    const SizedBox(height: 14),
                    Text(item.meanings[line]),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => play(),
                        icon: Icon(playing ? Icons.stop : Icons.volume_up),
                        label: Text(playing ? '停止' : '听示范'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => reveal = !reveal),
                        child: Text(reveal ? '收起提示' : '展开提示'),
                      ),
                      TextButton(
                        onPressed: () {
                          stop();
                          setState(() => line = (line + 1) % item.lines.length);
                        },
                        child: const Text('下一句'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              const Text('播放语速'),
              Expanded(
                child: Slider(
                  value: speed,
                  min: .3,
                  max: 1,
                  divisions: 7,
                  label: speed.toStringAsFixed(1),
                  onChanged: playing ? null : (v) => setState(() => speed = v),
                ),
              ),
            ],
          ),
          if (error != null) Text(error!),
          if (widget.kind == 'listening') ...[
            SwitchListTile(
              title: const Text('整篇循环'),
              value: repeat,
              onChanged: (v) => setState(() => repeat = v),
            ),
            FilledButton(
              onPressed: () => play(all: true),
              child: const Text('播放全文 / 停止'),
            ),
            TextButton(
              onPressed: () {
                sleep?.cancel();
                sleep = Timer(const Duration(minutes: 10), stop);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('将在10分钟后停止')));
              },
              child: const Text('10分钟定时停止'),
            ),
          ],
          if (widget.kind == 'chunks') ...[
            const Text('替换练习：保留句型，换成自己的需求。例如 this form → my luggage。'),
            TextField(
              controller: expression,
              maxLength: 240,
              decoration: const InputDecoration(labelText: '写下你自己的完整表达'),
            ),
            OutlinedButton(
              onPressed: () async {
                if (expression.text.trim().isEmpty || playing) return;
                speech = WordPronunciationService(selectedRate: speed);
                try {
                  await speech!.speak(expression.text.trim());
                } catch (_) {
                  if (mounted) setState(() => error = '示范播放失败，请重试。');
                }
              },
              child: const Text('听听我的表达'),
            ),
          ],
          if (widget.kind == 'ipa' || widget.kind == 'phonics')
            OutlinedButton(
              onPressed: () => context.push('/digital-human'),
              child: const Text('进入口语练习 · 支持录音与文字'),
            ),
          if (widget.kind == 'dialogue')
            OutlinedButton(
              onPressed: () => context.push(
                '/digital-human?scenario=${lesson == 0 ? 'restaurant' : 'hotel'}',
              ),
              child: const Text('进入外教语音 / 文字对话'),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final added = await ref
                    .read(phraseBookProvider.notifier)
                    .addSharedLearningCard(
                      token: 'module-${widget.kind}-$lesson-$line',
                      english: item.lines[line],
                      chinese: item.meanings[line],
                      title: item.title,
                      source: moduleTitles[widget.kind]!,
                    );
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(added ? '已保存到表达库与复习计划' : '表达已在库中')),
                  );
              } catch (_) {
                if (context.mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
              }
            },
            icon: const Icon(Icons.bookmark_outline),
            label: const Text('收藏当前表达并复习'),
          ),
          const Divider(height: 32),
          Text(item.question, style: Theme.of(context).textTheme.titleMedium),
          for (final option in item.choices)
            RadioListTile<String>(
              title: Text(option),
              value: option,
              groupValue: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          if (selected != null)
            Text(selected == item.answer ? '正确，可以完成本课。' : '再听一遍，试着重新选择。'),
          FilledButton(
            onPressed: selected == item.answer ? complete : null,
            child: const Text('完成并保存进度'),
          ),
          if (widget.kind == 'ipa' ||
              widget.kind == 'phonics' ||
              widget.kind == 'chunks')
            TextButton(
              onPressed: () => context.push(
                '/words/syllabus/cloud?tab=${widget.kind == 'chunks' ? 'pattern' : widget.kind}',
              ),
              child: const Text('更多课程 · 下载完整学习书'),
            ),
          const Text('示范音频使用设备语音合成，不等同于真人发音评分。练习不会自动公开，也不自动发放积分。'),
        ],
      ),
    );
  }
}
