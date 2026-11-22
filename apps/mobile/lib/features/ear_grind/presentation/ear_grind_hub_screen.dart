import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/presentation/module_gate.dart';
import '../data/ear_grind_controller.dart';
import '../data/ear_grind_foreground.dart';

class EarGrindHubScreen extends ConsumerWidget {
  const EarGrindHubScreen({super.key});

  Future<void> _openPath(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String path,
  }) async {
    final String resolved = path.trim();
    if (resolved.isEmpty) return;
    final bool remote = resolved.startsWith('http://') ||
        resolved.startsWith('https://') ||
        resolved.startsWith('file:');
    if (!remote && !File(resolved).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地文件不存在，请先在视频区导入或重新选择')),
      );
      return;
    }
    await EarGrindForeground.requestPermissions();
    final String mediaPath = resolved.startsWith('file:')
        ? Uri.parse(resolved).toFilePath()
        : resolved;
    await ref.read(earGrindProvider.notifier).open(
          EarGrindSession(
            title: title,
            mediaPath: mediaPath,
            isVideo: looksLikeVideoPath(mediaPath) ||
                (!looksLikeAudioPath(mediaPath) &&
                    !mediaPath.toLowerCase().endsWith('.m3u8')),
          ),
        );
    if (context.mounted) {
      context.push('/ear-grind/play');
    }
  }

  Future<void> _pickLocal(BuildContext context, WidgetRef ref) async {
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        const XTypeGroup(
          label: 'media',
          extensions: <String>[
            'mp3',
            'm4a',
            'aac',
            'wav',
            'flac',
            'ogg',
            'mp4',
            'mkv',
            'mov',
            'webm',
            'm4v',
          ],
        ),
      ],
    );
    if (file == null) return;
    final String? cached = await copyPickedMediaToCache(file.path, file.name);
    if (!context.mounted) return;
    await _openPath(
      context,
      ref,
      title: file.name,
      path: cached ?? file.path,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    final List<({LibraryCourseData course, LibraryEpisodeItem ep})> playable =
        <({LibraryCourseData course, LibraryEpisodeItem ep})>[];
    for (final LibraryCourseData c in courses) {
      for (final LibraryEpisodeItem e in c.episodes) {
        final String? asset = e.videoAsset;
        if (asset == null || asset.isEmpty || e.videoMissing) continue;
        playable.add((course: c, ep: e));
      }
    }

    return ModuleGate(
      moduleCode: 'video',
      title: '视频模块',
      softBrowse: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('磨耳朵')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            Text(
              '导入音频/视频后循环磨耳朵；息屏或锁屏只播声音，不中断。',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '也可从视频区导入片库后再来这里听。',
              style: TextStyle(color: Theme.of(context).hintColor, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _pickLocal(context, ref),
              icon: const Icon(Icons.library_music_outlined),
              label: const Text('导入音频 / 视频开听'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/importCourse'),
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('去视频区导入课程'),
            ),
            TextButton(
              onPressed: () => context.push('/learn/listening'),
              child: const Text('短句磨耳朵课（入门）'),
            ),
            const SizedBox(height: 20),
            Text(
              '片库可听',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            if (playable.isEmpty)
              const Text('暂无已下载媒体。先导入视频或音频。')
            else
              for (final ({LibraryCourseData course, LibraryEpisodeItem ep}) item
                  in playable.take(40))
                Card(
                  child: ListTile(
                    title: Text(item.ep.title),
                    subtitle: Text(item.course.title),
                    trailing: const Icon(Icons.headphones),
                    onTap: () => _openPath(
                      context,
                      ref,
                      title: item.ep.title,
                      path: item.ep.videoAsset!,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
