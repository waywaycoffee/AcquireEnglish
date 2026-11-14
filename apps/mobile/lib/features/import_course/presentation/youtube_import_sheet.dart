import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import '../../subtitle_completion/subtitle_completion_scheduler.dart';
import '../data/bilibili_episode_prepare.dart';
import '../data/youtube_import_service.dart';
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
  final YoutubeImportService _service = const YoutubeImportService();
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
    try {
      final YoutubeImportResult meta = await _service.fetch(id);
      final String courseId = 'youtube-${meta.videoId}';
      final bool hasEn = meta.enSubtitlePath != null;
      final bool hasZh = meta.cnSubtitlePath != null;
      final LibraryCourseData course = LibraryCourseData(
        id: courseId,
        title: meta.title,
        description: meta.author == null
            ? meta.watchUrl
            : '${meta.author} · ${meta.watchUrl}',
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
      final bool canLocalAsr = course.episodes.any(
        (LibraryEpisodeItem ep) => isUsableLocalVideoPath(ep.videoAsset),
      );
      if (ok && canLocalAsr) {
        await enqueueSubtitleCompletionForCourse(course: course);
        SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
      }
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      Navigator.of(context).pop();
      final String subtitleHint;
      if (hasEn && hasZh) {
        subtitleHint = '中英字幕已就绪。';
      } else if (!canLocalAsr) {
        // Watch URL alone cannot run on-device Whisper — do not claim backfill.
        subtitleHint = !hasEn && !hasZh
            ? '缺中英字幕；下载到本地后再补全。'
            : (!hasEn ? '缺英文字幕；下载到本地后再补全。' : '缺中文字幕；下载到本地后再补全。');
      } else {
        subtitleHint = !hasEn && !hasZh
            ? '缺中英字幕，已开始后台补全。'
            : (!hasEn
                  ? '缺英文字幕，已开始后台补全。'
                  : '缺中文字幕，已开始后台补全。');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已加入书库。$subtitleHint' : '该书库中已有此 YouTube 课程'),
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
          '导入 YouTube 链接',
          style: TextStyle(
            color: StudyShellTokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '粘贴链接后自动拉取标题与字幕轴；无字幕则进入学习页用 ASR。',
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
          child: Text(_busy ? '拉取中…' : '加入书库'),
        ),
      ],
    );
  }
}
