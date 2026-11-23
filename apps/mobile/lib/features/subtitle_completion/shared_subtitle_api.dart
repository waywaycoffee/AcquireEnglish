import '../sync/data/acquire_api_client.dart';

AcquireApiClient? _configuredSharedSubtitleApi;

void configureSharedBilibiliSubtitleApi(AcquireApiClient? api) {
  _configuredSharedSubtitleApi = api;
}

AcquireApiClient? resolveSharedBilibiliSubtitleApi([
  AcquireApiClient? override,
]) => override ?? _configuredSharedSubtitleApi;

/// Push one Bilibili page to the ECS GPU subtitle queue.
///
/// Returns true when the API accepted (or already had) a durable job.
Future<bool> requestCloudSubtitleGeneration({
  required String bvid,
  int page = 1,
  AcquireApiClient? api,
}) async {
  final SharedSubtitleGpuJob? job = await requestCloudSubtitleGenerationJob(
    bvid: bvid,
    page: page,
    api: api,
  );
  return job != null;
}

/// Same as [requestCloudSubtitleGeneration] but returns the job for UI state.
Future<SharedSubtitleGpuJob?> requestCloudSubtitleGenerationJob({
  required String bvid,
  int page = 1,
  AcquireApiClient? api,
}) async {
  final AcquireApiClient? client = resolveSharedBilibiliSubtitleApi(api);
  if (client == null) {
    return null;
  }
  final String id = bvid.trim();
  if (id.isEmpty) {
    return null;
  }
  try {
    return await client.enqueueSharedSubtitleJob(
      bvid: id,
      page: page < 1 ? 1 : page,
    );
  } catch (_) {
    return null;
  }
}

/// English already on disk → push GPU EN→ZH (no Whisper).
Future<bool> requestCloudSubtitleTranslation({
  required String bvid,
  required String subtitleEnSrt,
  int page = 1,
  String? title,
  int? cid,
  int? durationSec,
  AcquireApiClient? api,
}) async {
  final AcquireApiClient? client = resolveSharedBilibiliSubtitleApi(api);
  if (client == null) {
    return false;
  }
  final String id = bvid.trim();
  if (id.isEmpty || subtitleEnSrt.trim().length < 20) {
    return false;
  }
  try {
    final SharedSubtitleGpuJob? job =
        await client.enqueueSharedSubtitleTranslateJob(
      bvid: id,
      page: page < 1 ? 1 : page,
      subtitleEnSrt: subtitleEnSrt,
      title: title,
      cid: cid,
      durationSec: durationSec,
    );
    return job != null;
  } catch (_) {
    return false;
  }
}
