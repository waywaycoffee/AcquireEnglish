import 'bilibili_episode_prepare.dart';
import 'bilibili_import_service.dart';
import 'bilibili_multipage.dart';

/// Official softsub paths for one episode (disk and/or freshly fetched).
class OfficialSoftsubs {
  const OfficialSoftsubs({this.enPath, this.zhPath, this.note});

  final String? enPath;
  final String? zhPath;
  final String? note;

  bool get hasEnglish => isUsableSubtitlePath(enPath);
  bool get hasChinese => isUsableSubtitlePath(zhPath);
  bool get hasAny => hasEnglish || hasChinese;
}

/// Prefer B站 official softsubs over ASR: network-fetch when possible, then
/// fall back to files already under `Documents/bilibili/<key>/`.
///
/// Call this on import enqueue and before Whisper/translate so we never burn
/// compute when softsubs already exist on the platform or disk.
Future<OfficialSoftsubs> ensureOfficialSoftsubs({
  String? sourceUrl,
  String? sourceKey,
  String? bilibiliCookieHeader,
  String? existingEnPath,
  String? existingZhPath,
  bool networkFetch = true,
  BilibiliImportService? service,
}) async {
  // Strip foreign / unscoped existing paths so a poisoned catalog never
  // skips the correct page fetch (合集串台 vector).
  String? en = acceptEpisodeSubtitlePath(
    path: existingEnPath,
    sourceUrl: sourceUrl,
    sourceKey: sourceKey,
  );
  String? zh = acceptEpisodeSubtitlePath(
    path: existingZhPath,
    sourceUrl: sourceUrl,
    sourceKey: sourceKey,
  );
  String? note;

  final String source = (sourceUrl ?? '').trim();
  final bool needNetwork =
      networkFetch &&
      source.isNotEmpty &&
      (!isUsableSubtitlePath(en) || !isUsableSubtitlePath(zh));

  if (needNetwork) {
    try {
      final BilibiliImportService client =
          service ?? BilibiliImportService.withCookie(bilibiliCookieHeader);
      final Map<String, String?> tracks = await client
          .fetchOfficialSubtitleTracks(source);
      final String? fetchedEn = tracks['en'];
      final String? fetchedZh = tracks['zh'];
      note = tracks['note'];
      en = acceptEpisodeSubtitlePath(
            path: fetchedEn,
            sourceUrl: source,
            sourceKey: sourceKey,
          ) ??
          en;
      zh = acceptEpisodeSubtitlePath(
            path: fetchedZh,
            sourceUrl: source,
            sourceKey: sourceKey,
          ) ??
          zh;
    } catch (_) {}
  }

  en ??= acceptEpisodeSubtitlePath(
    path: await existingOfficialBilibiliSubtitle(
      idKey: sourceKey,
      fileName: 'en.srt',
    ),
    sourceUrl: sourceUrl,
    sourceKey: sourceKey,
  );
  zh ??= acceptEpisodeSubtitlePath(
    path: await existingOfficialBilibiliSubtitle(
      idKey: sourceKey,
      fileName: 'zh.srt',
    ),
    sourceUrl: sourceUrl,
    sourceKey: sourceKey,
  );

  return OfficialSoftsubs(enPath: en, zhPath: zh, note: note);
}
