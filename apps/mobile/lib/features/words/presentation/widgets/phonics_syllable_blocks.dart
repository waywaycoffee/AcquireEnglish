import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../domain/word_morphology.dart';

/// Vowels are always red; consonants/syllable groups use distinct text colors.
const Color _kVowelRed = Color(0xFFE11D48);

/// Light-surface text colors for non-vowel segments (cycled by syllable).
const List<Color> _kPhonicsTextLight = <Color>[
  Color(0xFF111827),
  Color(0xFF1D4ED8),
  Color(0xFF047857),
  Color(0xFFB45309),
  Color(0xFF7C3AED),
  Color(0xFFBE185D),
];

/// Dark-surface text colors for non-vowel segments (cycled by syllable).
const List<Color> _kPhonicsTextDark = <Color>[
  Color(0xFFF3F4F6),
  Color(0xFF93C5FD),
  Color(0xFF86EFAC),
  Color(0xFFFCD34D),
  Color(0xFFC4B5FD),
  Color(0xFFF9A8D4),
];

Brightness _surfaceBrightness(BuildContext context, {Brightness? surface}) {
  return surface ?? Theme.of(context).brightness;
}

Color _onSurfaceInk(BuildContext context, {Brightness? surface}) {
  final Brightness brightness = _surfaceBrightness(context, surface: surface);
  if (surface == null) {
    return Theme.of(context).colorScheme.onSurface;
  }
  return brightness == Brightness.dark
      ? const Color(0xFFF3F4F6)
      : const Color(0xFF111827);
}

Color _mutedInk(BuildContext context, {Brightness? surface}) {
  final Brightness brightness = _surfaceBrightness(context, surface: surface);
  return brightness == Brightness.dark
      ? const Color(0xFFB0B6C3)
      : const Color(0xFF4B5563);
}

Color _segmentTextColor(
  BuildContext context,
  PhonicsSegment seg, {
  Brightness? surface,
}) {
  if (seg.kind == 'vowel') {
    return _kVowelRed;
  }
  final Brightness brightness = _surfaceBrightness(context, surface: surface);
  final List<Color> palette =
      brightness == Brightness.dark ? _kPhonicsTextDark : _kPhonicsTextLight;
  return palette[seg.colorIndex % palette.length];
}

/// Headword with vowel letters tinted for natural-phonics awareness.
///
/// When [enableSyllableToggle] is true, tapping toggles round-dot syllable
/// separation (e.g. ability → a·bil·i·ty); tap again restores the whole word.
class ColoredVowelHeadword extends StatefulWidget {
  const ColoredVowelHeadword({
    required this.word,
    this.fontSize = 34,
    this.textAlign = TextAlign.center,
    this.showLegend = false,
    this.onTap,
    this.enableSyllableToggle = false,
    super.key,
  });

  final String word;
  final double fontSize;
  final TextAlign textAlign;
  final bool showLegend;
  final VoidCallback? onTap;

  /// Tap headword to show / hide `·` syllable separators.
  final bool enableSyllableToggle;

  @override
  State<ColoredVowelHeadword> createState() => _ColoredVowelHeadwordState();
}

class _ColoredVowelHeadwordState extends State<ColoredVowelHeadword> {
  bool _showSyllableDots = false;

