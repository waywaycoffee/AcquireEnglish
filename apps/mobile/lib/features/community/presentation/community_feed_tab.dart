import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../import_course/data/bilibili_open_or_import.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../data/community_models.dart';
import 'adventure_ui.dart';
import 'community_post_actions.dart';
import 'community_provider.dart';

class CommunityFeedTab extends ConsumerWidget {
  const CommunityFeedTab({
    super.key,
    this.kinds,
    this.emptyTitle = '还没有练习成果',
    this.emptyMeta = '发一条跟读、模考或仿写成果；也可分享素材或提问',
    this.emptyHint = '练习流优先展示成果卡；真题资料请看「考试」页。',
  });

  /// When set, only posts whose [CommunityPostDto.kind] is in this set.
  final Set<String>? kinds;
  final String emptyTitle;
  final String emptyMeta;
  final String emptyHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CommunityPostDto>> async = ref.watch(
      communityFeedProvider,
    );

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: () => ref.read(communityFeedProvider.notifier).refresh(),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object e, StackTrace st) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: <Widget>[Text('加载失败：$e')],
            ),
            data: (List<CommunityPostDto> posts) {
              final List<CommunityPostDto> ordered = _orderQuestFirst(posts)
                  .where(
                    (CommunityPostDto p) =>
                        kinds == null || kinds!.contains(p.kind),
                  )
                  .toList(growable: false);
              if (ordered.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    QuestFeedCard(
                      title: emptyTitle,
                      meta: emptyMeta,
                      badge: '推荐',
                      accent: AppDesignTokens.brandGreen,
                      onPlay: () => context.push('/exam'),
                    ),
                    const SizedBox(height: 12),
                    Text(emptyHint),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                itemCount: ordered.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int index) {
                  if (index == ordered.length)
                    return TextButton(
                      onPressed:
                          ref.read(communityFeedProvider.notifier).hasMore
                          ? () async {
                              try {
                                await ref
                                    .read(communityFeedProvider.notifier)
                                    .loadMore();
                              } catch (_) {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('加载更多失败，请重试')),
                                  );
                              }
                            }
                          : null,
                      child: Text(
                        ref.read(communityFeedProvider.notifier).hasMore
                            ? '加载更多'
                            : '已显示全部内容',
                      ),
                    );
                  return CommunityPostCard(post: ordered[index]);
                },
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: QuestComposerBar(
            onTap: () => unawaited(_showComposer(context, ref)),
          ),
        ),
      ],
    );
  }

  static bool _hasChallenge(CommunityPostDto post) => false;

  static List<CommunityPostDto> _orderQuestFirst(List<CommunityPostDto> posts) {
    final List<CommunityPostDto> quests = <CommunityPostDto>[];
    final List<CommunityPostDto> rest = <CommunityPostDto>[];
    for (final CommunityPostDto post in posts) {
      if (_hasChallenge(post)) {
        quests.add(post);
      } else {
        rest.add(post);
      }
    }
    return <CommunityPostDto>[...quests, ...rest];
  }

  Future<void> _showComposer(BuildContext context, WidgetRef ref) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFFF7F1E8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppDesignTokens.brandGreen,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '分享今天的练习成果',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ),
              const SizedBox(height: 12),
              for (final (String id, String title, String meta, Color accent)
                  in <(String, String, String, Color)>[
                (
                  'imitation',
                  '句子仿写',
                  '基于素材原句仿写，求用词点评',
                  AppDesignTokens.brandGreen,
                ),
                (
                  'shadowing',
                  '跟读投稿',
                  '一句 / 一段，求重音与连读反馈',
                  const Color(0xFF5B8DEF),
                ),
                (
                  'sentence_make',
                  '选词造句',
                  '用复习词造句，可绑 FSRS',
                  const Color(0xFF8E44AD),
                ),
                (
                  'learning_result',
                  '分享学习成果',
                  '精听 / 模考等通用成果卡',
                  AppDesignTokens.brandGreen,
                ),
                (
                  'share_bilibili',
                  '分享 B 站视频',
                  '推荐精听片子',
                  AppDesignTokens.brandGreen,
                ),
                (
                  'method',
                  '分享学习方法',
                  '把有效练法写成任务卡',
                  const Color(0xFF5B8DEF),
                ),
                (
                  'question',
                  '学习问答',
                  '卡住的地方喊人一起想',
                  const Color(0xFFE67E22),
                ),
                (
                  'team_invite',
                  '组队邀请',
                  '找搭子一起练',
                  AppDesignTokens.brandGreen,
                ),
                (
                  'feedback',
                  '吐槽软件功能',
                  '反馈缺陷与体验',
                  AppDesignTokens.orange,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: QuestFeedCard(
                    title: title,
                    meta: meta,
                    badge: '发帖',
                    accent: accent,
                    onPlay: () => Navigator.pop(ctx, id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _ComposeSheet(kind: choice),
    );
  }
}

class CommunityPostCard extends ConsumerWidget {
  const CommunityPostCard({required this.post});

  final CommunityPostDto post;

  String get _kindLabel {
    switch (post.kind) {
      case 'team_invite':
        return '组队';
      case 'share_bilibili':
        return '分享';
      case 'feedback':
        return '反馈';
      case 'learning_result':
        return '学习成果';
      case 'imitation':
        return '仿写';
      case 'shadowing':
        return '跟读';
      case 'sentence_make':
        return '造句';
      case 'method':
        return '学习方法';
      case 'question':
        return '学习问答';
      default:
        return post.kind;
    }
  }

  String get _metaLine {
    final String level = post.authorLevel ?? post.englishLevel ?? '';
    final String when = _relative(post.createdAt);
    if (level.isEmpty) return when;
    return '$when · $level';
  }

  String _relative(DateTime time) {
    final Duration d = DateTime.now().difference(time.toLocal());
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    if (d.inDays < 7) return '${d.inDays} 天前';
    return '${time.month}/${time.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CommunityPostDto post =
        ref.watch(communityPostUpdatesProvider)[this.post.id] ?? this.post;

    final String bodyPreview = post.body.trim().isEmpty ? post.title : post.body;
    final String compact = bodyPreview.replaceAll('\n', ' ');
    final String embedBits = <String>[
      if ((post.embedWord ?? '').isNotEmpty) '词条 ${post.embedWord}',
      if (post.embedTimestampSec != null)
        '⏱ ${post.embedTimestampSec!.toStringAsFixed(1)}s',
      if ((post.oralAudioUrl ?? '').isNotEmpty) '有跟读录音',
      if ((post.transcript ?? '').isNotEmpty) '已转写',
    ].join(' · ');
    final String metaCore =
        '$_metaLine · ♥${post.likeCount} · 💬${post.commentCount}'
        '${embedBits.isEmpty ? '' : ' · $embedBits'}'
        '${compact.isEmpty ? '' : ' · $compact'}';
    void openActions() {
      showModalBottomSheet<void>(
        context: context,
        builder: (BuildContext ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '帖子操作',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                CommunityPostActions(post: post),
              ],
            ),
          ),
        ),
      );
    }

    if (post.isShareBilibili) {
      final String title = post.linkTitle?.trim().isNotEmpty == true
          ? post.linkTitle!.trim()
          : (post.title.isNotEmpty ? post.title : 'B 站视频任务');
      return QuestFeedCard(
        title: '${post.authorName} · $title',
        meta: metaCore,
        badge: '视频素材',
        accent: const Color(0xFFE67E22),
        authorAvatar: post.authorAvatar,
        onPlay: () => unawaited(_openLink(context, ref)),
        onLongPress: openActions,
        trailing: IconButton(
          tooltip: '更多',
          onPressed: openActions,
          icon: const Icon(Icons.more_horiz_rounded),
        ),
      );
    }
    return QuestFeedCard(
      title: '${post.authorName} · ${_kindLabel}',
      meta: metaCore,
      badge: _kindLabel,
      accent: post.kind == 'method'
          ? const Color(0xFF5B8DEF)
          : post.kind == 'question'
              ? const Color(0xFFE67E22)
              : post.kind == 'feedback'
                  ? AppDesignTokens.orange
                  : AppDesignTokens.brandGreen,
      authorAvatar: post.authorAvatar,
      showPlayChevron: post.kind != 'question' && post.kind != 'method',
      onPlay: () => unawaited(_openComments(context, ref)),
      onLongPress: openActions,
      trailing: IconButton(
        tooltip: '更多',
        onPressed: openActions,
        icon: const Icon(Icons.more_horiz_rounded),
      ),
    );
  }

  Future<void> _openLink(BuildContext context, WidgetRef ref) async {
    final String? url = post.linkUrl?.trim();
    if (url == null || url.isEmpty) return;
    final String? episodeId = await openBilibiliLearningOrImport(
      context,
      ref,
      watchUrl: url,
      startImportImmediately: true,
      pushPlayer: false,
    );
    if (!context.mounted || episodeId == null) return;
    await context.pushNamed<void>(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episodeId},
      queryParameters: const <String, String>{'autoplay': '1'},
    );
  }

  Future<void> _openComments(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _CommentsSheet(post: post),
    );
    await ref.read(communityFeedProvider.notifier).refresh();
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.post});

  final CommunityPostDto post;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final TextEditingController _body = TextEditingController();
  List<CommunityCommentDto> _comments = <CommunityCommentDto>[];
  bool _loading = true;
  bool _busy = false;
  bool _mirror = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<CommunityCommentDto> rows = await ref
          .read(acquireApiClientProvider)
          .communityComments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('评论加载失败：$e')));
    }
  }

  Future<void> _submit() async {
    final String text = _body.text.trim();
    if (text.isEmpty || _busy) return;
    final bool hasCookie = ref
        .read(learningPreferencesProvider)
        .hasBilibiliCookie;
    if (_mirror && !hasCookie) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中授权 B 站 Cookie，再同步评论')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final CommunityCommentDto created = await ref
          .read(acquireApiClientProvider)
          .createCommunityComment(
            postId: widget.post.id,
            body: text,
            mirrorToBilibili: _mirror,
          );
      if (!mounted) return;
      _body.clear();
      setState(() {
        _comments = <CommunityCommentDto>[..._comments, created];
        _busy = false;
      });
      if (created.mirroredToBilibili) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已同步到 B 站视频评论区')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发送失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets inset = MediaQuery.viewInsetsOf(context);
    final bool canMirror = widget.post.isShareBilibili;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + inset.bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.post.title.isEmpty ? '评论' : widget.post.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ((widget.post.embedWord ?? '').isNotEmpty ||
                widget.post.embedTimestampSec != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                <String>[
                  if ((widget.post.embedWord ?? '').isNotEmpty)
                    '词条：${widget.post.embedWord}',
                  if (widget.post.embedTimestampSec != null)
                    '时间戳：${widget.post.embedTimestampSec!.toStringAsFixed(1)}s',
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            CommunityPostActions(post: widget.post),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                  ? const Center(child: Text('还没有评论；点评请实名，可用下方模板'))
                  : ListView.separated(
                      itemCount: _comments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final CommunityCommentDto c = _comments[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.authorName),
                          subtitle: Text(c.body),
                          trailing: c.mirroredToBilibili
                              ? const Icon(Icons.sync, size: 18)
                              : null,
                        );
                      },
                    ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final String chip in const <String>[
                    '【语法】',
                    '【用词】',
                    '【句式】',
                    '【自然度】',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(chip),
                        onPressed: () {
                          final String current = _body.text;
                          if (current.contains(chip)) return;
                          _body.text = current.isEmpty ? '$chip ' : '$current$chip ';
                          _body.selection = TextSelection.collapsed(
                            offset: _body.text.length,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (canMirror)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('一键同步到 B 站评论区'),
                subtitle: const Text('需已授权 B 站登录 Cookie'),
                value: _mirror,
                onChanged: (bool v) => setState(() => _mirror = v),
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _body,
                    decoration: const InputDecoration(
                      hintText: '写点评（不覆盖原文）…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? '…' : '发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeSheet extends ConsumerStatefulWidget {
  const _ComposeSheet({required this.kind});

  final String kind;

  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _link = TextEditingController();
  final TextEditingController _embedWord = TextEditingController();
  final TextEditingController _embedTs = TextEditingController();
  bool _busy = false;
  bool _recording = false;
  String? _oralPath;
  String? _oralAudioUrl;
  String? _oralBookId;
  String? _oralKey;
  final AudioRecorder _recorder = AudioRecorder();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    _embedWord.dispose();
    _embedTs.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  bool get _supportsEmbed => const <String>{
        'question',
        'imitation',
        'shadowing',
        'sentence_make',
        'learning_result',
        'method',
      }.contains(widget.kind);

  String get _heading {
    switch (widget.kind) {
      case 'team_invite':
        return '组队邀请';
      case 'share_bilibili':
        return '分享你喜欢的 B 站视频';
      case 'imitation':
        return '句子仿写';
      case 'shadowing':
        return '跟读投稿';
      case 'sentence_make':
        return '选词造句';
      case 'learning_result':
        return '分享学习成果';
      case 'method':
        return '分享学习方法';
      case 'question':
        return '提出学习问题';
      default:
        return '反馈软件功能';
    }
  }

  bool _isYoutubeUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    final String host = uri.host.toLowerCase().replaceFirst('www.', '');
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host.endsWith('.youtube.com');
  }

  bool _isBilibiliUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    final String host = uri.host.toLowerCase().replaceFirst('www.', '');
    return host == 'bilibili.com' ||
        host.endsWith('.bilibili.com') ||
        host == 'b23.tv';
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (widget.kind == 'share_bilibili') {
      final String link = _link.text.trim();
      if (link.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请粘贴 B 站视频链接')));
        return;
      }
      if (_isYoutubeUrl(link)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('因政策原因，暂时不支持分享 YouTube 视频，请改用 B 站链接')),
        );
        return;
      }
      if (!_isBilibiliUrl(link)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('目前仅支持 bilibili.com / b23.tv 链接')),
        );
        return;
      }
    }
    final bool outputKind = const <String>{
      'learning_result',
      'imitation',
      'shadowing',
      'sentence_make',
      'method',
      'question',
    }.contains(widget.kind);
    final String optionalLink = _link.text.trim();
    if (outputKind && optionalLink.isNotEmpty) {
      if (_isYoutubeUrl(optionalLink)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('因政策原因，暂时不支持分享 YouTube 视频，请改用 B 站链接')),
        );
        return;
      }
      final Uri? uri = Uri.tryParse(optionalLink);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('素材链接须为 http(s)')),
        );
        return;
      }
    }
    final double? embedTs = double.tryParse(_embedTs.text.trim());
    setState(() => _busy = true);
    try {
      if (widget.kind == 'shadowing' &&
          _oralAudioUrl == null &&
          _oralPath != null) {
        await _uploadOralIfNeeded();
      }
      final CommunityPostDto? created = await ref
          .read(communityFeedProvider.notifier)
          .createPost(
            kind: widget.kind,
            title: _title.text.trim(),
            body: _body.text.trim(),
            linkUrl: widget.kind == 'share_bilibili'
                ? _link.text.trim()
                : (outputKind && optionalLink.isNotEmpty ? optionalLink : null),
            linkTitle: widget.kind == 'share_bilibili'
                ? _title.text.trim()
                : null,
            embedWord: _supportsEmbed ? _embedWord.text.trim() : null,
            embedTimestampSec: _supportsEmbed ? embedTs : null,
            oralAudioUrl: _oralAudioUrl,
            oralBookId: _oralBookId,
            oralKey: _oralKey,
          );
      if (widget.kind == 'shadowing' &&
          created != null &&
          (_oralAudioUrl ?? '').isNotEmpty) {
        try {
          await ref
              .read(acquireApiClientProvider)
              .transcribeCommunityPost(created.id);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已发布')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发布失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadOralIfNeeded() async {
    final String? path = _oralPath;
    if (path == null || !File(path).existsSync()) return;
    final String email = ref.read(authSessionProvider).email.trim();
    final String bookId = email.isEmpty
        ? 'user_guest'
        : 'user_${email.hashCode.abs()}';
    final String key =
        'shadow_${DateTime.now().millisecondsSinceEpoch}';
    final Map<String, dynamic> uploaded =
        await ref.read(acquireApiClientProvider).uploadContentMedia(
              bytes: await File(path).readAsBytes(),
              filename: 'shadowing.m4a',
              bookId: bookId,
              key: key,
              namespace: 'oral',
            );
    final Map<String, dynamic>? item =
        uploaded['item'] as Map<String, dynamic>?;
    final String? url = (item?['audio_url'] as String?)?.trim();
    _oralAudioUrl = (url == null || url.isEmpty)
        ? null
        : url;
    _oralBookId = bookId;
    _oralKey = key;
  }

  Future<void> _toggleShadowingRecord() async {
    try {
      if (_recording) {
        final String? path = await _recorder.stop();
        setState(() {
          _recording = false;
          _oralPath = path ?? _oralPath;
          _oralAudioUrl = null;
        });
        return;
      }
      if (!await _recorder.hasPermission()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录跟读')),
        );
        return;
      }
      final Directory dir = await getTemporaryDirectory();
      final String path =
          '${dir.path}/community-shadow-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _recording = true;
        _oralPath = path;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('录音失败：$e')),
      );
      setState(() => _recording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + pad.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_heading, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '内容',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.kind == 'share_bilibili') ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '后台会自动归类兴趣领域与英语难度；若不准，其他同学可申请纠错。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _link,
                decoration: const InputDecoration(
                  labelText: 'B 站视频链接',
                  hintText: 'https://www.bilibili.com/video/… 或 b23.tv/…',
                  border: OutlineInputBorder(),
                ),
              ),
            ] else if (const <String>{
              'learning_result',
              'imitation',
              'shadowing',
              'sentence_make',
              'method',
              'question',
            }.contains(widget.kind)) ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                controller: _link,
                decoration: const InputDecoration(
                  labelText: '素材链接（可选）',
                  hintText: 'https://…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (widget.kind == 'shadowing') ...<Widget>[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => unawaited(_toggleShadowingRecord()),
                icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(
                  _recording
                      ? '停止录音'
                      : (_oralPath == null ? '录制跟读（上传 ECS）' : '已录好，可重录'),
                ),
              ),
              if (_oralPath != null && !_recording)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '录音将上传到 ECS oral 命名空间，并可自动转写',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (_supportsEmbed) ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                controller: _embedWord,
                decoration: const InputDecoration(
                  labelText: '关联词条（可选）',
                  hintText: 'apple / Could I get…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _embedTs,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '台词时间戳秒（可选）',
                  hintText: '12.5',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '发布中…' : '发布'),
            ),
          ],
        ),
      ),
    );
  }
}
