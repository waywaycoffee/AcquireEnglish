import 'package:flutter/material.dart';

import '../../domain/word_morphology.dart';

/// Colored syllable / phonics blocks under a headword.
class PhonicsSyllableBlocks extends StatelessWidget {
  const PhonicsSyllableBlocks({
    required this.word,
    this.compact = false,
    super.key,
  });

  final String word;
  final bool compact;

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
          compact ? '自然拼读' : '自然拼读 · 音节色块',
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
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: Color(kPhonicsPalette[seg.colorIndex]),
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