  @override
  void didUpdateWidget(covariant ColoredVowelHeadword oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word.trim().toLowerCase() !=
        widget.word.trim().toLowerCase()) {
      _showSyllableDots = false;
    }
  }

  List<InlineSpan> _letterSpans(String raw, Color consonant) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = 0; i < raw.length; i++) {
      final String ch = raw[i];
      final bool vowel = isVowelLetter(
        ch,
        prev: i > 0 ? raw[i - 1] : null,
      );
      spans.add(
        TextSpan(
          text: ch,
          style: TextStyle(
            fontSize: widget.fontSize,
            height: 1.2,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            color: vowel ? _kVowelRed : consonant,
          ),
        ),
      );
    }
    return spans;
  }

  List<InlineSpan> _syllableSpans(String raw, Color consonant, Color muted) {
    final List<String> syllables = splitEnglishSyllables(raw);
    if (syllables.length <= 1) {
      return _letterSpans(raw, consonant);
    }
    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = 0; i < syllables.length; i++) {
      if (i > 0) {
        spans.add(
          TextSpan(
            text: '·',
            style: TextStyle(
              fontSize: widget.fontSize * 0.85,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
        );
      }
      spans.addAll(_letterSpans(syllables[i], consonant));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final String raw = widget.word.trim();
    if (raw.isEmpty) return const SizedBox.shrink();
    final Color consonant = _onSurfaceInk(context);
    final Color muted = _mutedInk(context);
    final bool showDots =
        widget.enableSyllableToggle && _showSyllableDots;
    final List<InlineSpan> spans = showDots
        ? _syllableSpans(raw, consonant, muted)
        : _letterSpans(raw, consonant);
    final Widget rich = Text.rich(
      TextSpan(children: spans),
      textAlign: widget.textAlign,
    );
    final String legend = widget.enableSyllableToggle
        ? (showDots
            ? '圆点 = 音节分界 · 再点恢复'
            : '红色 = 元音 · 点单词显示音节')
        : (widget.onTap == null
            ? '红色 = 元音'
            : '红色 = 元音 · 点单词展开音节 / 拼读');
    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.textAlign == TextAlign.start
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: <Widget>[
        rich,
        if (widget.showLegend) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            legend,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
        ],
      ],
    );
    final VoidCallback? handleTap = widget.enableSyllableToggle
        ? () {
            setState(() => _showSyllableDots = !_showSyllableDots);
          }
        : widget.onTap;
    if (handleTap == null) return body;
    return InkWell(
      onTap: handleTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: body,
      ),
    );
  }
}

/// Colored syllable / phonics letters under a headword (text color only).
class PhonicsSyllableBlocks extends StatelessWidget {
  const PhonicsSyllableBlocks({
    required this.word,
    this.compact = false,
    this.onSegmentTap,
    this.surfaceBrightness,
    super.key,
  });

  final String word;
  final bool compact;
  final ValueChanged<PhonicsSegment>? onSegmentTap;

  /// When set, letter colors follow this surface (e.g. a light panel in dark app).
  final Brightness? surfaceBrightness;

  @override
  Widget build(BuildContext context) {
    final List<PhonicsSegment> segments = buildPhonicsSegments(word);
    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }
    final List<String> syllables = splitEnglishSyllables(word);
    final double fontSize = compact ? 18 : 22;
    final Color muted = _mutedInk(context, surface: surfaceBrightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          compact ? '自然拼读' : '自然拼读 · 元音红色，音节分色',
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 2,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (int i = 0; i < segments.length; i++) ...<Widget>[
              if (i > 0 &&
                  segments[i].colorIndex != segments[i - 1].colorIndex)
                Text(
                  '·',
                  style: TextStyle(
                    fontSize: fontSize * 0.85,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              _PhonicsLetterSpan(
                segment: segments[i],
                fontSize: fontSize,
                surfaceBrightness: surfaceBrightness,
                onTap: onSegmentTap == null
                    ? null
                    : () => onSegmentTap!(segments[i]),
              ),
            ],
          ],
        ),
        if (!compact && syllables.length > 1) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '音节：${syllables.join(' · ')}',
            style: TextStyle(
              fontSize: 12,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _PhonicsLetterSpan extends StatelessWidget {
  const _PhonicsLetterSpan({
    required this.segment,
    required this.fontSize,
    this.surfaceBrightness,
    this.onTap,
  });

  final PhonicsSegment segment;
  final double fontSize;
  final Brightness? surfaceBrightness;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(
      segment.text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: segment.kind == 'vowel' ? FontWeight.w900 : FontWeight.w700,
        letterSpacing: 0.4,
        height: 1.2,
        color: _segmentTextColor(
          context,
          segment,
          surface: surfaceBrightness,
        ),
      ),
    );
    if (onTap == null) return text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        child: text,
      ),
    );
  }
}

/// Step-by-step natural phonics coach with optional cloud/human audio.
class PhonicsCoachPanel extends StatefulWidget {
  const PhonicsCoachPanel({
    required this.word,
    required this.onSpeak,
    this.speaking = false,
    super.key,
  });

  final String word;
  final Future<void> Function(String text) onSpeak;
  final bool speaking;

  @override
  State<PhonicsCoachPanel> createState() => _PhonicsCoachPanelState();
}

class _PhonicsCoachPanelState extends State<PhonicsCoachPanel> {
  int _step = 0;
  bool _busy = false;

  List<PhonicsGuideStep> get _steps => buildPhonicsGuideSteps(widget.word);

