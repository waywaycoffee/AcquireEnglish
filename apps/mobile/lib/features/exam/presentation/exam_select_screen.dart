import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/exam_registry.dart';
import 'exam_profile_provider.dart';

const Color _kExamHeroDark = Color(0xFF1A2332);

class ExamSelectScreen extends ConsumerStatefulWidget {
  const ExamSelectScreen({
    super.key,
    this.initialTrack,
    this.initialFamilyId,
  });

  final ExamTrack? initialTrack;
  final String? initialFamilyId;

  @override
  ConsumerState<ExamSelectScreen> createState() => _ExamSelectScreenState();
}

class _ExamSelectScreenState extends ConsumerState<ExamSelectScreen> {
  late ExamTrack? _track = widget.initialTrack ?? ExamTrack.k12;
  late String? _familyId = widget.initialFamilyId;
  String? _ieltsBand;

  @override
  Widget build(BuildContext context) {
    final List<ExamFamily> families = _track == null
        ? const <ExamFamily>[]
        : examFamiliesForTrack(_track!);

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        title: const Text('选择考试目标'),
        backgroundColor: AppDesignTokens.softWhite,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          Text(
            '考试轨',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ExamTrack track in ExamTrack.values)
                _TrackChip(
                  label: examTrackLabel(track),
                  selected: _track == track,
                  onTap: () => setState(() {
                    _track = track;
                    _familyId = null;
                    _ieltsBand = null;
                  }),
                ),
            ],
          ),
          if (_track == ExamTrack.k12) ...<Widget>[
            const SizedBox(height: 22),
            const Text(
              '中考 / 高考',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _EntranceCard(
                    title: '中考',
                    subtitle: '按地区卷',
                    selected: _familyId == 'zhongkao',
                    dark: false,
                    onTap: () => setState(() => _familyId = 'zhongkao'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EntranceCard(
                    title: '高考',
                    subtitle: '估分 / 档次',
                    selected: _familyId == 'gaokao',
                    dark: true,
                    onTap: () => setState(() => _familyId = 'gaokao'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 22),
            Text(
              '具体考试',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
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
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppDesignTokens.softGray,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _familyId == null
                  ? null
                  : () async {
                      await ref.read(examProfileProvider.notifier).setFamily(
                            _familyId!,
                            targetScore: _ieltsBand,
                          );
                      if (context.mounted) {
                        context.go('/exam');
                      }
                    },
              child: const Text(
                '保存考试目标',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
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

class _TrackChip extends StatelessWidget {
  const _TrackChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppDesignTokens.brandGreen : AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : AppDesignTokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _EntranceCard extends StatelessWidget {
  const _EntranceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool emphasize = dark || selected;
    return Material(
      color: emphasize ? _kExamHeroDark : AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 88,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: selected && !emphasize
                ? Border.all(color: AppDesignTokens.brandGreen, width: 2)
                : selected
                    ? Border.all(color: AppDesignTokens.brandGreen, width: 2)
                    : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                selected ? '$title ✓' : title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: emphasize ? Colors.white : AppDesignTokens.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: emphasize
                      ? const Color(0xFFB8BECB)
                      : AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.only(bottom: 14),
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
                Material(
                  color: selectedId == f.id
                      ? AppDesignTokens.brandGreen
                      : AppDesignTokens.appWhite,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(f.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        f.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selectedId == f.id
                              ? Colors.white
                              : AppDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
