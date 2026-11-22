import 'assessment_panel.dart';
import '../digital_human/presentation/digital_human_coach_screen.dart';
import 'dart:convert';
import 'dart:math';
import '../authentication/presentation/auth_session.dart';
import '../sync/data/acquire_api_client.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import '../authentication/presentation/account_storage.dart';
import '../digital_human/data/oral_coach_pipeline_client.dart';
import '../membership/domain/module_access.dart';
import '../onboarding/presentation/onboarding_provider.dart';
import '../settings/presentation/settings_provider.dart';
import '../phrases/presentation/phrase_book_provider.dart';
import '../reading/data/reading_tts.dart';
import '../shared/data/word_pronunciation_service.dart';
import '../shared/presentation/pad/app_design_tokens.dart';

part 'module_curriculum.dart';

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

const _introLessons = <String, List<ModuleLesson>>{
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
  const ModuleScreen({super.key, required this.kind, this.initialLesson});
  final String kind;
  final int? initialLesson;
  @override
  ConsumerState<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends ConsumerState<ModuleScreen>
    with WidgetsBindingObserver {
  int lesson = 0, line = 0, role = 1;
  bool reveal = false, playing = false, repeat = false, hintDismissed = false;
  String? selected, error;
  int sequence = 0;
  Set<int> completedLessons = {};
  bool syncing = false;
  String syncStatus = '';
  bool saving = false;
  Timer? sleep;
  final expression = TextEditingController();
  final scroll = ScrollController();
  double speed = 0.75;

  /// Demo audio via [WordPronunciationService] so end-of-playback waits until
  /// audio actually started (media_kit can emit `completed` during open).
  Future<void> remoteSpeech(String text) async {
    final int generation = sequence;
    final String spoken = text.trim();
    if (spoken.isEmpty) return;

    final WordPronunciationService pronunciation =
        ref.read(wordPronunciationServiceProvider);
    // Cloud CosyVoice: keep near-native rate (slowing MP3 caused early cutoffs).
    final double cloudRate = (speed / 0.75).clamp(0.85, 1.25);
    Object? lastError;

    Future<void> playUrl(String url) async {
      if (!mounted || generation != sequence) return;
      await pronunciation.speak(
        spoken,
        recordedUrl: url,
        rate: cloudRate,
        allowSynthesisFallback: false,
      );
    }

    try {
      final String voice = loadReadingTtsGender().aliyunVoiceId;
      final String url = await ref
          .read(acquireApiClientProvider)
          .readingSpeech(spoken, voice);
      await playUrl(url);
      return;
    } catch (e) {
      lastError = e;
    }

    try {
      final String? url = await OralCoachPipelineClient().synthesizeSpeech(
        rawBaseUrl: ref.read(learningSettingsProvider).oralCoachPipelineUrl,
        text: spoken,
        digitalHumanId: 'mia',
        ttsVoice: widget.kind == 'ipa' || widget.kind == 'phonics'
            ? 'en-GB-SoniaNeural'
            : null,
      );
      if (url != null && url.isNotEmpty) {
        await playUrl(url);
        return;
      }
    } catch (e) {
      lastError = e;
    }

    if (!mounted || generation != sequence) return;
    try {
      await pronunciation.speak(
        spoken,
        rate: speed.clamp(0.5, 1.0),
        allowSynthesisFallback: true,
      );
      return;
    } catch (e) {
      lastError = e;
    }
    throw StateError('语音暂不可用: $lastError');
  }

  List<ModuleLesson> get lessons => moduleLessons[widget.kind] ?? const [];
  bool get _videoModuleGated =>
      widget.kind == 'listening' || widget.kind == 'dialogue';
  String get key => studyStorageKey(
    'module-v1:${widget.kind}',
    ref.read(studyAccountProvider),
  );

  Future<bool> _ensureLessonAllowed(int index) async {
    if (!_videoModuleGated || isFreePreviewIndex(index)) return true;
    final bool unlocked = await resolveModuleUnlocked(ref, 'video');
    if (unlocked) return true;
    if (mounted) {
      await showModulePaywall(context, moduleCode: 'video');
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(load);
  }

  Map<String, dynamic> snapshot() => {
    'version': 1,
    'lesson': lesson,
    'line': line,
    'completed': completedLessons.toList(),
  };
  Future<void> persist() async {
    if (!Hive.isBoxOpen('prefs')) throw StateError('storage');
    await Hive.box<String>(
      'prefs',
    ).put(key, jsonEncode({...snapshot(), 'dirty': true}));
  }

  void applyState(Map<String, dynamic> data) {
    lesson = (data['lesson'] as num).toInt().clamp(0, lessons.length - 1);
    line = ((data['line'] as num?)?.toInt() ?? 0).clamp(
      0,
      lessons[lesson].lines.length - 1,
    );
    completedLessons = (data['completed'] as List<dynamic>? ?? [])
        .whereType<int>()
        .where((i) => i >= 0 && i < lessons.length)
        .toSet();
  }

  void load() {
    if (!mounted) return;
    final raw = Hive.isBoxOpen('prefs')
        ? Hive.box<String>('prefs').get(key)
        : null;
    setState(() {
      completedLessons = {};
      line = 0;
      lesson = 0;
      try {
        if (raw != null) applyState(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        lesson = (int.tryParse(raw ?? '') ?? 0).clamp(0, lessons.length - 1);
      }
      final int? initial = widget.initialLesson;
      if (initial != null && lessons.isNotEmpty) {
        lesson = initial.clamp(0, lessons.length - 1);
        line = 0;
      }
      if (_videoModuleGated && !isFreePreviewIndex(lesson)) {
        lesson = 0;
        line = 0;
      }
    });
    if (_videoModuleGated &&
        widget.initialLesson != null &&
        !isFreePreviewIndex(widget.initialLesson!)) {
      unawaited(() async {
        final bool ok = await _ensureLessonAllowed(widget.initialLesson!);
        if (!mounted || !ok) return;
        setState(() {
          lesson = widget.initialLesson!.clamp(0, lessons.length - 1);
          line = 0;
        });
      }());
    }
    if (ref.read(authSessionProvider).isLoggedIn) unawaited(sync());
  }

  Future<void> sync() async {
    if (syncing) return;
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() => syncStatus = '登录后可同步，本机可继续学习');
      return;
    }
    final account = ref.read(studyAccountProvider);
    final storage = key;
    setState(() {
      syncing = true;
      syncStatus = '同步中';
    });
    bool active() => mounted && ref.read(studyAccountProvider) == account;
    try {
      final api = ref.read(acquireApiClientProvider);
      final cloud = await api.moduleProgress(widget.kind);
      if (!active()) return;
      final raw = Hive.isBoxOpen('prefs')
          ? Hive.box<String>('prefs').get(storage)
          : null;
      Map<String, dynamic> local = {};
      try {
        if (raw != null) local = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
      final remote = cloud['state'] as Map<String, dynamic>?;
      if (local['dirty'] != true && remote != null) {
        await Hive.box<String>(
          'prefs',
        ).put(storage, jsonEncode({...remote, 'dirty': false}));
        if (active()) setState(() => applyState(remote));
      } else {
        final sent = snapshot();
        sent['completed'] = {
          ...completedLessons,
          ...((remote?['completed'] as List<dynamic>?) ?? []).whereType<int>(),
        }.toList();
        final baseline = raw;
        final saved = await api.moduleProgress(
          widget.kind,
          upload: {'revision': cloud['revision'], 'state': sent},
        );
        if (!active()) return;
        if (Hive.box<String>('prefs').get(storage) == baseline) {
          final state = saved['state'] as Map<String, dynamic>;
          await Hive.box<String>(
            'prefs',
          ).put(storage, jsonEncode({...state, 'dirty': false}));
          if (active())
            setState(
              () => completedLessons = (state['completed'] as List<dynamic>)
                  .cast<int>()
                  .toSet(),
            );
        }
      }
      if (active()) setState(() => syncStatus = '已同步');
    } catch (_) {
      if (active()) setState(() => syncStatus = '本机进度保留，点击重试同步');
    } finally {
      if (active()) setState(() => syncing = false);
    }
  }

  void stop() {
    sequence++;
    sleep?.cancel();
    unawaited(ref.read(wordPronunciationServiceProvider).stop());
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
    // Avoid ref.read in dispose — Riverpod forbids it after unmount.
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
          await remoteSpeech(item.lines[i]);
        }
      } while (all && repeat && mounted && generation == sequence);
    } catch (_) {
      if (mounted) setState(() => error = '播放失败，请检查网络和语音服务后重试。');
    } finally {
      if (mounted && generation == sequence) setState(() => playing = false);
    }
  }

  Future<void> complete() async {
    if (saving || selected != lessons[lesson].answer) return;
    final account = ref.read(studyAccountProvider);
    final previous = snapshot();
    setState(() => saving = true);
    try {
      completedLessons.add(lesson);
      final int next = (lesson + 1) % lessons.length;
      if (!await _ensureLessonAllowed(next)) {
        if (!mounted || account != ref.read(studyAccountProvider)) return;
        setState(() {
          saving = false;
          selected = null;
          reveal = false;
        });
        await persist();
        return;
      }
      lesson = next;
      line = 0;
      await persist();
      if (!mounted || account != ref.read(studyAccountProvider)) return;
      if (scroll.hasClients) scroll.jumpTo(0);
      setState(() {
        selected = null;
        reveal = false;
      });
      unawaited(sync());
    } catch (_) {
      if (mounted && account == ref.read(studyAccountProvider))
        setState(() {
          applyState(previous);
          error = '进度未保存，请重试。';
        });
    } finally {
      if (mounted && account == ref.read(studyAccountProvider))
        setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(studyAccountProvider, (_, __) {
      stop();
      expression.clear();
      setState(() {
        syncing = false;
        saving = false;
        syncStatus = '';
        line = 0;
        selected = null;
        reveal = false;
      });
      load();
    });
    final item = lessons[lesson];
    final choices = List<String>.of(item.choices)
      ..shuffle(Random(lesson * 7919 + 17));
    final theme = Theme.of(context);
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        title: Text(moduleTitles[widget.kind] ?? '学习'),
        actions: [
          IconButton(
            tooltip: '同步进度',
            onPressed: syncing ? null : sync,
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
        ],
      ),
      body: ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(20, 16, 20, 28 + bottomInset),
        children: [
          if (syncStatus.isNotEmpty) ...[
            Text(
              syncStatus,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            '已完成 ${completedLessons.length} / ${lessons.length} 课',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '入门课程 · ${lesson + 1} / ${lessons.length}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          if (!hintDismissed) ...[
            Builder(
              builder: (BuildContext context) {
                final profile = ref.watch(onboardingProvider);
                String? tip;
                if (widget.kind == 'ipa' && profile.showSyllableHints) {
                  tip = '提示：可以先按音节拆开读，听准再拼回去。可随时跳过。';
                } else if (widget.kind == 'phonics' &&
                    profile.showPhonicsHints) {
                  tip = '提示：先盯住字母组合的发音，再合成整词。可随时跳过。';
                } else if (widget.kind == 'dialogue' &&
                    (profile.showSyllableHints || profile.showPhonicsHints)) {
                  tip = '提示：生词可先拆音节或用字母音试读，不会也不影响继续对话。';
                }
                if (tip == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: AppDesignTokens.softGray,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        tip,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => setState(() => hintDismissed = true),
                        child: const Text('跳过'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppDesignTokens.borderGray),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: lesson,
                  isExpanded: true,
                  items: [
                    for (int i = 0; i < lessons.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          _videoModuleGated && !isFreePreviewIndex(i)
                              ? '${lessons[i].title} · 需开通'
                              : lessons[i].title,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    unawaited(() async {
                      if (!await _ensureLessonAllowed(v)) return;
                      if (!mounted) return;
                      stop();
                      setState(() {
                        lesson = v;
                        line = 0;
                        selected = null;
                        reveal = false;
                      });
                      unawaited(
                        persist().catchError((_) {
                          if (mounted) {
                            setState(() => error = '位置保存失败，请重试');
                          }
                        }),
                      );
                    }());
                  },
                ),
              ),
            ),
          ),
          if (widget.kind == 'dialogue') ...[
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('角色 A')),
                ButtonSegment(value: 1, label: Text('角色 B')),
              ],
              selected: {role},
              onSelectionChanged: (v) => setState(() => role = v.first),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            widget.kind == 'ipa'
                ? '先听示范词，分辨音素，再读例句。'
                : widget.kind == 'phonics'
                ? '先听字母组合，再尝试合成完整单词。'
                : '先听示范，再尝试用自己的话表达。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppDesignTokens.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppDesignTokens.borderGray),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.kind == 'dialogue'
                        ? '${line % 2 == 0 ? 'A' : 'B'}${line % 2 == role ? ' · 轮到你说' : ''}'
                        : '第 ${line + 1} 句',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.kind == 'listening' && !reveal
                        ? '先听一遍，再展开字幕'
                        : item.lines[line],
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  if (reveal) ...[
                    const SizedBox(height: 12),
                    Text(
                      item.meanings[line],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppDesignTokens.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => play(),
                        icon: Icon(
                          playing ? Icons.stop_rounded : Icons.volume_up_rounded,
                        ),
                        label: Text(playing ? '停止' : '听示范'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => reveal = !reveal),
                        child: Text(reveal ? '收起提示' : '展开提示'),
                      ),
                      TextButton(
                        onPressed: () {
                          stop();
                          setState(() => line = (line + 1) % item.lines.length);
                          unawaited(
                            persist().catchError((_) {
                              if (mounted) {
                                setState(() => error = '位置保存失败，请重试');
                              }
                            }),
                          );
                        },
                        child: const Text('下一句'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '播放语速',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppDesignTokens.textSecondary,
                ),
              ),
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
              Text(
                speed.toStringAsFixed(1),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
          if (error != null) ...[
            Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.kind == 'listening') ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
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
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          AssessmentPanel(
            key: ValueKey('${widget.kind}-$lesson-$line'),
            reference: item.lines[line],
          ),
          const SizedBox(height: 12),
          if (widget.kind == 'chunks') ...[
            Text(
              '替换练习：保留句型，换成自己的需求。例如 this form → my luggage。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: expression,
              maxLength: 240,
              decoration: const InputDecoration(labelText: '写下你自己的完整表达'),
            ),
            OutlinedButton(
              onPressed: () async {
                if (expression.text.trim().isEmpty || playing) return;

                try {
                  await remoteSpeech(expression.text.trim());
                } catch (_) {
                  if (mounted) setState(() => error = '示范播放失败，请重试。');
                }
              },
              child: const Text('听听我的表达'),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.kind == 'ipa' || widget.kind == 'phonics')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.push('/digital-human'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('进入口语练习 · 支持录音与文字'),
              ),
            ),
          if (widget.kind == 'dialogue')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  stop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DigitalHumanCoachScreen(
                        lessonTitle: item.title,
                        lessonText: [
                          for (int i = 0; i < item.lines.length; i++)
                            '${i.isEven ? 'A' : 'B'}: ${item.lines[i]}',
                        ].join('\n'),
                        practiceRole: role == 0 ? 'A' : 'B',
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('分角色语音 / 文字实战与反馈'),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
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
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(added ? '已保存到表达库与复习计划' : '表达已在库中'),
                      ),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('保存失败，请重试')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.bookmark_outline),
              label: const Text('收藏当前表达并复习'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppDesignTokens.borderGray),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.question,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final option in choices)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(option),
                      value: option,
                      groupValue: selected,
                      onChanged: (v) => setState(() => selected = v),
                    ),
                  if (selected != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        selected == item.answer
                            ? '正确，可以完成本课。'
                            : '再听一遍，试着重新选择。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected == item.answer
                              ? AppDesignTokens.brandGreen
                              : AppDesignTokens.textSecondary,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          !saving && selected == item.answer ? complete : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('完成并保存进度'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.kind == 'ipa' ||
              widget.kind == 'phonics' ||
              widget.kind == 'chunks') ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push(
                '/words/syllabus/cloud?tab=${widget.kind == 'chunks' ? 'pattern' : widget.kind}',
              ),
              child: const Text('更多课程 · 下载完整学习书'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '示范语音优先用服务器阿里云配音；不可用时再用本机朗读。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
