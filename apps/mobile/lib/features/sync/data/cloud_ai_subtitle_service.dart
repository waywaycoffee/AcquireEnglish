import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'acquire_api_client.dart';

final Provider<CloudAiSubtitleService> cloudAiSubtitleServiceProvider =
    Provider<CloudAiSubtitleService>((Ref ref) {
      return CloudAiSubtitleService(ref.watch(acquireApiClientProvider));
    });

/// Server-side AI subtitles (same path as the website: extract audio → DashScope → SRT).
class CloudAiSubtitleService {
  CloudAiSubtitleService(this._api);

  final AcquireApiClient _api;

  bool get isAuthenticated => _api.hasAuthorization;

  /// Ensure the watch URL exists as a link-course, run ASR, return English SRT text.
  Future<String> generateEnglishSrt({
    required String watchUrl,
    String? existingLinkCourseId,
    String? asrApiKey,
    int? maxSeconds,
  }) async {
    if (!isAuthenticated) {
      throw StateError('请先登录 AcquireEnglish 账号，才能使用云端 AI 字幕。');
    }
    if (asrApiKey != null && asrApiKey.trim().isNotEmpty) {
      await _api.ensureAsrApiKey(asrApiKey.trim());
    }

    int importId;
    final String? existing = existingLinkCourseId;
    if (existing != null && existing.startsWith('link-')) {
      importId = int.parse(existing.substring('link-'.length));
    } else {
      final AcquireCourseDto imported = await _api.importLink(watchUrl);
      final String id = imported.id;
      if (!id.startsWith('link-')) {
        throw StateError('云端导入返回了意外的课程 ID：$id');
      }
      importId = int.parse(id.substring('link-'.length));
    }

    final AcquireCourseDto course = await _api.generateSubtitles(
      importId: importId,
      language: 'en',
      maxSeconds: maxSeconds,
    );
    final String enPath = course.lessons.isEmpty
        ? ''
        : course.lessons.first.subtitleEn;
    if (enPath.isEmpty) {
      throw StateError('云端未返回英文字幕');
    }
    return _api.fetchText(enPath);
  }
}
