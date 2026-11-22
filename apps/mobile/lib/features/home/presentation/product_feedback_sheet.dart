import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';

const List<(String, String)> _kFeedbackCategories = <(String, String)>[
  ('feature', '软件优化 / 新功能建议'),
  ('ux', '界面体验优化'),
  ('performance', '卡顿 / 性能优化'),
  ('bug', '功能缺陷'),
  ('content', '内容与课程'),
  ('billing', '会员 / 支付'),
  ('general', '其他建议'),
];

/// Product / software optimization suggestions (private → admin only).
Future<void> showProductFeedbackSheet(
  BuildContext context,
  WidgetRef ref, {
  String initialCategory = 'feature',
}) async {
  if (!ref.read(authSessionProvider).isLoggedIn) {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('需要登录'),
        content: const Text(
          '登录后可提交软件优化建议。建议仅运营可见，其他用户看不到。',
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
    if ((go ?? false) && context.mounted) {
      context.go(SGRoute.login.route);
    }
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (BuildContext ctx) => _ProductFeedbackSheet(
      initialCategory: initialCategory,
    ),
  );
}

class _ProductFeedbackSheet extends ConsumerStatefulWidget {
  const _ProductFeedbackSheet({this.initialCategory = 'feature'});

  final String initialCategory;

  @override
  ConsumerState<_ProductFeedbackSheet> createState() =>
      _ProductFeedbackSheetState();
}

class _ProductFeedbackSheetState extends ConsumerState<_ProductFeedbackSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  late String _category;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final bool ok = _kFeedbackCategories.any(
      ((String, String) e) => e.$1 == widget.initialCategory,
    );
    _category = ok ? widget.initialCategory : 'feature';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String text = _body.text.trim();
    if (text.length < 2) {
      setState(() => _error = '请写一点具体内容（至少 2 个字）');
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
      final String title = _title.text.trim().isEmpty
          ? '软件优化建议'
          : _title.text.trim();
      await ref.read(acquireApiClientProvider).submitProductFeedback(
            body: text,
            title: title,
            category: _category,
            contact: _contact.text.trim(),
            appVersion: version,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('优化建议已提交。仅运营后台可见，我们会尽快处理。'),
        ),
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
    final EdgeInsets pad = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + pad.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '软件优化建议',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '直接发给运营后台：功能建议、体验优化、卡顿问题等。'
              '不会出现在社区，其他用户看不到。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 14),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '建议类型',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _category,
                  items: <DropdownMenuItem<String>>[
                    for (final (String id, String label) in _kFeedbackCategories)
                      DropdownMenuItem<String>(value: id, child: Text(label)),
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
              decoration: const InputDecoration(
                labelText: '标题（可选）',
                hintText: '一句话概括，例如「阅读页字体可再大一点」',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              enabled: !_sending,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '具体建议',
                hintText:
                    '请尽量写清：在哪个页面、做什么操作、期望怎样更好。'
                    '例如「社区考试上传后希望能看到审核进度」…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contact,
              enabled: !_sending,
              decoration: const InputDecoration(
                labelText: '联系方式（可选）',
                hintText: '微信 / 邮箱，方便我们回访',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_sending ? '提交中…' : '提交优化建议'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _sending ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}
