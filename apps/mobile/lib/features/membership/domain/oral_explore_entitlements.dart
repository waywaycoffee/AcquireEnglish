import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';

/// Feature flags for 口语入门探索版 (and free defaults).
class OralExploreFeatures {
  const OralExploreFeatures({
    this.customDigitalHuman = true,
    this.voiceClone = false,
    this.hdExport = false,
    this.teamCollab = false,
    this.baseAvatar = true,
    this.maxResolution = '720p',
    this.rag = true,
    this.podcast = true,
    this.tier = 'free',
  });

  final bool customDigitalHuman;
  final bool voiceClone;
  final bool hdExport;
  final bool teamCollab;
  final bool baseAvatar;
  final String maxResolution;
  final bool rag;
  final bool podcast;
  final String tier;

  factory OralExploreFeatures.fromJson(Map<String, dynamic>? json) {
    final Map<String, dynamic> map = json ?? const <String, dynamic>{};
    return OralExploreFeatures(
      customDigitalHuman: map['custom_digital_human'] as bool? ?? true,
      voiceClone: map['voice_clone'] as bool? ?? false,
      hdExport: map['hd_export'] as bool? ?? false,
      teamCollab: map['team_collab'] as bool? ?? false,
      baseAvatar: map['base_avatar'] as bool? ?? true,
      maxResolution: '${map['max_resolution'] ?? '720p'}',
      rag: map['rag'] as bool? ?? true,
      podcast: map['podcast'] as bool? ?? true,
      tier: '${map['tier'] ?? 'free'}',
    );
  }

  bool get allowsHdAbove720 =>
      hdExport || maxResolution.toLowerCase().contains('1080');
}

class OralDocLibraryLimits {
  const OralDocLibraryLimits({
    this.limit = 5,
    this.maxMb = 20,
    this.tier = 'free',
  });

  final int limit;
  final int maxMb;
  final String tier;

  int get maxBytes => maxMb * 1024 * 1024;

  factory OralDocLibraryLimits.fromJson(Map<String, dynamic>? json) {
    final Map<String, dynamic> map = json ?? const <String, dynamic>{};
    return OralDocLibraryLimits(
      limit: (map['limit'] as num?)?.toInt() ?? 5,
      maxMb: (map['max_mb'] as num?)?.toInt() ?? 20,
      tier: '${map['tier'] ?? 'free'}',
    );
  }
}

class OralExploreSnapshot {
  const OralExploreSnapshot({
    required this.features,
    required this.docLibraries,
    this.duplexRemaining,
    this.duplexLimit,
    this.duplexExhausted = false,
  });

  final OralExploreFeatures features;
  final OralDocLibraryLimits docLibraries;
  final int? duplexRemaining;
  final int? duplexLimit;
  final bool duplexExhausted;
}

final oralExploreSnapshotProvider =
    FutureProvider<OralExploreSnapshot>((Ref ref) async {
  if (!ref.watch(authSessionProvider).isLoggedIn) {
    return const OralExploreSnapshot(
      features: OralExploreFeatures(),
      docLibraries: OralDocLibraryLimits(),
      duplexRemaining: 5,
      duplexLimit: 5,
    );
  }
  final AcquireApiClient api = ref.read(acquireApiClientProvider);
  Map<String, dynamic> quotas = <String, dynamic>{};
  Map<String, dynamic> ents = <String, dynamic>{};
  try {
    quotas = await api.commerceQuotas(moduleCode: 'digital_human');
  } catch (_) {}
  try {
    ents = await api.commerceEntitlements();
  } catch (_) {}

  final Map<String, dynamic>? featuresJson =
      (quotas['features'] as Map?)?.cast<String, dynamic>() ??
          (ents['features'] as Map?)?.cast<String, dynamic>();
  final Map<String, dynamic>? docsJson =
      (quotas['doc_libraries'] as Map?)?.cast<String, dynamic>() ??
          (ents['doc_libraries'] as Map?)?.cast<String, dynamic>();

  int? remaining;
  int? limit;
  bool exhausted = false;
  final Object? items = quotas['items'];
  if (items is List) {
    for (final Object? raw in items) {
      if (raw is! Map) continue;
      if ('${raw['metric']}' != 'duplex_minutes') continue;
      remaining = (raw['remaining'] as num?)?.toInt();
      limit = (raw['limit'] as num?)?.toInt();
      exhausted = raw['exhausted'] == true || (remaining ?? 1) <= 0;
      break;
    }
  }

  return OralExploreSnapshot(
    features: OralExploreFeatures.fromJson(featuresJson),
    docLibraries: OralDocLibraryLimits.fromJson(docsJson),
    duplexRemaining: remaining,
    duplexLimit: limit,
    duplexExhausted: exhausted,
  );
});
