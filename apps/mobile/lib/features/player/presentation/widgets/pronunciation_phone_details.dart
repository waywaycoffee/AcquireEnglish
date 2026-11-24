import 'package:flutter/material.dart';

import '../../domain/pronunciation_assessment.dart';

class PronunciationPhoneDetails extends StatelessWidget {
  const PronunciationPhoneDetails({required this.result, super.key});

  final PronunciationAssessmentResult result;

  @override
  Widget build(BuildContext context) {
    final words = result.words.where((word) => word.phones.isNotEmpty).toList();
    if (words.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return ExpansionTile(
      title: const Text('逐音素点评'),
      children: [
        for (final word in words)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  word.referenceWord.isNotEmpty
                      ? word.referenceWord
                      : word.word,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final phone in word.phones)
                      Chip(
                        backgroundColor: (phone.accuracy ?? 100) < 60
                            ? colors.errorContainer
                            : colors.surfaceContainerHighest,
                        label: Text(_label(phone)),
                      ),
                    if (_tip(word) case final String tip) Text(tip),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  String? _tip(PronunciationWordResult word) {
    for (final phone in word.phones) {
      if ((phone.accuracy ?? 100) >= 60) continue;
      final expected = phone.referencePhone.toLowerCase().replaceAll('/', '');
      return switch (expected) {
        'dh' || 'ð' => '练习 /ð/ 时，舌尖轻触上齿边缘，送气时让声带振动。',
        'th' || 'θ' => '练习 /θ/ 时，舌尖轻触上齿边缘，让气流轻轻通过。',
        _ => '先重听这个词，慢读一次标出的音素，再跟读整词。',
      };
    }
    return null;
  }

  String _label(PronunciationPhoneResult phone) {
    final expected = phone.referencePhone.isEmpty
        ? phone.phone
        : phone.referencePhone;
    final heard = phone.phone.isNotEmpty && phone.phone != expected
        ? ' · 实际 ${phone.phone}'
        : '';
    final score = phone.accuracy == null
        ? ' · 暂无评分'
        : ' · ${phone.accuracy!.round()} 分';
    return '$expected$heard$score';
  }
}
