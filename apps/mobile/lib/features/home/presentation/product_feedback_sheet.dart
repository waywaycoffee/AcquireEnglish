import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';

const List<(String, String)> _kFeedbackCategories = <(String, String)>[
  ('general', '综合建议'),
  ('bug', '功能缺陷'),
  ('ux', '界面体验'),
  ('content', '内容与课程'),
  ('performance', '卡顿 / 性能'),
  ('billing', '会员 / 支付'),
  ('feature', '想要的新功能'),
];

Future<void> showProductFeedbackSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!ref.read(authSessionProvider).isLoggedIn) {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('需要登录'),
        content: const Text('登录后可提交意见反馈。反馈仅运营可见，其他用户看不到。'),
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
    builder: (BuildContext ctx) => const _ProductFeedbackSheet(),
  );
}

class _ProductFeedbackSheet extends ConsumerStatefulWidget {
  const _ProductFeedbackSheet();

  @override
  ConsumerState<_ProductFeedbackSheet> createState() =>
      _ProductFeedbackSheetState();
}

class _ProductFeedbackSheetState extends ConsumerState<_ProductFeedbackSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  String _category = 'general';
  bool _sending = false;
  String? _error;

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
      await ref.read(acquireApiClientProvider).submitProductFeedback(
            body: text,
            title: _title.text.trim(),
            category: _category,
            contact: _contact.text.trim(),
            appVersion: version,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已提交。仅运营后台可见，其他用户看不到你的反馈。'),
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
            Text('意见反馈', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '直接发给运营后台，不会出现在社区，其他试用用户看不到。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '类型',
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
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              enabled: !_sending,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '具体内容',
                hintText: '例如：某页点不开、字幕不准、希望加某某功能…',
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
                hintText: '微信 / 邮箱，方便回访',
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
            FilledButton(
              onPressed: _sending ? null : _submit,
              child: Text(_sending ? '提交中…' : '提交给运营'),
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
