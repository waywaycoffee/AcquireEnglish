import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../player/presentation/player_subtitle_loader.dart';
import '../../player/presentation/player_mock_state.dart';
import '../../player/presentation/subtitle_file_persist.dart';
import '../../player/presentation/widgets/study_bottom_controls.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../reading/presentation/reading_text_spans.dart';

import '../../sync/data/acquire_api_client.dart';
import '../../import_course/domain/youtube_import.dart';
import '../../subtitle_completion/shared_bilibili_subtitle_sync.dart';

typedef _Occurrence = ({String title, String sentence, Uri destination});

Future<void> showWordOccurrences(
  BuildContext context,
  WidgetRef ref,
  String word,
) async {
  final courses = ref.read(libraryCatalogProvider);
  final reading = ref.read(readingLibraryProvider);
  final api = ref.read(acquireApiClientProvider);
  final pattern = RegExp(
    r"(?<![A-Za-z0-9'])" + RegExp.escape(word.trim()) + r"(?![A-Za-z0-9'])",
    caseSensitive: false,
  );

  Future<List<_Occurrence>> scan() async {
    final hits = <_Occurrence>[];
    Future<List<PersonalImportAsset>>? personal;
    Future<List<PersonalImportAsset>> loadPersonal() async {
      try {
        return await api.listPersonalImports().timeout(const Duration(seconds: 6));
      } catch (_) {
        return const [];
      }
    }

    for (final course in courses) {
      for (final episode in course.episodes) {
        if (!episode.completed &&
            episode.progressPercent <= 0 &&
            (episode.progressTimeStr?.isEmpty ?? true) &&
            (episode.lastWatchedStr?.isEmpty ?? true)) {
          continue;
        }
        try {
          final track = episode.enSubtitleAsset;
          var lines = <PlayerSubtitleLine>[];
          if (track != null && track.isNotEmpty) {
            try {
              lines = await loadSubtitleLines(track);
            } catch (_) {}
          }
          if (lines.isEmpty) {
            lines = (await loadAsrSentenceSubtitles(episodeId: episode.id))
                ?.sentenceLines ?? [];
          }
          if (lines.isEmpty) {
            final youtube = course.id.startsWith('youtube-')
                ? YoutubeImport.extractVideoId(episode.sourceUrl ?? '') : null;
            final bili = resolveBilibiliSharedSubtitleIds(
              course: course, episode: episode, sourceUrl: episode.sourceUrl,
            );
            if (youtube != null || bili != null) {
              final assets = await (personal ??= loadPersonal());
              final asset = assets.where((asset) => asset.hasEn &&
                  (youtube != null
                      ? asset.source == 'youtube' && asset.externalId == youtube
                      : asset.source == 'bilibili' &&
                        (asset.externalId == '${bili!.bvid}-p${bili.page}' ||
                         (bili.page == 1 && asset.externalId == bili.bvid)))).firstOrNull;
              final raw = asset == null ? null :
                  await api.fetchPersonalImportSrt(importId: asset.id, lang: 'en');
              if (raw != null) lines = parseSubtitleLines(raw);
              if (lines.isEmpty && bili != null) {
                final pack = await api.getSharedBilibiliSubtitle(bvid: bili.bvid, page: bili.page);
                if (pack != null) lines = parseSubtitleLines(pack.subtitleEnSrt);
              }
            }
          }
          for (final line in lines) {
            if (!pattern.hasMatch(line.english)) continue;
            final time = StudyBottomControls.formatClock(
              Duration(milliseconds: line.startMs),
            );
            hits.add((
              title: '${course.title} · ${episode.title} · $time',
              sentence: line.english,
              destination: Uri(
                pathSegments: ['', 'episodes', episode.id],
                queryParameters: {'startTime': time},
              ),
            ));
          }
        } catch (_) {
          // Missing media on this device does not prevent other hits.
        }
      }
    }
    for (final doc in reading.all) {
      if (reading.progressFor(doc.id) == null) continue;
      final seen = <int>{};
      for (final match in pattern.allMatches(doc.plainText)) {
        final sentence = sentenceBounds(doc.plainText, match.start, match.end);
        if (!seen.add(sentence.start)) continue;
        hits.add((
          title: doc.displayTitle,
          sentence: sentence.text,
          destination: Uri(
            pathSegments: ['', 'reading', doc.id],
            queryParameters: {'offset': '${match.start}'},
          ),
        ));
      }
    }
    return hits;
  }

  final future = scan();
  final target = await showModalBottomSheet<Uri>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .75,
        child: Column(
          children: [
            ListTile(title: Text('$word · 已学语境')),
            Expanded(
              child: FutureBuilder<List<_Occurrence>>(
                future: future,
                builder: (_, snapshot) {
                  if (snapshot.hasError)
                    return const Center(child: Text('语境读取失败'));
                  final hits = snapshot.data;
                  if (hits == null)
                    return const Center(child: CircularProgressIndicator());
                  if (hits.isEmpty)
                    return const Center(child: Text('已学素材中暂无匹配'));
                  return ListView.builder(
                    itemCount: hits.length,
                    itemBuilder: (_, index) {
                      final hit = hits[index];
                      return ListTile(
                        title: Text(hit.sentence),
                        subtitle: Text(hit.title),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            Navigator.pop(sheetContext, hit.destination),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (target != null && context.mounted) context.push(target.toString());
}
