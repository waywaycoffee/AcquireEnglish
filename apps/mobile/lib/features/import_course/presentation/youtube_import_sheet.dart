import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../../shared/presentation/widgets/youtube_brand_icon.dart';
import '../data/youtube_import_actions.dart';

Future<void> showYoutubeImportSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: StudyShellTokens.surface,
    builder: (BuildContext context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: const _YoutubeImportForm(),
      );
    },
  );
}

class _YoutubeImportForm extends ConsumerStatefulWidget {
  const _YoutubeImportForm();

  @override
  ConsumerState<_YoutubeImportForm> createState() => _YoutubeImportFormState();
}

class _YoutubeImportFormState extends ConsumerState<_YoutubeImportForm> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final opened = await importYoutubeVideoById(
      context, ref,
      videoId: _controller.text.trim(),
      closeSheetOnSuccess: true,
    );
    if (!mounted || opened) return;
    setState(() {
      _busy = false;
      _error = '请检查链接及 YouTube 网络连接后重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Row(
          children: <Widget>[
            YoutubeBrandIcon(size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '导入 YouTube 链接',
                style: TextStyle(
                  color: StudyShellTokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '支持视频和合集链接。合集先在线播放第一集。需可访问 YouTube 的网络。',
          style: TextStyle(color: StudyShellTokens.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          style: const TextStyle(color: StudyShellTokens.textPrimary),
          decoration: const InputDecoration(
            hintText: 'https://www.youtube.com/watch?v=...',
            hintStyle: TextStyle(color: StudyShellTokens.textMuted),
            prefixIcon: Padding(
              padding: EdgeInsets.only(left: 12, right: 4),
              child: YoutubeBrandIcon(size: 22),
            ),
            prefixIconConstraints: BoxConstraints(minWidth: 40, minHeight: 24),
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: YoutubeBrandIcon.brandRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const YoutubeBrandIcon(size: 20),
          label: Text(_busy ? '拉取中…' : '打开播放'),
        ),
      ],
    );
  }
}
