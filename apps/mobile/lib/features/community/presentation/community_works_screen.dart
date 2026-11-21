import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/community_models.dart';
import 'community_feed_tab.dart';
import 'community_social_provider.dart';

/// Aggregates the signed-in user's posts by kind (我的作品集).
class CommunityWorksScreen extends ConsumerStatefulWidget {
  const CommunityWorksScreen({super.key});

  @override
  ConsumerState<CommunityWorksScreen> createState() =>
      _CommunityWorksScreenState();
}

class _CommunityWorksScreenState extends ConsumerState<CommunityWorksScreen> {
  List<CommunityPostDto> _posts = const <CommunityPostDto>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> social =
          ref.read(communitySocialProvider).asData?.value ??
              await ref.read(communitySocialProvider.future);
      final int? myId = (social['my_id'] as num?)?.toInt();
      if (myId == null || myId <= 0) {
        throw StateError('无法识别当前用户');
      }
      final List<CommunityPostDto> posts = await ref
          .read(acquireApiClientProvider)
          .communityFeed(authorId: myId, limit: 100);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'imitation':
        return '仿写';
      case 'shadowing':
        return '跟读';
      case 'sentence_make':
        return '造句';
      case 'learning_result':
        return '成果';
      case 'share_bilibili':
        return '素材分享';
      case 'question':
        return '问答';
      case 'method':
        return '方法';
      case 'team_invite':
        return '组队';
      case 'feedback':
        return '反馈';
      default:
        return kind;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<CommunityPostDto>> grouped =
        <String, List<CommunityPostDto>>{};
    for (final CommunityPostDto post in _posts) {
      grouped.putIfAbsent(post.kind, () => <CommunityPostDto>[]).add(post);
    }
    final List<String> order = <String>[
      'imitation',
      'shadowing',
      'sentence_make',
      'learning_result',
      'share_bilibili',
      'question',
      'method',
      'team_invite',
      'feedback',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('我的作品集')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _posts.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: const <Widget>[
                            Text(
                              '还没有公开作品。去「练习」发仿写 / 跟读 / 造句吧。',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          children: <Widget>[
                            Text(
                              '共 ${_posts.length} 条 · 按类型聚合',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppDesignTokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            for (final String kind in <String>[
                              ...order.where(grouped.containsKey),
                              ...grouped.keys.where(
                                (String k) => !order.contains(k),
                              ),
                            ]) ...<Widget>[
                              Text(
                                '${_kindLabel(kind)} · ${grouped[kind]!.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final CommunityPostDto post
                                  in grouped[kind]!) ...<Widget>[
                                CommunityPostCard(post: post),
                                const SizedBox(height: 10),
                              ],
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                ),
    );
  }
}
