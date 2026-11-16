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
  static const List<({String id, String label})> _allTags =
      <({String id, String label})>[
        (id: 'slow', label: '慢速英语'),
        (id: 'daily', label: '日常对话'),
        (id: 'news', label: '英语新闻'),
        (id: 'ted', label: 'TED 演讲'),
        (id: 'travel', label: '旅行英语'),
        (id: 'business', label: '商务英语'),
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
            '兴趣主题（用于每日 B站推荐）',
            style: TextStyle(
              color: StudyShellTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '只影响首页「每日推荐」，不会自动加入你的学习课程。',
            style: TextStyle(
              color: StudyShellTokens.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _allTags.map((({String id, String label}) tag) {
              final bool selected = _draft.tags.contains(tag.id);
              return FilterChip(
                label: Text(tag.label),
                selected: selected,
                onSelected: (bool value) {
                  final List<String> next = List<String>.from(_draft.tags);
                  if (value) {
                    next.add(tag.id);
                  } else {
                    next.remove(tag.id);
                  }
                  setState(() => _draft = _draft.copyWith(tags: next));
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            '每日推荐 ${_draft.dailyQuota} 条',
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
              '推荐更新提醒',
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
                ).showSnackBar(const SnackBar(content: Text('偏好已保存，每日推荐已刷新')));
                Navigator.of(context).pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: StudyShellTokens.accent,
            ),
            child: const Text('保存并刷新每日推荐'),
          ),
        ],
      ),
    );
  }
}
