import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import 'adventure_ui.dart';
import 'community_people_tab.dart';
import 'study_desk_screen.dart';

/// Formal study groups + desk + language-exchange entry.
class CommunityGroupsTab extends ConsumerStatefulWidget {
  const CommunityGroupsTab({super.key});

  @override
  ConsumerState<CommunityGroupsTab> createState() => _CommunityGroupsTabState();
}

class _CommunityGroupsTabState extends ConsumerState<CommunityGroupsTab> {
  List<Map<String, dynamic>> _groups = const <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_load());
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<Map<String, dynamic>> groups =
          await ref.read(acquireApiClientProvider).listCommunityGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createGroup() async {
    final TextEditingController title = TextEditingController();
    final TextEditingController topic = TextEditingController(text: 'daily');
    final TextEditingController cefr = TextEditingController(text: 'B1');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('创建学习小组'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: '小组名称'),
            ),
            TextField(
              controller: topic,
              decoration: const InputDecoration(labelText: '题材'),
            ),
            TextField(
              controller: cefr,
              decoration: const InputDecoration(labelText: 'CEFR'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (title.text.trim().isEmpty) return;
    try {
      await ref.read(acquireApiClientProvider).createCommunityGroup(
        <String, dynamic>{
          'title': title.text.trim(),
          'topic': topic.text.trim(),
          'cefr': cefr.text.trim(),
          'visibility': 'public',
        },
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('小组已创建')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：$e')),
      );
    }
  }

  Future<void> _openGroup(Map<String, dynamic> group) async {
    final int groupId = (group['id'] as num?)?.toInt() ?? 0;
    if (groupId <= 0) return;
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    List<Map<String, dynamic>> tasks = const <Map<String, dynamic>>[];
    try {
      if (group['joined'] != true &&
          ref.read(authSessionProvider).isLoggedIn) {
        await api.joinCommunityGroup(groupId);
      }
      tasks = await api.listCommunityGroupTasks(groupId);
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                (group['title'] as String?) ?? '学习小组',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '成员 ${group['member_count'] ?? 1} · '
                '${(group['cefr'] as String?) ?? ''} '
                '${(group['topic'] as String?) ?? ''}',
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                const Text('本周还没有任务；组长可发布共同素材任务。')
              else
                for (final Map<String, dynamic> task in tasks.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text((task['title'] as String?) ?? '任务'),
                    subtitle: Text(
                      '${task['week_id'] ?? ''} · ${task['task_type'] ?? ''}',
                    ),
                  ),
              if (ref.read(authSessionProvider).isLoggedIn)
                FilledButton.tonal(
                  onPressed: () async {
                    final TextEditingController taskTitle =
                        TextEditingController(text: '本周共同跟读');
                    final bool? ok = await showDialog<bool>(
                      context: ctx,
                      builder: (BuildContext dialogCtx) => AlertDialog(
                        title: const Text('发布本周任务'),
                        content: TextField(
                          controller: taskTitle,
                          decoration: const InputDecoration(labelText: '任务标题'),
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(dialogCtx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogCtx, true),
                            child: const Text('发布'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    try {
                      await api.createCommunityGroupTask(
                        groupId,
                        <String, dynamic>{
                          'title': taskTitle.text.trim(),
                          'task_type': 'shadowing',
                        },
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _load();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('发布失败：$e')),
                      );
                    }
                  },
                  child: const Text('发布本周任务'),
                ),
            ],
          ),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          const Text(
            '学习小组',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            '共同素材、轻量周任务、同桌互评；语言交换入口在下方。',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          if (loggedIn)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () => unawaited(_createGroup()),
                child: const Text('创建小组'),
              ),
            ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_groups.isEmpty)
            QuestFeedCard(
              title: '还没有公开小组',
              meta: '创建后可发布本周共同跟读 / 仿写任务',
              badge: '小组',
              accent: AppDesignTokens.brandGreen,
              onPlay: loggedIn ? () => unawaited(_createGroup()) : () {},
            )
          else
            for (final Map<String, dynamic> group in _groups) ...<Widget>[
              QuestFeedCard(
                title: (group['title'] as String?)?.trim().isNotEmpty == true
                    ? group['title'] as String
                    : '未命名小组',
                meta: <String>[
                  if ((group['cefr'] as String?)?.isNotEmpty == true)
                    group['cefr'] as String,
                  if ((group['topic'] as String?)?.isNotEmpty == true)
                    group['topic'] as String,
                  '成员 ${group['member_count'] ?? 1}',
                  if (group['joined'] == true) '已加入',
                ].join(' · '),
                badge: '小组',
                accent: AppDesignTokens.brandGreen,
                showPlayChevron: false,
                onPlay: () => unawaited(_openGroup(group)),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 8),
          QuestFeedCard(
            title: '本周同桌 · 学习桌',
            meta: '1:1 一起练；换人不丢自己的进度',
            badge: '同桌',
            accent: AppDesignTokens.brandGreen,
            showPlayChevron: false,
            onPlay: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const StudyDeskScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          QuestFeedCard(
            title: '语言交换 / 真人对练',
            meta: '互补母语匹配，或普通口语搭子',
            badge: '语伴',
            accent: const Color(0xFF5B8DEF),
            showPlayChevron: false,
            onPlay: () => context.push('/peer-oral'),
          ),
          const SizedBox(height: 12),
          QuestFeedCard(
            title: '找语伴 / 相似同学',
            meta: '按水平与兴趣匹配；支持拉黑举报',
            badge: '发现',
            accent: const Color(0xFF4A5568),
            showPlayChevron: false,
            onPlay: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('找语伴')),
                  body: const CommunityPeopleTab(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          QuestFeedCard(
            title: '考试备考',
            meta: '按考试族组队刷词、听力与模考',
            badge: '备考',
            accent: const Color(0xFF8E5AA8),
            onPlay: () => context.push('/exam'),
          ),
        ],
      ),
    );
  }
}
