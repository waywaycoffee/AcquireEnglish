import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../domain/word_morphology.dart';

/// Vowels are always red; consonants/syllable groups use distinct text colors.
const Color _kVowelRed = Color(0xFFE11D48);

/// Light-theme text colors for non-vowel segments (cycled by syllable).
const List<Color> _kPhonicsTextLight = <Color>[
  Color(0xFF111827),
  Color(0xFF1D4ED8),
  Color(0xFF047857),
  Color(0xFFB45309),
  Color(0xFF7C3AED),
  Color(0xFFBE185D),
];

/// Dark-theme text colors for non-vowel segments (cycled by syllable).
const List<Color> _kPhonicsTextDark = <Color>[
  Color(0xFFE5E7EB),
  Color(0xFF93C5FD),
  Color(0xFF86EFAC),
  Color(0xFFFCD34D),
  Color(0xFFC4B5FD),
  Color(0xFFF9A8D4),
];

Color _segmentTextColor(PhonicsSegment seg) {
  if (seg.kind == 'vowel') {
    return _kVowelRed;
  }
  final List<Color> palette =
      AppDesignTokens.isDark ? _kPhonicsTextDark : _kPhonicsTextLight;
  return palette[seg.colorIndex % palette.length];
}

/// Headword with vowel letters tinted for natural-phonics awareness.
class ColoredVowelHeadword extends StatelessWidget {
  const ColoredVowelHeadword({
    required this.word,
    this.fontSize = 34,
    this.textAlign = TextAlign.center,
    this.showLegend = false,
    this.onTap,
    super.key,
  });

  final String word;
  final double fontSize;
  final TextAlign textAlign;
  final bool showLegend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String raw = word.trim();
    if (raw.isEmpty) return const SizedBox.shrink();
    final Color consonant = AppDesignTokens.textPrimary;
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
            fontSize: fontSize,
            height: 1.2,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            color: vowel ? _kVowelRed : consonant,
          ),
        ),
      );
    }
    final Widget rich = Text.rich(
      TextSpan(children: spans),
      textAlign: textAlign,
    );
    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.start
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: <Widget>[
        rich,
        if (showLegend) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            onTap == null ? '红色 = 元音' : '红色 = 元音 · 点单词展开音节 / 拼读',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ],
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
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
    super.key,
  });

  final String word;
  final bool compact;
  final ValueChanged<PhonicsSegment>? onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final List<PhonicsSegment> segments = buildPhonicsSegments(word);
    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }
    final List<String> syllables = splitEnglishSyllables(word);
    final double fontSize = compact ? 18 : 22;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          compact ? '自然拼读' : '自然拼读 · 元音红色，音节分色',
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w800,
            color: AppDesignTokens.textSecondary,
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
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              _PhonicsLetterSpan(
                segment: segments[i],
                fontSize: fontSize,
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
              color: AppDesignTokens.textSecondary,
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
    this.onTap,
  });

  final PhonicsSegment segment;
  final double fontSize;
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
        color: _segmentTextColor(segment),
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
    final bool dark = AppDesignTokens.isDark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C2430) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? const Color(0xFF2A3444) : const Color(0xFFBFDBFE),
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
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '按音节拼出来，再连成整词；点字母或步骤可听真人/云端发音。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppDesignTokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          PhonicsSyllableBlocks(
            word: widget.word,
            onSegmentTap: (PhonicsSegment seg) {
              if (_busy || widget.speaking) return;
              widget.onSpeak(seg.text);
            },
          ),
          const SizedBox(height: 12),
          Text(
            '步骤 ${_step + 1}/${steps.length} · ${current.labelCn}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            current.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: current.isWholeWord ? 28 : 24,
              fontWeight: FontWeight.w900,
              color: current.isWholeWord
                  ? _kVowelRed
                  : AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 6),
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
