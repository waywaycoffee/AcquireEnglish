import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';

/// Community 「反馈」: feature/bug tickets with description, screenshot, status.
class FeatureFeedbackTab extends ConsumerStatefulWidget {
  const FeatureFeedbackTab({super.key});

  @override
  ConsumerState<FeatureFeedbackTab> createState() => _FeatureFeedbackTabState();
}

class _FeatureFeedbackTabState extends ConsumerState<FeatureFeedbackTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      return const <Map<String, dynamic>>[];
    }
    return ref.read(acquireApiClientProvider).listMyProductFeedback();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _openCompose() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          backgroundColor: AppDesignTokens.appWhite,
          title: Text(
            '需要登录',
            style: TextStyle(color: AppDesignTokens.textPrimary),
          ),
          content: Text(
            '登录后可提交功能问题反馈，并查看处理进度。',
            style: TextStyle(color: AppDesignTokens.textSecondary),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去登录'),
            ),
          ],
        ),
      );
      if ((go ?? false) && mounted) {
        context.go(SGRoute.login.route);
      }
      return;
    }
    final bool? submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.appWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) => const _FeatureFeedbackComposeSheet(),
    );
    if (submitted == true && mounted) {
      _reload();
    }
  }

  String _statusLabel(String status) => switch (status) {
        'done' => '已解决',
        'read' => '处理中',
        _ => '待处理',
      };

  Color _statusColor(String status) => switch (status) {
        'done' => AppDesignTokens.brandGreen,
        'read' => AppDesignTokens.primaryBlueDark,
        _ => AppDesignTokens.orange,
      };

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: () async => _reload(),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
            ) {
              if (!loggedIn) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    Text(
                      '功能问题反馈',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '登录后可提交问题情况描述与截图，并查看解决进度。',
                      style: TextStyle(
                        color: AppDesignTokens.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _openCompose,
                      child: const Text('去登录并反馈'),
                    ),
                  ],
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    Text('加载失败：${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('重试'),
                    ),
                  ],
                );
              }
              final List<Map<String, dynamic>> items =
                  snapshot.data ?? const <Map<String, dynamic>>[];
              if (items.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: <Widget>[
                    Text(
                      '还没有功能问题反馈',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '描述问题情况、可选上传截图。处理进度会显示：待处理 / 处理中 / 已解决。',
                      style: TextStyle(
                        color: AppDesignTokens.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return Text(
                      '我的反馈 · 问题解决情况',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    );
                  }
                  final Map<String, dynamic> item = items[index - 1];
                  final String status = '${item['status'] ?? 'open'}';
                  final String title = '${item['title'] ?? ''}'.trim().isEmpty
                      ? '功能问题反馈'
                      : '${item['title']}'.trim();
                  final String body = '${item['body'] ?? ''}'.trim();
                  final String shot = '${item['screenshot_url'] ?? ''}'.trim();
                  final String note = '${item['admin_note'] ?? ''}'.trim();
                  return Material(
                    color: AppDesignTokens.appWhite,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withValues(
                                    alpha: 0.18,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _statusLabel(status),
                                  style: TextStyle(
                                    color: _statusColor(status),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (body.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              body,
                              style: TextStyle(
                                color: AppDesignTokens.textSecondary,
                                height: 1.4,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (shot.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 140,
                                width: double.infinity,
                                child: CoverImage(
                                  path: shot,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                          if (note.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              '处理说明：$note',
                              style: TextStyle(
                                color: AppDesignTokens.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: FilledButton.icon(
              onPressed: () => unawaited(_openCompose()),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.primaryBlueDark,
                foregroundColor: AppDesignTokens.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('提交功能问题反馈'),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureFeedbackComposeSheet extends ConsumerStatefulWidget {
  const _FeatureFeedbackComposeSheet();

  @override
  ConsumerState<_FeatureFeedbackComposeSheet> createState() =>
      _FeatureFeedbackComposeSheetState();
}

class _FeatureFeedbackComposeSheetState
    extends ConsumerState<_FeatureFeedbackComposeSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  String _category = 'bug';
  XFile? _shot;
  bool _sending = false;
  String? _error;

  static const List<(String, String)> _categories = <(String, String)>[
    ('bug', '功能异常'),
    ('ux', '界面体验'),
    ('performance', '卡顿 / 性能'),
    ('content', '内容与课程'),
    ('billing', '会员 / 支付'),
    ('feature', '功能建议'),
    ('general', '其他'),
  ];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickShot() async {
    final XFile? shot = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (!mounted || shot == null) return;
    setState(() => _shot = shot);
  }

  Future<void> _submit() async {
    final String text = _body.text.trim();
    if (text.length < 2) {
      setState(() => _error = '请填写问题情况描述（至少 2 个字）');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      String version = '';
      try {
        final PackageInfo info = await PackageInfo.fromPlatform();
        version = '${info.version}+${info.buildNumber}';
      } catch (_) {}
      String screenshotUrl = '';
      final XFile? shot = _shot;
      if (shot != null) {
        final List<int> bytes = await shot.readAsBytes();
        final String email = ref.read(authSessionProvider).email.trim();
        final String bookId = email.isEmpty
            ? 'user_guest'
            : 'user_${email.hashCode.abs()}';
        final String key =
            'feedback_${DateTime.now().millisecondsSinceEpoch}';
        final Map<String, dynamic> uploaded =
            await ref.read(acquireApiClientProvider).uploadContentMedia(
                  bytes: bytes,
                  filename: shot.name.isEmpty ? 'feedback.jpg' : shot.name,
                  bookId: bookId,
                  key: key,
                  namespace: 'misc',
                );
        screenshotUrl = '${uploaded['url'] ?? uploaded['path'] ?? ''}'.trim();
      }
      await ref.read(acquireApiClientProvider).submitProductFeedback(
            body: text,
            title: _title.text.trim().isEmpty
                ? '功能问题反馈'
                : _title.text.trim(),
            category: _category,
            appVersion: version,
            screenshotUrl: screenshotUrl,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('反馈已提交，可在本页查看解决进度')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets inset = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + inset.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '功能问题反馈',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '请描述问题情况；可附截图。提交后可在列表查看解决情况。',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                height: 1.4,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            InputDecorator(
              decoration: InputDecoration(
                labelText: '问题类型',
                labelStyle: TextStyle(color: AppDesignTokens.textSecondary),
                filled: true,
                fillColor: AppDesignTokens.softWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _category,
                  dropdownColor: AppDesignTokens.appWhite,
                  style: TextStyle(color: AppDesignTokens.textPrimary),
                  items: <DropdownMenuItem<String>>[
                    for (final (String id, String label) in _categories)
                      DropdownMenuItem<String>(
                        value: id,
                        child: Text(label),
                      ),
                  ],
                  onChanged: _sending
                      ? null
                      : (String? v) {
                          if (v == null) return;
                          setState(() => _category = v);
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              enabled: !_sending,
              style: TextStyle(color: AppDesignTokens.textPrimary),
              decoration: InputDecoration(
                labelText: '标题（可选）',
                hintText: '例如「美剧网盘导入点不开」',
                filled: true,
                fillColor: AppDesignTokens.softWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              enabled: !_sending,
              minLines: 5,
              maxLines: 10,
              style: TextStyle(color: AppDesignTokens.textPrimary),
              decoration: InputDecoration(
                labelText: '问题情况描述',
                hintText: '在哪个页面、做什么操作、出现什么现象、期望怎样…',
                alignLabelWithHint: true,
                filled: true,
                fillColor: AppDesignTokens.softWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _sending ? null : () => unawaited(_pickShot()),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppDesignTokens.textPrimary,
                side: BorderSide(color: AppDesignTokens.borderGray),
              ),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_shot == null ? '添加问题截图（可选）' : '已选截图 · 点击更换'),
            ),
            if (_shot != null) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_shot!.path),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: AppDesignTokens.dangerText),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : () => unawaited(_submit()),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.primaryBlueDark,
                foregroundColor: AppDesignTokens.onAccent,
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_sending ? '提交中…' : '提交反馈'),
            ),
          ],
        ),
      ),
    );
  }
}
