import 'bilibili_episode_prepare.dart';
import 'bilibili_import_service.dart';

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
  String? en = isUsableSubtitlePath(existingEnPath)
      ? existingEnPath!.trim()
      : null;
  String? zh = isUsableSubtitlePath(existingZhPath)
      ? existingZhPath!.trim()
      : null;
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
      if (isUsableSubtitlePath(fetchedEn)) {
        en = fetchedEn!.trim();
      }
      if (isUsableSubtitlePath(fetchedZh)) {
        zh = fetchedZh!.trim();
      }
    } catch (_) {}
  }

  en ??= await existingOfficialBilibiliSubtitle(
    idKey: sourceKey,
    fileName: 'en.srt',
  );
  zh ??= await existingOfficialBilibiliSubtitle(
    idKey: sourceKey,
    fileName: 'zh.srt',
  );

  return OfficialSoftsubs(enPath: en, zhPath: zh, note: note);
}
