import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/coach_english_voices.dart';
import '../data/digital_human_catalog.dart';
import '../data/oral_coach_pipeline_client.dart';

/// Home-page row: pick a near-real digital-human coach persona.
class DigitalHumanPicker extends ConsumerStatefulWidget {
  const DigitalHumanPicker({super.key, this.onSelect});

  final ValueChanged<DigitalHumanPersona>? onSelect;

  @override
  ConsumerState<DigitalHumanPicker> createState() => _DigitalHumanPickerState();
}

enum _PersonaFilter {
  all('全部'),
  women('女外教'),
  men('男外教'),
  children('儿童伙伴');

  const _PersonaFilter(this.label);
  final String label;

  bool matches(DigitalHumanPersona persona) => switch (this) {
    all => true,
    women => !persona.isChild && persona.isFemaleVoice,
    men => !persona.isChild && !persona.isFemaleVoice,
    children => persona.isChild,
  };
}

class _DigitalHumanPickerState extends ConsumerState<DigitalHumanPicker> {
  final ScrollController _personas = ScrollController();
  _PersonaFilter _filter = _PersonaFilter.all;

  final OralCoachPipelineClient _pipeline = OralCoachPipelineClient();
  final Map<String, String?> _savedVoices = <String, String?>{};
  Player? _previewPlayer;
  Completer<bool>? _previewDone;
  String? _previewing;
  bool _loadingPreview = false;
  int _previewRequest = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshVoices());
  }

  Future<void> _refreshVoices() async {
    try {
      final SharedPreferencesAsync preferences = SharedPreferencesAsync();
      final Map<String, String?> voices = Map<String, String?>.fromEntries(
        await Future.wait(
          digitalHumanCatalog.map(
            (DigitalHumanPersona persona) async => MapEntry<String, String?>(
              persona.id,
              await readCoachVoicePreference(preferences, persona),
            ),
          ),
        ),
      );
      if (mounted) setState(() => _savedVoices.addAll(voices));
    } catch (_) {
      // Show each coach's recommended voice if saved preferences are unavailable.
    }
  }

  Future<void> _stopPreview() async {
    _previewRequest++;
    final Completer<bool>? done = _previewDone;
    _previewDone = null;
    if (done != null && !done.isCompleted) {
      done.complete(false);
    }
    final Player? player = _previewPlayer;
    _previewPlayer = null;
    if (mounted) {
      setState(() {
        _previewing = null;
        _loadingPreview = false;
      });
    }
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {
      // Player may already be torn down.
    }
    try {
      await player.dispose();
    } catch (_) {
      // Ignore dispose races when switching previews quickly.
    }
  }

  Future<bool> _playPreviewUrl(String url, int request) async {
    if (!mounted || request != _previewRequest) return false;
    final Player player = Player();
    final Completer<bool> done = Completer<bool>();
    _previewPlayer = player;
    _previewDone = done;
    StreamSubscription<bool>? completedSub;
    StreamSubscription<String>? errorSub;
    try {
      completedSub = player.stream.completed.listen((bool value) {
        if (value && !done.isCompleted) done.complete(true);
      });
      errorSub = player.stream.error.listen((String _) {
        if (!done.isCompleted) done.complete(false);
      });
      // Subscribe before open so short/cached clips cannot miss completion.
      await player.open(Media(url), play: true);
      if (!mounted || request != _previewRequest) return false;
      if (mounted) setState(() => _loadingPreview = false);
      return await done.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => false,
      );
    } finally {
      await completedSub?.cancel();
      await errorSub?.cancel();
      if (identical(_previewDone, done)) {
        _previewDone = null;
      }
      if (identical(_previewPlayer, player)) {
        _previewPlayer = null;
        try {
          await player.stop();
        } catch (_) {}
        try {
          await player.dispose();
        } catch (_) {}
      }
    }
  }

  Future<void> _preview(DigitalHumanPersona persona) async {
    final bool stop = _previewing == persona.id;
    final Future<void> stopping = _stopPreview();
    final int request = _previewRequest;
    if (stop) {
      await stopping;
      return;
    }
    final String baseUrl = ref
        .read(learningSettingsProvider)
        .oralCoachPipelineUrl;
    setState(() {
      _previewing = persona.id;
      _loadingPreview = true;
    });
    var failed = false;
    try {
      await stopping;
      String? saved = _savedVoices[persona.id];
      try {
        saved = await readCoachVoicePreference(
          SharedPreferencesAsync(),
          persona,
        );
      } catch (_) {
        // Use the cached selection or recommended voice.
      }
      if (!mounted || request != _previewRequest) return;
      setState(() => _savedVoices[persona.id] = saved);
      final String voice =
          saved ?? persona.recommendedVoiceId ?? persona.edgeVoiceEn;
      final bool bilingual = isBilingualCoachVoice(voice);
      final result = await _pipeline.synthesizeSpeechWithProvider(
        rawBaseUrl: baseUrl,
        text: bilingual
            ? '你好，很高兴见到你。 Hi! Let’s practise English together.'
            : 'Hi! It’s nice to meet you. Let’s practise English together.',
        digitalHumanId: persona.id,
        ttsVoice: voice,
        language: bilingual ? 'zh' : 'en',
      );
      if (!mounted || request != _previewRequest) return;
      if (result == null) throw StateError('Missing preview audio');
      if (result.provider == 'edge') {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本次试听使用备用音色（Edge）')));
      }
      final bool played = await _playPreviewUrl(result.url, request);
      if (!mounted || request != _previewRequest) return;
      if (!played) failed = true;
    } catch (_) {
      if (mounted && request == _previewRequest) failed = true;
    } finally {
      if (mounted && request == _previewRequest) {
        if (failed) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('暂时无法试听，请稍后重试。')));
        }
        await _stopPreview();
      }
    }
  }

  @override
  void dispose() {
    _previewRequest++;
    final Player? player = _previewPlayer;
    _previewPlayer = null;
    if (player != null) {
      unawaited(() async {
        try {
          await player.stop();
        } catch (_) {}
        try {
          await player.dispose();
        } catch (_) {}
      }());
    }
    _personas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final DigitalHumanPersona selected = settings.selectedDigitalHuman;
    final List<DigitalHumanPersona> visible = digitalHumanCatalog
        .where(_filter.matches)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '选择数字人形象',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '探索版支持自定义形象；声音复刻 / 高清导出 / 团队协作需更高档位',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '当前：${selected.displayName} · ${selected.tagline} · ${selected.voiceLabel}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final _PersonaFilter filter in _PersonaFilter.values)
              ChoiceChip(
                label: Text(filter.label),
                selected: filter == _filter,
                onSelected: (bool selected) {
                  if (!selected) return;
                  if (_personas.hasClients) _personas.jumpTo(0);
                  setState(() => _filter = filter);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _PersonaCard.cardHeight,
          child: ListView.separated(
            controller: _personas,
            primary: false,
            padding: EdgeInsets.zero,
            scrollDirection: Axis.horizontal,
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final DigitalHumanPersona persona = visible[index];
              final bool active = persona.id == selected.id;
              return _PersonaCard(
                persona: persona,
                selected: active,
                bilingual: isBilingualCoachVoice(
                  _savedVoices[persona.id] ?? persona.recommendedVoiceId,
                ),
                playing: _previewing == persona.id,
                loading: _previewing == persona.id && _loadingPreview,
                onPreview: () => unawaited(_preview(persona)),
                onTap: () {
                  final ValueChanged<DigitalHumanPersona>? onSelect =
                      widget.onSelect;
                  if (onSelect != null) {
                    onSelect(persona);
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setDigitalHumanId(persona.id);
                },
              );
            },
          ),
        ),
        if (widget.onSelect == null) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    await _stopPreview();
                    if (!context.mounted) return;
                    await context.push('/digital-human');
                    if (mounted) await _refreshVoices();
                  },
                  icon: const Icon(Icons.record_voice_over_rounded, size: 18),
                  label: const Text('开始情景口语'),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  if (_personas.hasClients) {
                    _personas.animateTo(
                      _personas.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: const Text('更多 ›'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.selected,
    required this.bilingual,
    required this.playing,
    required this.loading,
    required this.onPreview,
    required this.onTap,
  });

  final DigitalHumanPersona persona;
  final bool selected;
  final bool bilingual;
  final bool playing;
  final bool loading;
  final VoidCallback onPreview;
  final VoidCallback onTap;

  static const double cardHeight = 196;
  static const double cardWidth = 112;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? AppDesignTokens.brandGreenDark
                    : AppDesignTokens.borderGray,
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected ? AppDesignTokens.toyCardShadow : null,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        persona.assetPath,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: AppDesignTokens.skyLight,
                          child: Icon(
                            Icons.face_retouching_natural_rounded,
                            color: AppDesignTokens.brandGreenDark,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    persona.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: selected
                          ? AppDesignTokens.brandGreenDark
                          : AppDesignTokens.textPrimary,
                    ),
                  ),
                  Text(
                    bilingual ? '中英同音色' : '中文另用音色',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: IconButton(
                      tooltip: playing
                          ? '停止试听 ${persona.displayName}'
                          : '试听 ${persona.displayName}',
                      onPressed: onPreview,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints.tightFor(width: 28, height: 28),
                      iconSize: 22,
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              playing
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_circle_outline,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
