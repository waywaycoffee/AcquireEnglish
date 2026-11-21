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
    final Player? player = _previewPlayer;
    _previewPlayer = null;
    if (mounted) {
      setState(() {
        _previewing = null;
        _loadingPreview = false;
      });
    }
    await player?.dispose();
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
      final Player player = Player();
      _previewPlayer = player;
      await player.open(Media(result.url), play: true);
      if (!mounted || request != _previewRequest) return;
      setState(() => _loadingPreview = false);
      await player.stream.completed
          .firstWhere((bool value) => value)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      if (mounted && request == _previewRequest) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法试听，请稍后重试。')));
      }
    } finally {
      if (mounted && request == _previewRequest) await _stopPreview();
    }
  }

  @override
  void dispose() {
    _previewRequest++;
    final Player? player = _previewPlayer;
    if (player != null) unawaited(player.dispose());
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
        RawScrollbar(
          controller: _personas,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          thickness: 8,
          radius: const Radius.circular(8),
          thumbColor: AppDesignTokens.brandGreenDark,
          trackColor: AppDesignTokens.borderGray,
          child: SizedBox(
            height: 215,
            child: ListView.separated(
              controller: _personas,
              primary: false,
              padding: const EdgeInsets.only(bottom: 16),
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
        ),
        if (widget.onSelect == null)
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await _stopPreview();
                    if (!context.mounted) return;
                    await context.push('/digital-human');
                    if (mounted) await _refreshVoices();
                  },
                  icon: const Icon(Icons.record_voice_over_rounded),
                  label: const Text('开始情景口语'),
                ),
              ),
              TextButton(
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 112,
        padding: const EdgeInsets.all(8),
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
            const SizedBox(height: 8),
            Text(
              persona.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected
                    ? AppDesignTokens.brandGreenDark
                    : AppDesignTokens.textPrimary,
              ),
            ),
            Text(
              bilingual ? '中英同音色' : '中文另用音色',
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            IconButton(
              tooltip: playing
                  ? '停止试听 ${persona.displayName}'
                  : '试听 ${persona.displayName}',
              onPressed: onPreview,
              visualDensity: VisualDensity.compact,
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
          ],
        ),
      ),
    );
  }
}
