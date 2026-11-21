import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/endpoints.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../words/domain/foundation_media.dart';

/// ECS-hosted reading audio/video manifest (never packaged in the APK).
final FutureProvider<FoundationMediaManifest> readingContentMediaProvider =
    FutureProvider<FoundationMediaManifest>((Ref ref) async {
      try {
        final FoundationMediaManifest raw = await ref
            .read(acquireApiClientProvider)
            .contentMediaManifest(namespace: 'reading');
        final String apiBase = Endpoints.normalizeBaseUrl(
          ref.read(learningSettingsProvider).resolvedCloudApiBaseUrl,
        );
        return raw.withResolvedUrls(apiBase);
      } catch (_) {
        return FoundationMediaManifest.empty;
      }
    });

/// Resolve accompanying media for a reading doc id / slug via ECS.
FoundationMediaItem? readingMediaForDoc(
  FoundationMediaManifest manifest,
  String docIdOrSlug,
) {
  final String key = docIdOrSlug.trim();
  if (key.isEmpty) return null;
  for (final String pack in const <String>[
    'reading',
    'onestop',
    'magic',
    'cefr',
    'standard_ebooks',
  ]) {
    final FoundationMediaItem? hit = manifest.lookup(pack, key);
    if (hit != null) return hit;
  }
  // Fall back: match any pack whose key equals the slug (after last colon).
  final String slug = key.contains(':') ? key.split(':').last : key;
  final String wantSlug = FoundationMediaManifest.normKey(slug);
  final String wantKey = FoundationMediaManifest.normKey(key);
  for (final FoundationMediaItem item in manifest.items) {
    final String itemKey = FoundationMediaManifest.normKey(item.key);
    if (itemKey == wantSlug || itemKey == wantKey) return item;
  }
  return null;
}
