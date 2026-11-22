import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../../import_course/data/bilibili_cover_refresh.dart';
import '../../../import_course/data/bilibili_import_service.dart';
import '../../../import_course/data/bilibili_multipage.dart';
import '../../../library/presentation/library_catalog_provider.dart';
import '../../../library/presentation/library_mock_data.dart';

enum _VideoAction { rename, refreshCover }

class PlayerVideoOptions extends StatefulWidget {
  const PlayerVideoOptions({
    super.key,
    required this.catalog,
    required this.course,
    required this.episode,
    required this.player,
    required this.cookie,
  });

  final LibraryCatalogNotifier catalog;
  final LibraryCourseData course;
  final LibraryEpisodeItem episode;
  final Player? player;
  final String cookie;

  @override
  State<PlayerVideoOptions> createState() => _PlayerVideoOptionsState();
}

class _PlayerVideoOptionsState extends State<PlayerVideoOptions> {
  bool _busy = false;

  Future<void> _select(_VideoAction action) async {
    final LibraryEpisodeItem episode = widget.episode;
    final LibraryCourseData course = widget.course;
    final LibraryCatalogNotifier catalog = widget.catalog;
    setState(() => _busy = true);
    try {
      if (action == _VideoAction.rename) {
        String name = episode.title;
        final String? result = await showDialog<String>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('修改视频标题'),
            content: TextFormField(
              initialValue: name,
              autofocus: true,
              maxLength: 160,
              decoration: const InputDecoration(labelText: '视频标题'),
              onChanged: (String value) => name = value,
              onFieldSubmitted: (String value) {
                if (value.trim().isNotEmpty)
                  Navigator.pop(dialogContext, value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (name.trim().isNotEmpty)
                    Navigator.pop(dialogContext, name);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
        if (result == null || !mounted) return;
        await catalog.updateEpisodeDisplay(
          courseId: course.id,
          episodeId: episode.id,
          title: result,
        );
        _message('视频标题已更新');
      } else {
        final String? cover = await _fetchCover(course, episode);
        if (!mounted) return;
        if (cover == null) {
          _message('暂时无法获取封面，请播放视频后重试。');
          return;
        }
        await catalog.updateEpisodeDisplay(
          courseId: course.id,
          episodeId: episode.id,
          cover: cover,
        );
        _message('视频封面已更新');
      }
    } catch (_) {
      _message('视频信息更新失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _fetchCover(
    LibraryCourseData course,
    LibraryEpisodeItem episode,
  ) async {
    final Player? player = widget.player;
    final String? source = bilibiliSourceForEpisode(
      course: course,
      episode: episode,
      videoAsset: episode.videoAsset,
    );
    if (source != null && source.isNotEmpty) {
      try {
        final String? poster =
            await BilibiliImportService.withCookie(widget.cookie)
                .resolveCoverImage(source, refresh: true)
                .timeout(const Duration(seconds: 10));
        if (poster != null && isDisplayableCover(poster)) return poster;
      } catch (_) {}
    }
    if (!mounted || player == null) return null;
    final Uint8List? bytes = await player.screenshot();
    if (bytes == null || bytes.isEmpty) return null;
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory directory = await Directory(
      '${docs.path}/video_covers',
    ).create(recursive: true);
    final String id = Uri.encodeComponent(episode.id);
    final File file = File(
      '${directory.path}/$id-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<_VideoAction>(
    tooltip: '视频选项',
    enabled: !_busy,
    onSelected: _select,
    itemBuilder: (_) => const [
      PopupMenuItem(value: _VideoAction.rename, child: Text('修改视频标题')),
      PopupMenuItem(value: _VideoAction.refreshCover, child: Text('重新获取封面')),
    ],
  );
}
