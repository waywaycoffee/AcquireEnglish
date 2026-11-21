import 'package:flutter/material.dart';

import '../../domain/word_morphology.dart';

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
            color: vowel ? const Color(0xFF1D4ED8) : const Color(0xFF111827),
            backgroundColor: vowel
                ? const Color(0xFFDBEAFE)
                : Colors.transparent,
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
            onTap == null ? '蓝色高亮 = 元音' : '蓝色高亮 = 元音 · 点单词展开音节 / 拼读',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
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

/// Colored syllable / phonics blocks under a headword.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          compact ? '自然拼读' : '自然拼读 · 音节色块（元音加亮）',
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final PhonicsSegment seg in segments)
              Material(
                color: Color(kPhonicsPalette[seg.colorIndex]),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onSegmentTap == null
                      ? null
                      : () => onSegmentTap!(seg),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 10,
                      vertical: compact ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Text(
                      seg.text,
                      style: TextStyle(
                        fontSize: compact ? 16 : 20,
                        fontWeight: seg.kind == 'vowel'
                            ? FontWeight.w900
                            : FontWeight.w700,
                        letterSpacing: 0.3,
                        color: seg.kind == 'vowel'
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFF111827),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (!compact && syllables.length > 1) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '音节：${syllables.join(' · ')}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '自然拼读引导',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            '按音节拼出来，再连成整词；点色块或步骤可听真人/云端发音。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.grey.shade700,
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            current.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: current.isWholeWord ? 28 : 24,
              fontWeight: FontWeight.w900,
              color: current.isWholeWord
                  ? const Color(0xFF1D4ED8)
                  : const Color(0xFF111827),
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
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '词根词缀联想',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${_kindLabel(hit.kind)} ',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          TextSpan(
                            text: hit.part,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          TextSpan(
                            text: '  ${hit.meaningCn}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (hit.examples.isNotEmpty)
                            TextSpan(
                              text: '\n例：${hit.examples.take(3).join(', ')}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
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
              style: const TextStyle(height: 1.45),
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
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '单词溯源',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.45)),
          if (aiText.trim().isEmpty && localHint.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '（本地构词提示；收藏并生成 AI 词卡可获得更完整词源）',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
