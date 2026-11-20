import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/endpoints.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/foundation_media.dart';

final FutureProvider<FoundationMediaManifest> foundationMediaManifestProvider =
    FutureProvider<FoundationMediaManifest>((Ref ref) async {
      try {
        final FoundationMediaManifest raw =
            await ref.read(acquireApiClientProvider).foundationMediaManifest();
        final String apiBase = Endpoints.normalizeBaseUrl(
          ref.read(learningSettingsProvider).resolvedCloudApiBaseUrl,
        );
        return raw.withResolvedUrls(apiBase);
      } catch (_) {
        return FoundationMediaManifest.empty;
      }
    });

/// Resolves remote demo media for a syllabus review key `syllabus:{book}:{word}`.
FoundationMediaItem? foundationMediaForReviewKey(
  FoundationMediaManifest manifest,
  String reviewKey,
) {
  if (!reviewKey.startsWith('syllabus:')) return null;
  final List<String> parts = reviewKey.split(':');
  if (parts.length < 3) return null;
  final String bookId = parts[1];
  final String word = parts.sublist(2).join(':');
  return manifest.lookup(bookId, word);
}