  Future<void> _playCurrent() async {
    if (_busy || widget.speaking) return;
    final List<PhonicsGuideStep> steps = _steps;
    if (steps.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSpeak(steps[_step.clamp(0, steps.length - 1)].text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playAll() async {
    if (_busy || widget.speaking) return;
    final List<PhonicsGuideStep> steps = _steps;
    if (steps.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (int i = 0; i < steps.length; i++) {
        if (!mounted) return;
        setState(() => _step = i);
        await widget.onSpeak(steps[i].text);
        await Future<void>.delayed(const Duration(milliseconds: 280));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<PhonicsGuideStep> steps = _steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final PhonicsGuideStep current = steps[_step.clamp(0, steps.length - 1)];
    // Match panel ink to the panel surface, not a possibly stale global token.
    final Brightness panelBrightness = Theme.of(context).brightness;
    final bool panelDark = panelBrightness == Brightness.dark;
    final Color panelBg =
        panelDark ? const Color(0xFF1C2430) : const Color(0xFFEFF6FF);
    final Color panelInk = _onSurfaceInk(context, surface: panelBrightness);
    final Color panelMuted = _mutedInk(context, surface: panelBrightness);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: panelDark ? const Color(0xFF2A3444) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '自然拼读引导',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: panelInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '按音节拼出来，再连成整词；点字母或步骤可听真人/云端发音。',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: panelMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          PhonicsSyllableBlocks(
            word: widget.word,
            surfaceBrightness: panelBrightness,
            onSegmentTap: (PhonicsSegment seg) {
              if (_busy || widget.speaking) return;
              widget.onSpeak(seg.text);
            },
          ),
          const SizedBox(height: 10),
          Text(
            '步骤 ${_step + 1}/${steps.length} · ${current.labelCn}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: panelInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            current.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: current.isWholeWord ? 26 : 22,
              fontWeight: FontWeight.w900,
              color: current.isWholeWord ? _kVowelRed : panelInk,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: '上一步',
                onPressed: _step <= 0 || _busy
                    ? null
                    : () => setState(() => _step -= 1),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy || widget.speaking ? null : _playCurrent,
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('听这一拍'),
                ),
              ),
              IconButton(
                tooltip: '下一步',
                onPressed: _step >= steps.length - 1 || _busy
                    ? null
                    : () => setState(() => _step += 1),
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _busy || widget.speaking ? null : _playAll,
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('完整拼读一遍'),
          ),
        ],
      ),
    );
  }
}

class RootsAffixesCard extends StatelessWidget {
  const RootsAffixesCard({
    required this.affixes,
    required this.aiText,
    super.key,
  });

  final List<AffixHit> affixes;
  final String aiText;

  @override
  Widget build(BuildContext context) {
    if (affixes.isEmpty && aiText.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppDesignTokens.isDark
            ? const Color(0xFF1E1B2E)
            : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '词根词缀联想',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          if (affixes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final AffixHit hit in affixes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.isDark
                          ? AppDesignTokens.softWhite
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${_kindLabel(hit.kind)} ',
                            style: TextStyle(
                              color: AppDesignTokens.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          TextSpan(
                            text: hit.part,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text: '  ${hit.meaningCn}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                          if (hit.examples.isNotEmpty)
                            TextSpan(
                              text: '\n例：${hit.examples.take(3).join(', ')}',
                              style: TextStyle(
                                color: AppDesignTokens.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (aiText.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              aiText.trim(),
              style: TextStyle(
                height: 1.45,
                color: AppDesignTokens.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _kindLabel(String kind) => switch (kind) {
        'prefix' => '前缀',
        'suffix' => '后缀',
        _ => '词根',
      };
}

class EtymologyCard extends StatelessWidget {
  const EtymologyCard({
    required this.localHint,
    required this.aiText,
    super.key,
  });

  final String localHint;
  final String aiText;

  @override
  Widget build(BuildContext context) {
    final String body = aiText.trim().isNotEmpty ? aiText.trim() : localHint.trim();
    if (body.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppDesignTokens.isDark
            ? const Color(0xFF2A2218)
            : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '单词溯源',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              height: 1.45,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          if (aiText.trim().isEmpty && localHint.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '（本地构词提示；收藏并生成 AI 词卡可获得更完整词源）',
              style: TextStyle(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
