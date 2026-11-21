import '../sync/data/acquire_api_client.dart';

AcquireApiClient? _configuredSharedSubtitleApi;

void configureSharedBilibiliSubtitleApi(AcquireApiClient? api) {
  _configuredSharedSubtitleApi = api;
}

AcquireApiClient? resolveSharedBilibiliSubtitleApi([
  AcquireApiClient? override,
]) => override ?? _configuredSharedSubtitleApi;

/// Cloud lookup and GPU enqueue run in parallel with the media download.
Future<void> requestSharedSubtitlesForDownload({
  required String bvid,
  required int page,
  int? cid,
}) async {
  try {
    await _configuredSharedSubtitleApi?.getSharedBilibiliSubtitle(
      bvid: bvid,
      page: page,
      cid: cid,
    );
  } catch (_) {
    // Offline cloud or expired login must not block the video download.
  }
}
