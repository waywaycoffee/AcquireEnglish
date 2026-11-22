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
  /// Default to K12 / 中高考 — product priority alongside CET.
  ExamTrack? _track = ExamTrack.k12;
  String? _familyId;
  String? _ieltsBand;

  @override
  Widget build(BuildContext context) {
    final List<ExamFamily> families = _track == null
        ? const <ExamFamily>[]
        : examFamiliesForTrack(_track!);

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
          if (_track == ExamTrack.k12) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              '中考 / 高考',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '备考助手优先入口；年级目标会映射到对应阶段题包。',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String id in kK12EntranceExamIds)
                  if (examFamilyById(id) != null)
                    ChoiceChip(
                      label: Text(examFamilyById(id)!.label),
                      selected: _familyId == id,
                      onSelected: (_) => setState(() => _familyId = id),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            _K12Section(
              title: '小学',
              families: k12FamiliesPrimary(),
              selectedId: _familyId,
              onSelect: (String id) => setState(() => _familyId = id),
            ),
            _K12Section(
              title: '初中',
              families: k12FamiliesJunior()
                  .where((ExamFamily f) => f.id != 'zhongkao')
                  .toList(growable: false),
              selectedId: _familyId,
              onSelect: (String id) => setState(() => _familyId = id),
            ),
            _K12Section(
              title: '高中',
              families: k12FamiliesSenior()
                  .where((ExamFamily f) => f.id != 'gaokao')
                  .toList(growable: false),
              selectedId: _familyId,
              onSelect: (String id) => setState(() => _familyId = id),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                '扩展资料包',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('知识点图谱 / 研究阅读集'),
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final ExamFamily f in k12FamiliesResearch())
                        ChoiceChip(
                          label: Text(f.label),
                          selected: _familyId == f.id,
                          onSelected: (_) =>
                              setState(() => _familyId = f.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ] else if (families.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              '具体考试',
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
            child: const Text('保存考试目标'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              await ref.read(examProfileProvider.notifier).clearExamTarget();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清除考试目标')),
                );
                context.go('/home');
              }
            },
            child: const Text('清除考试目标'),
          ),
        ],
      ),
    );
  }
}

class _K12Section extends StatelessWidget {
  const _K12Section({
    required this.title,
    required this.families,
    required this.selectedId,
    required this.onSelect,
  });

  final String title;
  final List<ExamFamily> families;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (families.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
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
                  selected: selectedId == f.id,
                  onSelected: (_) => onSelect(f.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
