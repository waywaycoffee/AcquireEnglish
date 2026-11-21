import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../avatar/presentation/avatar_preview.dart';
import '../../avatar/presentation/avatar_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../words/presentation/word_book_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'adventure_ui.dart';
import 'study_pk_screen.dart';
import 'study_play_screen.dart';

class StudyDeskScreen extends ConsumerStatefulWidget {
  const StudyDeskScreen({super.key});

  @override
  ConsumerState<StudyDeskScreen> createState() => _StudyDeskScreenState();
}

class _StudyDeskScreenState extends ConsumerState<StudyDeskScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _desk;
  Map<String, dynamic>? _activity;
  Map<String, dynamic>? _library;
  String? _error;
  String? _libraryError;
  String _category = 'common';
  int _days = 7;
  int _generation = 0;
  bool _busy = false;
  bool _inviteExpanded = false;
  final TextEditingController _invite = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final GlobalKey _inviteSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _invite.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) unawaited(_load());
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) => ref
      .read(acquireApiClientProvider)
      .studyDeskRequest(method, path, data: data, query: query);

  String _message(Object error) {
    if (error is DioException && error.response?.data is Map) {
      final Object? detail =
          (error.response!.data as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
    }
    return '暂时无法连接同桌服务，请检查网络后重试。';
  }

  Future<void> _load() async {
    final int version = ++_generation;
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    final String token = ref.read(authSessionProvider).accessToken;
    setState(() {
      _busy = true;
      _error = null;
      _activity = null;
      _library = null;
      _libraryError = null;
    });
    try {
      final Map<String, dynamic> desk = await _request('GET', '');
      Map<String, dynamic>? activity;
      Map<String, dynamic>? library;
      String? libraryError;
      if (desk['peer'] != null) {
        activity = await _request(
          'GET',
          '/activity',
          query: <String, dynamic>{'days': _days},
        );
        try {
          library = await _request(
            'GET',
            '/library',
            query: <String, dynamic>{
              'category': _category,
              'q': _search.text.trim(),
            },
          );
        } catch (error) {
          libraryError = _message(error);
        }
      }
      if (!mounted ||
          version != _generation ||
          token != ref.read(authSessionProvider).accessToken)
        return;
      setState(() {
        _desk = desk;
        _activity = activity;
        _library = library;
        _libraryError = libraryError;
      });
    } catch (error) {
      if (mounted && version == _generation)
        setState(() {
          _desk = null;
          _error = _message(error);
        });
    } finally {
      if (mounted && version == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _loadMoreLibrary() async {
    if (_busy || _library == null) return;
    final int version = _generation;
    final String token = ref.read(authSessionProvider).accessToken;
    final List<dynamic> existing = List<dynamic>.of(
      _library!['words'] as List<dynamic>,
    );
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> next = await _request(
        'GET',
        '/library',
        query: {
          'category': _category,
          'q': _search.text.trim(),
          'offset': existing.length,
        },
      );
      if (!mounted ||
          version != _generation ||
          token != ref.read(authSessionProvider).accessToken)
        return;
      setState(
        () => _library = {
          ...next,
          'words': [...existing, ...(next['words'] as List<dynamic>)],
        },
      );
    } catch (error) {
      if (mounted && version == _generation)
        setState(() => _libraryError = _message(error));
    } finally {
      if (mounted && version == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
    } finally {
      if (mounted) await _load();
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _syncLibrary() async {
    final List<String> words = ref
        .read(wordBookProvider)
        .where((WordEntry w) => w.favorite && w.kind == VocabCardKind.word)
        .map((WordEntry w) => w.word)
        .toList();
    if (!await _confirm(
          '同步我的收藏',
          '将当前 ${words.length} 个收藏单词同步到同桌图书馆，替换旧快照。不含原句、录音或私有视频；仅在你开启收藏共享后同桌才能查看。',
        ) ||
        !mounted)
      return;
    await _action(() async {
      await _request(
        'PUT',
        '/library',
        data: <String, dynamic>{'words': words},
      );
    });
  }

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    ref.listen(
      authSessionProvider.select((AuthSessionState s) => s.accessToken),
      (String? old, String next) {
        _generation++;
        setState(() {
          _desk = null;
          _activity = null;
          _library = null;
          _busy = false;
        });
        if (next.isNotEmpty) unawaited(_load());
      },
    );
    final Map<String, dynamic>? peer = _desk?['peer'] as Map<String, dynamic>?;
    final Map<String, dynamic> sharing =
        (_desk?['sharing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return Scaffold(
      backgroundColor: const Color(0xFFF7F1E8),
      appBar: AppBar(
        backgroundColor: AdventurePalette.cafeWarm,
        foregroundColor: Colors.white,
        title: const Text('学习桌'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新同桌与共享状态',
          ),
        ],
      ),
      body: !loggedIn
          ? const Center(child: Text('请先登录，再建立同桌关系。'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  AdventureHeroBanner(
                    edgeToEdge: true,
                    chapterTitle: '学习桌',
                    chapterIndex: 1,
                    stageLabel: peer == null
                        ? '邀请同桌，一起练词与备考'
                        : '本周搭子 · ${peer['name']}',
                    progressLabel: peer == null ? '尚未配对' : '同桌学习中',
                    nodeCount: 1,
                    clearedCount: peer == null ? 0 : 1,
                    ctaLabel: '打开考试备考',
                    onContinue: () => context.push('/exam'),
                    partnerLabel: peer == null
                        ? '暂无同桌'
                        : '同桌 · ${peer['name']}',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_error != null)
                          _card('连接失败', <Widget>[
                            Text(_error!),
                            TextButton(
                              onPressed: _busy ? null : _load,
                              child: const Text('重试'),
                            ),
                          ]),
                        _WeeklyQuestCard(
                          hasPeer: peer != null,
                          onEncourage: peer == null || _busy
                              ? null
                              : () => unawaited(_action(() async {
                                    await _request('POST', '/encourage');
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '已发送一次本周提醒（每天最多一次）',
                                          ),
                                        ),
                                      );
                                    }
                                  })),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: DeskActionTile(
                                label: '词汇PK',
                                icon: Icons.sports_esports_rounded,
                                color: AppDesignTokens.brandGreen,
                                onTap: _busy
                                    ? null
                                    : () => Navigator.of(context).push<void>(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const StudyPkScreen(),
                                          ),
                                        ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DeskActionTile(
                                label: '每日打卡',
                                icon: Icons.local_fire_department_rounded,
                                color: AdventurePalette.pathAmber,
                                onTap: _busy
                                    ? null
                                    : () => Navigator.of(context).push<void>(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const StudyPlayScreen(),
                                          ),
                                        ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DeskActionTile(
                                label: peer == null ? '邀请同桌' : '同桌管理',
                                icon: Icons.groups_2_rounded,
                                color: const Color(0xFF5B8DEF),
                                onTap: () {
                                  setState(() => _inviteExpanded = true);
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    final BuildContext? target =
                                        _inviteSectionKey.currentContext;
                                    if (target != null) {
                                      Scrollable.ensureVisible(
                                        target,
                                        duration: const Duration(
                                          milliseconds: 280,
                                        ),
                                        alignment: 0.05,
                                      );
                                    }
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        if (peer != null) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(
                            '同桌在线一起练 · 换人不丢个人进度',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (_desk != null)
                          ExpansionTile(
                            key: ValueKey<String>(
                              'invite-${_inviteExpanded || peer == null}',
                            ),
                            initiallyExpanded: true,
                            onExpansionChanged: (bool open) {
                              setState(() => _inviteExpanded = open);
                            },
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              peer == null
                                  ? '邀请同桌（可选加分）'
                                  : '同桌与共享设置',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            children: <Widget>[
                              KeyedSubtree(
                                key: _inviteSectionKey,
                                child: const SizedBox.shrink(),
                              ),
                              _card(
                                peer == null
                                    ? '邀请同桌 · 双方确认后建立'
                                    : '本周搭子 · ${peer['name']}',
                                <Widget>[
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: <Widget>[
                                      AvatarPreview(
                                        loadout: ref
                                                .watch(avatarMeProvider)
                                                .asData
                                                ?.value
                                                .loadout ??
                                            <String, String>{
                                              'body': 'body.cartoon1',
                                            },
                                        height: 110,
                                      ),
                                      if (peer != null)
                                        AvatarPreview(
                                          loadout: (peer['avatar']
                                                      as Map<String, dynamic>? ??
                                                  <String, dynamic>{})
                                              .cast<String, String>(),
                                          height: 110,
                                        ),
                                    ],
                                  ),
                                  SelectableText('我的同桌编号：${_desk!['my_id']}'),
                                  const Text(
                                    '每人一位正式同桌，双方确认后建立。邀请有效期24小时。',
                                  ),
                                  if (peer == null) ...<Widget>[
                                    TextField(
                                      controller: _invite,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '输入朋友的同桌编号',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () {
                                              final int? id = int.tryParse(
                                                _invite.text.trim(),
                                              );
                                              if (id == null || id <= 0) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      '请输入有效的同桌编号',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              _action(() async {
                                                await _request(
                                                  'POST',
                                                  '/invites',
                                                  data: <String, dynamic>{
                                                    'target_id': id,
                                                  },
                                                );
                                              });
                                            },
                                      child: const Text('发送邀请'),
                                    ),
                                  ],
                                  for (final dynamic invitation
                                      in (_desk!['invites'] as List<dynamic>))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            '${invitation['name']} · ${invitation['incoming'] == true ? '邀请你一起练' : '等待对方确认'}',
                                          ),
                                          Wrap(
                                            children: <Widget>[
                                              if (invitation['incoming'] ==
                                                  true)
                                                TextButton(
                                                  onPressed: _busy
                                                      ? null
                                                      : () async {
                                                          if (!await _confirm(
                                                                '接受同桌邀请',
                                                                '与 ${invitation['name']} 建立正式同桌关系。',
                                                              ) ||
                                                              !mounted) {
                                                            return;
                                                          }
                                                          await _action(
                                                            () async {
                                                              await _request(
                                                                'POST',
                                                                '/invites/${invitation['id']}/accept',
                                                              );
                                                            },
                                                          );
                                                        },
                                                  child: const Text('接受'),
                                                ),
                                              TextButton(
                                                onPressed: _busy
                                                    ? null
                                                    : () => _action(() async {
                                                          await _request(
                                                            'POST',
                                                            '/invites/${invitation['id']}/${invitation['incoming'] == true ? 'decline' : 'cancel'}',
                                                          );
                                                        }),
                                                child: Text(
                                                  invitation['incoming'] == true
                                                      ? '婉拒'
                                                      : '撤回',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              if (peer != null) ...<Widget>[
                                _card('由我决定共享什么', <Widget>[
                                  for (final (String key, String title)
                                      in <(String, String)>[
                                        ('activity', '共享按天学习时长'),
                                        ('videos', '共享近期公开视频学习记录'),
                                        ('library', '共享收藏单词（不含私有原句）'),
                                      ])
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(title),
                                      value: sharing[key] == true,
                                      onChanged: _busy
                                          ? null
                                          : (bool value) => _action(() async {
                                                await _request(
                                                  'PUT',
                                                  '/sharing',
                                                  data: <String, dynamic>{
                                                    'share_activity':
                                                        key == 'activity'
                                                            ? value
                                                            : sharing[
                                                                    'activity'] ==
                                                                true,
                                                    'share_videos':
                                                        key == 'videos'
                                                            ? value
                                                            : sharing[
                                                                    'videos'] ==
                                                                true,
                                                    'share_library':
                                                        key == 'library'
                                                            ? value
                                                            : sharing[
                                                                    'library'] ==
                                                                true,
                                                  },
                                                );
                                              }),
                                    ),
                                ]),
                                _activityCard(),
                                _libraryCard(),
                                _card('关系管理', <Widget>[
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            if (!await _confirm(
                                                  '解除同桌关系',
                                                  '双方立即停止访问同桌共享数据。',
                                                ) ||
                                                !mounted) {
                                              return;
                                            }
                                            await _action(() async {
                                              await _request('DELETE', '');
                                            });
                                          },
                                    child: const Text('解除同桌关系'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            if (!await _confirm(
                                                  '屏蔽并解除关系',
                                                  '解除后双方无法再次互相邀请。',
                                                ) ||
                                                !mounted) {
                                              return;
                                            }
                                            await _action(() async {
                                              await _request('POST', '/block');
                                            });
                                          },
                                    child: const Text('屏蔽并解除'),
                                  ),
                                ]),
                              ],
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

  Widget _activityCard() {
    final Map<String, dynamic>? summary =
        _activity?['summary'] as Map<String, dynamic>?;
    final List<dynamic>? videos = _activity?['videos'] as List<dynamic>?;
    return _card('一起上学 · 对方最近学了什么', <Widget>[
      Wrap(
        spacing: 8,
        children: <Widget>[
          for (final int days in <int>[7, 30])
            ChoiceChip(
              label: Text('近 $days 天'),
              selected: _days == days,
              onSelected: _busy
                  ? null
                  : (_) {
                      setState(() => _days = days);
                      unawaited(_load());
                    },
            ),
        ],
      ),
      if (summary == null)
        const Text('对方尚未共享学习时长。')
      else ...<Widget>[
        Text(
          '已同步学习 ${((summary['study_seconds'] as num) / 60).floor()} 分钟 · ${summary['study_days']} 天',
        ),
        for (final dynamic day in summary['daily'] as List<dynamic>)
          Text('${day['day']} · ${((day['seconds'] as num) / 60).floor()} 分钟'),
      ],
      const SizedBox(height: 12),
      if (videos == null)
        const Text('对方尚未共享近期视频记录。')
      else if (videos.isEmpty)
        const Text('此周期内暂无已同步的视频记录。')
      else
        for (final dynamic video in videos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.ondemand_video),
            title: Text('${video['title']}'),
            subtitle: Text(
              '${video['day']} · ${video['completed'] == true ? '进度标记完成' : '近期学过'}',
            ),
          ),
      const Text(
        '统计来自已同步记录，可能有延迟；时长不是可信奖励依据。私有视频不提供地址或标题。',
        style: TextStyle(fontSize: 12),
      ),
    ]);
  }

  Widget _libraryCard() {
    final Map<String, dynamic>? counts =
        _library?['counts'] as Map<String, dynamic>?;
    return _card('图书馆 · 收藏单词对照', <Widget>[
      OutlinedButton.icon(
        onPressed: _busy ? null : _syncLibrary,
        icon: const Icon(Icons.sync),
        label: const Text('同步我的最新收藏快照'),
      ),
      const Text(
        '对照最近同步的收藏单词，短语另行展示；收藏量不代表词汇量，目前不显示未经测评的词汇估计。',
        style: TextStyle(fontSize: 12),
      ),
      if (_libraryError != null) Text(_libraryError!),
      if (counts != null) ...<Widget>[
        if ((_library!['snapshots'] as Map<String, dynamic>?)?['mine'] == null)
          const Text('我还没有同步收藏快照；请先点击上方同步按钮。'),
        if ((_library!['snapshots'] as Map<String, dynamic>?)?['peer'] == null)
          const Text('对方还没有同步收藏快照，当前对照尚不完整。'),
        Text(
          '我 ${counts['mine']} · 对方 ${counts['peer']} · 共同 ${counts['common']}',
        ),
        Text('仅我 ${counts['mine_only']} · 仅对方 ${counts['peer_only']}'),
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (final (String key, String title) in <(String, String)>[
              ('common', '共同收藏'),
              ('mine', '仅我收藏'),
              ('peer', '仅对方收藏'),
            ])
              ChoiceChip(
                label: Text(title),
                selected: _category == key,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(() => _category = key);
                        unawaited(_load());
                      },
              ),
          ],
        ),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: '搜索词条',
            suffixIcon: IconButton(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) => _load(),
        ),
        if ((_library!['words'] as List<dynamic>).isEmpty)
          const Text('当前分类没有匹配的收藏词。'),
        for (final dynamic word in _library!['words'] as List<dynamic>)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('$word'),
            trailing: _category == 'peer'
                ? TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!await _confirm(
                                  '收藏这个单词',
                                  '将 $word 加入自己的收藏，不复制对方的原句或记忆进度。',
                                ) ||
                                !mounted)
                              return;
                            await _action(() async {
                              await ref
                                  .read(wordBookProvider.notifier)
                                  .mergeRemoteFavorite(word: '$word');
                              final List<String> words = ref
                                  .read(wordBookProvider)
                                  .where(
                                    (WordEntry w) =>
                                        w.favorite &&
                                        w.kind == VocabCardKind.word,
                                  )
                                  .map((WordEntry w) => w.word)
                                  .toList();
                              await _request(
                                'PUT',
                                '/library',
                                data: <String, dynamic>{'words': words},
                              );
                            });
                          },
                    child: const Text('收藏'),
                  )
                : null,
          ),
        if ((_library!['total'] as num) >
            (_library!['words'] as List<dynamic>).length)
          TextButton(
            onPressed: _busy ? null : _loadMoreLibrary,
            child: const Text('加载更多收藏单词'),
          ),
      ],
    ]);
  }
}

class _WeeklyQuestCard extends StatelessWidget {
  const _WeeklyQuestCard({
    required this.hasPeer,
    required this.onEncourage,
  });

  final bool hasPeer;
  final VoidCallback? onEncourage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AdventurePalette.pathAmber.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x22000000), offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hasPeer ? '本周同桌一起练' : '本周目标 · 邀请同桌一起练',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            hasPeer
                ? '用词汇 PK、考试备考或共享词库互相督促。'
                : '配对后可发起词汇 PK，并互相提醒坚持学习。',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          if (onEncourage != null) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onEncourage,
                child: const Text('提醒同桌'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
