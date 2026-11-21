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
  final AcquireApiClient? client = resolveSharedBilibiliSubtitleApi(api);
  if (client == null) {
    return false;
  }
  final String id = bvid.trim();
  if (id.isEmpty) {
    return false;
  }
  try {
    final SharedSubtitleGpuJob? job = await client.enqueueSharedSubtitleJob(
      bvid: id,
      page: page < 1 ? 1 : page,
    );
    return job != null;
  } catch (_) {
    return false;
  }
}
