import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../import_course/data/bilibili_open_or_import.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../sync/data/acquire_api_client.dart';

class PublicLearningCardScreen extends ConsumerStatefulWidget {
  const PublicLearningCardScreen({super.key, required this.token});
  final String token;
  @override
  ConsumerState<PublicLearningCardScreen> createState() =>
      _PublicLearningCardScreenState();
}

class _PublicLearningCardScreenState
    extends ConsumerState<PublicLearningCardScreen> {
  Map<String, dynamic>? _card;
  String? _error;
  bool _revealed = false;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> card = await ref
          .read(acquireApiClientProvider)
          .learningCardRequest('GET', '/${widget.token}');
      if (mounted)
        setState(() {
          _card = card;
          _error = null;
        });
    } catch (_) {
      if (mounted) setState(() => _error = '学习卡已撤回、来源不可用或网络暂时异常。');
    }
  }

  Future<void> _save() async {
    if (_saving || _card == null) return;
    if (!ref.read(authSessionProvider).isLoggedIn) {
      await context.push('/login');
      if (!mounted || !ref.read(authSessionProvider).isLoggedIn) return;
    }
    final String token = ref.read(authSessionProvider).accessToken;
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> card = await ref
          .read(acquireApiClientProvider)
          .learningCardRequest('GET', '/${widget.token}');
      if (!mounted || token != ref.read(authSessionProvider).accessToken)
        return;
      final bool added = await ref
          .read(phraseBookProvider.notifier)
          .addSharedLearningCard(
            token: widget.token,
            english: '${card['expression']}',
            chinese: '${card['meaning']}',
            title: '${card['title']}',
          );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(added ? '已加入我的短语库与复习计划' : '我的短语库中已有这个表达')),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未能保存，请重新加载后重试。')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('朋友分享的学习卡')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        if (_error != null) ...<Widget>[
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('重新加载')),
        ],
        if (_card == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (_card != null) ...<Widget>[
          Text(
            '${_card!['title']}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('${_card!['author']}分享 · 原视频公开来源'),
          const SizedBox(height: 28),
          Text(
            '${_card!['expression']}',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          if (!_revealed)
            FilledButton(
              onPressed: () => setState(() => _revealed = true),
              child: const Text('我想好了，核对释义'),
            )
          else
            Text('${_card!['meaning']}', style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存到我的短语库'),
          ),
          OutlinedButton(
            onPressed: () => openBilibiliLearningOrImport(
              context,
              ref,
              watchUrl: '${_card!['watch_url']}',
            ),
            child: const Text('导入原视频，开始学习'),
          ),
          const Text('看卡片不自动计成绩、不发动态。保存表达由本人确认，不复制分享者的学习记录。'),
        ],
      ],
    ),
  );
}
