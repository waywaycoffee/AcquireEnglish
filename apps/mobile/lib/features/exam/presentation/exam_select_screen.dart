import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/exam_registry.dart';
import 'exam_profile_provider.dart';

class ExamSelectScreen extends ConsumerStatefulWidget {
  const ExamSelectScreen({super.key});

  @override
  ConsumerState<ExamSelectScreen> createState() => _ExamSelectScreenState();
}

class _ExamSelectScreenState extends ConsumerState<ExamSelectScreen> {
  ExamTrack? _track;
  String? _familyId;
  String? _ieltsBand;

  @override
  Widget build(BuildContext context) {
    final List<ExamFamily> families = _track == null
        ? const <ExamFamily>[]
        : kExamFamilies
              .where((ExamFamily f) => f.track == _track)
              .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('选择考试目标')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            '考试轨',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ExamTrack track in ExamTrack.values)
                ChoiceChip(
                  label: Text(examTrackLabel(track)),
                  selected: _track == track,
                  onSelected: (_) => setState(() {
                    _track = track;
                    _familyId = null;
                    _ieltsBand = null;
                  }),
                ),
            ],
          ),
          if (families.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              '具体考试 / 年级',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final ExamFamily f in families)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _familyId == f.id,
                    onSelected: (_) => setState(() => _familyId = f.id),
                  ),
              ],
            ),
          ],
          if (_familyId == 'ielts_ac' || _familyId == 'ielts_gt') ...<Widget>[
            const SizedBox(height: 20),
            Text(
              '目标分数',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String band in kIeltsTargetBands)
                  ChoiceChip(
                    label: Text(band),
                    selected: _ieltsBand == band,
                    onSelected: (_) => setState(() => _ieltsBand = band),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _familyId == null
                ? null
                : () async {
                    await ref
                        .read(examProfileProvider.notifier)
                        .setFamily(
                          _familyId!,
                          targetScore: _ieltsBand,
                        );
                    if (context.mounted) {
                      context.go('/exam');
                    }
                  },
            child: const Text('进入备考模式'),
          ),
        ],
      ),
    );
  }
}
