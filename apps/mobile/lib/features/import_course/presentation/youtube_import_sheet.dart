import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../domain/youtube_import.dart';

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
    final String? id = YoutubeImport.extractVideoId(_controller.text);
    if (id == null) {
      setState(() => _error = '请输入有效的 YouTube 链接或视频 ID');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final String courseId = 'youtube-$id';
    final LibraryCourseData course = LibraryCourseData(
      id: courseId,
      title: 'YouTube $id',
      description: YoutubeImport.watchUrl(id),
      sourceLabel: 'YouTube',
      coverImage: 'assets/img/app_icon.png',
      level: 'A2',
      category: 'youtube',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 1,
      lastStudiedStr: '未学习',
      rating: 0,
      episodes: <LibraryEpisodeItem>[
        LibraryEpisodeItem(
          id: '$courseId-01',
          numberStr: '01',
          title: 'YouTube 课段',
          durationMinutes: 1,
          hasChineseSubtitles: false,
          hasEnglishSubtitles: false,
          completed: false,
          progressPercent: 0,
          coverImage: 'assets/img/app_icon.png',
          videoAsset: YoutubeImport.watchUrl(id),
          videoMissing: false,
        ),
      ],
    );
    final bool ok = await ref
        .read(libraryCatalogProvider.notifier)
        .importCourse(course);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '已加入书库。打开后可语音识别生成字幕（需可播流/ASR）。'
              : '该书库中已有此 YouTube 课程',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          '导入 YouTube 链接',
          style: TextStyle(
            color: StudyShellTokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '粘贴链接后进入学习页。有自动字幕时可跟播；否则用语音识别生成字幕。',
          style: TextStyle(color: StudyShellTokens.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          style: const TextStyle(color: StudyShellTokens.textPrimary),
          decoration: const InputDecoration(
            hintText: 'https://www.youtube.com/watch?v=...',
            hintStyle: TextStyle(color: StudyShellTokens.textMuted),
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: StudyShellTokens.accent,
          ),
          child: Text(_busy ? '导入中…' : '加入书库'),
        ),
      ],
    );
  }
}
