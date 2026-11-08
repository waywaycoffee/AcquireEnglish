import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../data/bilibili_import_service.dart';
import '../domain/bilibili_import.dart';

Future<void> showBilibiliImportSheet(BuildContext context, WidgetRef ref) {
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
        child: const _BilibiliImportForm(),
      );
    },
  );
}

class _BilibiliImportForm extends ConsumerStatefulWidget {
  const _BilibiliImportForm();

  @override
  ConsumerState<_BilibiliImportForm> createState() => _BilibiliImportFormState();
}

class _BilibiliImportFormState extends ConsumerState<_BilibiliImportForm> {
  final TextEditingController _controller = TextEditingController();
  final BilibiliImportService _service = BilibiliImportService();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!BilibiliImport.isBilibiliUrl(_controller.text)) {
      setState(() => _error = '请输入有效的 Bilibili 链接、BVxxx 或 av 号');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final BilibiliImportResult meta = await _service.fetch(_controller.text);
      final String courseId = 'bilibili-${meta.idKey}';
      final bool hasEn = meta.enSubtitlePath != null;
      final bool hasZh = meta.cnSubtitlePath != null;
      final LibraryCourseData course = LibraryCourseData(
        id: courseId,
        title: meta.title,
        description: meta.author == null
            ? meta.watchUrl
            : '${meta.author} · ${meta.watchUrl}',
        sourceLabel: 'Bilibili',
        coverImage: 'assets/img/app_icon.png',
        level: 'A2',
        category: 'bilibili',
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
            title: meta.title,
            durationMinutes: meta.durationMinutes,
            hasChineseSubtitles: hasZh,
            hasEnglishSubtitles: hasEn,
            completed: false,
            progressPercent: 0,
            coverImage: 'assets/img/app_icon.png',
            videoAsset: meta.watchUrl,
            enSubtitleAsset: meta.enSubtitlePath,
            cnSubtitleAsset: meta.cnSubtitlePath,
            subtitleTracks: <LibrarySubtitleTrackItem>[
              if (hasEn)
                LibrarySubtitleTrackItem(
                  languageCode: 'en',
                  languageLabel: 'English',
                  path: meta.enSubtitlePath!,
                ),
              if (hasZh)
                LibrarySubtitleTrackItem(
                  languageCode: 'zh',
                  languageLabel: '中文',
                  path: meta.cnSubtitlePath!,
                ),
            ],
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
      final String subtitleHint = (hasEn || hasZh)
          ? '已拉取${hasEn ? '英' : ''}${hasEn && hasZh ? '/' : ''}${hasZh ? '中' : ''}字幕。'
          : '未找到字幕，打开后可用语音识别生成。';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '已加入书库。$subtitleHint打开播放页将尝试直链精听/跟读。'
                : '该书库中已有此 Bilibili 课程',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '导入失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          '导入 Bilibili 链接',
          style: TextStyle(
            color: StudyShellTokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '支持 BV / av 链接。有字幕则写入学习轴；无字幕可 ASR。打开后会解析 B 站直链，用真实进度驱动精听/跟读。',
          style: TextStyle(color: StudyShellTokens.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          style: const TextStyle(color: StudyShellTokens.textPrimary),
          decoration: const InputDecoration(
            hintText: 'https://www.bilibili.com/video/BVxxxx',
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
            backgroundColor: const Color(0xFFFB7299),
          ),
          child: Text(_busy ? '拉取中…' : '加入书库'),
        ),
      ],
    );
  }
}
