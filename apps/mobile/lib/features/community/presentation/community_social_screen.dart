import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/community_models.dart';
import 'community_feed_tab.dart';
import 'community_social_provider.dart';

class CommunitySocialScreen extends ConsumerStatefulWidget {
  const CommunitySocialScreen({super.key});
  @override
  ConsumerState<CommunitySocialScreen> createState() =>
      _CommunitySocialScreenState();
}

class _CommunitySocialScreenState extends ConsumerState<CommunitySocialScreen> {
  Map<String, dynamic>? _state;
  List<dynamic> _notices = [], _reports = [], _cards = [];
  List<CommunityPostDto> _saved = [], _following = [];
  String? _error;
  bool _busy = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final List<Object> result = await Future.wait<Object>([
        api.socialRequest('GET', ''),
        api.socialRequest('GET', '/notices'),
        api.socialRequest('GET', '/reports'),
        api.communityFeed(bookmarked: true),
        api.communityFeed(following: true),
        api.learningCardRequest('GET', '/mine'),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = result[0] as Map<String, dynamic>;
        _notices =
            (result[1] as Map<String, dynamic>)['notices'] as List<dynamic>;
        _reports =
            (result[2] as Map<String, dynamic>)['reports'] as List<dynamic>;
        _saved = result[3] as List<CommunityPostDto>;
        _following = result[4] as List<CommunityPostDto>;
        _cards = (result[5] as Map<String, dynamic>)['cards'] as List<dynamic>;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() => _error = '加载未完成，请刷新重试。');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_busy) return;
    final String token = ref.read(authSessionProvider).accessToken;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted && token == ref.read(authSessionProvider).accessToken) {
        ref.invalidate(communitySocialProvider);
        await _load();
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作未完成，请重试')));
    } finally {
      if (mounted && token == ref.read(authSessionProvider).accessToken)
        setState(() => _busy = false);
    }
  }

  Future<void> _post(int id) async {
    final int generation = _generation;
    final Map<String, dynamic> data = await ref
        .read(acquireApiClientProvider)
        .socialRequest('GET', '/posts/$id');
    if (!mounted || generation != _generation) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('帖子与讨论')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              CommunityPostCard(post: CommunityPostDto.fromJson(data)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authSessionProvider.select((AuthSessionState s) => s.accessToken),
      (String? old, String next) {
        _generation++;
        setState(() {
          _state = null;
          _busy = false;
          _notices = [];
          _saved = [];
          _following = [];
          _reports = [];
          _cards = [];
        });
        if (next.isNotEmpty) _load();
      },
    );
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('社区消息与管理'),
          actions: <Widget>[
            IconButton(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Tab>[
              Tab(text: '消息'),
              Tab(text: '收藏'),
              Tab(text: '关注'),
              Tab(text: '我的分享'),
              Tab(text: '管理'),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      if (_notices.isEmpty) const Text('暂无互动消息'),
                      for (final dynamic notice in _notices)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              notice['read'] == true
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                            ),
                            title: Text('${notice['text']}'),
                            subtitle: Text('${notice['created_at']}'),
                            onTap: () => _action(() async {
                              await ref
                                  .read(acquireApiClientProvider)
                                  .socialRequest(
                                    'PUT',
                                    '/notices/${notice['id']}/read',
                                  );
                              if (notice['post_id'] != null)
                                await _post(notice['post_id'] as int);
                            }),
                          ),
                        ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      if (_saved.isEmpty) const Text('暂无收藏帖子'),
                      for (final CommunityPostDto post in _saved)
                        CommunityPostCard(post: post),
                      const Text('显示最近40条，更多内容可在社区中查看。'),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      if (_following.isEmpty) const Text('关注作者后，这里会显示他们的最新帖子'),
                      for (final CommunityPostDto post in _following)
                        CommunityPostCard(post: post),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      const Text('公开学习卡可随时撤回，撤回后旧链接不可访问。'),
                      for (final dynamic card in _cards)
                        ListTile(
                          title: Text('${card['expression']}'),
                          subtitle: Text(
                            card['active'] == true ? '公开中' : '已撤回',
                          ),
                          trailing: card['active'] == true
                              ? TextButton(
                                  onPressed: () => _action(() async {
                                    await ref
                                        .read(acquireApiClientProvider)
                                        .learningCardRequest(
                                          'DELETE',
                                          '/${card['token']}',
                                        );
                                  }),
                                  child: const Text('撤回'),
                                )
                              : null,
                        ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      SwitchListTile(
                        title: const Text('接收新的社区互动通知'),
                        subtitle: const Text('关闭后不再接收鼓励、关注和回复等新通知；已有消息保留。'),
                        value: _state?['notifications_enabled'] != false,
                        onChanged: _busy
                            ? null
                            : (bool enabled) => _action(() async {
                                await ref
                                    .read(acquireApiClientProvider)
                                    .socialRequest(
                                      'PUT',
                                      '/notifications',
                                      data: <String, dynamic>{
                                        'enabled': enabled,
                                      },
                                    );
                              }),
                      ),
                      const Text('我的屏蔽名单', style: TextStyle(fontSize: 20)),
                      for (final dynamic id
                          in _state?['blocks'] as List<dynamic>? ?? [])
                        ListTile(
                          title: Text('用户编号 $id'),
                          trailing: TextButton(
                            onPressed: () => _action(() async {
                              await ref
                                  .read(acquireApiClientProvider)
                                  .socialRequest('DELETE', '/blocks/$id');
                            }),
                            child: const Text('解除屏蔽'),
                          ),
                        ),
                      const Text('我的举报与处理结果', style: TextStyle(fontSize: 20)),
                      for (final dynamic report in _reports)
                        ListTile(
                          title: Text(
                            '举报 #${report['id']} · 帖子 ${report['post_id']}',
                          ),
                          subtitle: Text(
                            '${report['status'] == 'pending'
                                ? '待审核'
                                : report['status'] == 'hide'
                                ? '已下架'
                                : '已处理'} ${report['review_note']}',
                          ),
                        ),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const _ModerationScreen(),
                          ),
                        ),
                        child: const Text('管理员审核（需要凭据）'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModerationScreen extends ConsumerStatefulWidget {
  const _ModerationScreen();
  @override
  ConsumerState<_ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends ConsumerState<_ModerationScreen> {
  final TextEditingController _token = TextEditingController();
  final TextEditingController _note = TextEditingController();
  List<dynamic> _reports = [];
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _token.clear();
    _token.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data = await ref
          .read(acquireApiClientProvider)
          .moderationRequest('GET', '', _token.text);
      if (mounted) setState(() => _reports = data['reports'] as List<dynamic>);
    } catch (_) {
      if (mounted) setState(() => _error = '凭据无效或服务暂不可用。凭据不在本机持久化。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(int id, String action) async {
    if (_note.text.trim().length < 2) {
      setState(() => _error = '请填写处理理由（至少2字）');
      return;
    }
    try {
      await ref
          .read(acquireApiClientProvider)
          .moderationRequest(
            'POST',
            '/$id',
            _token.text,
            data: <String, dynamic>{
              'action': action,
              'note': _note.text.trim(),
            },
          );
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '处理未完成，请刷新后重试。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('社区审核')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const Text('仅授权管理员使用。凭据只在本页面内存中使用，退出即清除。'),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: '管理员凭据'),
        ),
        FilledButton(
          onPressed: _busy ? null : _load,
          child: const Text('加载待审核举报'),
        ),
        if (_error != null) Text(_error!),
        TextField(
          controller: _note,
          maxLength: 500,
          decoration: const InputDecoration(labelText: '处理理由（将向举报者展示）'),
        ),
        for (final dynamic report in _reports)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('举报 #${report['id']} · 帖子 ${report['post_id']}'),
                  Text('${report['reason']}'),
                  Wrap(
                    children: <Widget>[
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _review(report['id'] as int, 'hide'),
                        child: const Text('确认下架'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _review(report['id'] as int, 'dismiss'),
                        child: const Text('不予下架并说明理由'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
