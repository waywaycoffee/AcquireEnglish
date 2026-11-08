import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';

class LearningPreferencesScreen extends ConsumerStatefulWidget {
  const LearningPreferencesScreen({super.key});

  @override
  ConsumerState<LearningPreferencesScreen> createState() =>
      _LearningPreferencesScreenState();
}

class _LearningPreferencesScreenState
    extends ConsumerState<LearningPreferencesScreen> {
  static const List<String> _levels = <String>['A1', 'A2', 'B1', 'B2', 'C1'];
  static const List<String> _allTags = <String>[
    'slow',
    'daily',
    'news',
    'ted',
    'travel',
    'business',
  ];

  late AcquirePreferencesDto _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(learningPreferencesProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudyShellTokens.background,
      appBar: AppBar(
        backgroundColor: StudyShellTokens.background,
        foregroundColor: StudyShellTokens.textPrimary,
        title: const Text('学习偏好'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            '级别',
            style: TextStyle(
              color: StudyShellTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _levels.map((String level) {
              final bool selected = _draft.level == level;
              return ChoiceChip(
                label: Text(level),
                selected: selected,
                onSelected: (_) => setState(() {
                  _draft = _draft.copyWith(level: level);
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            '主题标签',
            style: TextStyle(
              color: StudyShellTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _allTags.map((String tag) {
              final bool selected = _draft.tags.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: selected,
                onSelected: (bool value) {
                  final List<String> next = List<String>.from(_draft.tags);
                  if (value) {
                    next.add(tag);
                  } else {
                    next.remove(tag);
                  }
                  setState(() => _draft = _draft.copyWith(tags: next));
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            '每日推荐 ${_draft.dailyQuota} 课',
            style: const TextStyle(
              color: StudyShellTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Slider(
            value: _draft.dailyQuota.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '${_draft.dailyQuota}',
            onChanged: (double value) {
              setState(
                () => _draft = _draft.copyWith(dailyQuota: value.round()),
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '每日课程推送',
              style: TextStyle(color: StudyShellTokens.textPrimary),
            ),
            value: _draft.notifyDailyFeed,
            onChanged: (bool value) {
              setState(
                () => _draft = _draft.copyWith(notifyDailyFeed: value),
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await ref.read(learningPreferencesProvider.notifier).save(_draft);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('偏好已保存，今日课程已刷新')));
                Navigator.of(context).pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: StudyShellTokens.accent,
            ),
            child: const Text('保存并刷新今日课程'),
          ),
        ],
      ),
    );
  }
}
