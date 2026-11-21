import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/community_models.dart';

final AsyncNotifierProvider<CommunityFeedNotifier, List<CommunityPostDto>>
communityFeedProvider =
    AsyncNotifierProvider<CommunityFeedNotifier, List<CommunityPostDto>>(
      CommunityFeedNotifier.new,
    );

final communityPostUpdatesProvider =
    NotifierProvider<CommunityPostUpdates, Map<int, CommunityPostDto>>(
      CommunityPostUpdates.new,
    );

class CommunityPostUpdates extends Notifier<Map<int, CommunityPostDto>> {
  @override
  Map<int, CommunityPostDto> build() {
    ref.watch(authSessionProvider);
    return <int, CommunityPostDto>{};
  }

  void put(CommunityPostDto post) =>
      state = <int, CommunityPostDto>{...state, post.id: post};
}

class CommunityFeedNotifier extends AsyncNotifier<List<CommunityPostDto>> {
  bool _loadingMore = false;
  bool hasMore = true;
  Future<void> loadMore() async {
    if (_loadingMore || !hasMore) return;
    final List<CommunityPostDto> current =
        state.asData?.value ?? <CommunityPostDto>[];
    if (current.isEmpty) return;
    _loadingMore = true;
    final String token = ref.read(authSessionProvider).accessToken;
    try {
      final List<CommunityPostDto> more = await ref
          .read(acquireApiClientProvider)
          .communityFeed(before: current.last.id);
      if (!ref.mounted || token != ref.read(authSessionProvider).accessToken)
        return;
      hasMore = more.length == 40;
      final List<CommunityPostDto> latest = state.asData?.value ?? current;
      final Set<int> ids = latest.map((CommunityPostDto p) => p.id).toSet();
      state = AsyncData<List<CommunityPostDto>>(<CommunityPostDto>[
        ...latest,
        ...more.where((CommunityPostDto p) => !ids.contains(p.id)),
      ]);
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Future<List<CommunityPostDto>> build() async {
    ref.watch(authSessionProvider.select((AuthSessionState s) => s.isLoggedIn));
    return ref.read(acquireApiClientProvider).communityFeed();
  }

  Future<void> refresh() async {
    hasMore = true;
    state = const AsyncLoading<List<CommunityPostDto>>();
    state = await AsyncValue.guard(
      () => ref.read(acquireApiClientProvider).communityFeed(),
    );
  }

  Future<CommunityPostDto?> createPost({
    required String kind,
    String title = '',
    String body = '',
    String? linkUrl,
    String? linkTitle,
    String? embedWord,
    double? embedTimestampSec,
    String? oralAudioUrl,
    String? oralBookId,
    String? oralKey,
    String? transcript,
    String? referenceLine,
    Map<String, dynamic>? meta,
  }) async {
    final CommunityPostDto post = await ref
        .read(acquireApiClientProvider)
        .createCommunityPost(
          kind: kind,
          title: title,
          body: body,
          linkUrl: linkUrl,
          linkTitle: linkTitle,
          embedWord: embedWord,
          embedTimestampSec: embedTimestampSec,
          oralAudioUrl: oralAudioUrl,
          oralBookId: oralBookId,
          oralKey: oralKey,
          transcript: transcript,
          referenceLine: referenceLine,
          meta: meta,
        );
    final List<CommunityPostDto> current =
        state.asData?.value ?? const <CommunityPostDto>[];
    state = AsyncData<List<CommunityPostDto>>(<CommunityPostDto>[
      post,
      ...current,
    ]);
    return post;
  }

  Future<void> toggleLike(int postId, {bool? enabled}) async {
    final CommunityPostDto updated = await ref
        .read(acquireApiClientProvider)
        .setCommunityLike(
          postId,
          enabled ??
              !(state.asData?.value
                      .where((CommunityPostDto p) => p.id == postId)
                      .firstOrNull
                      ?.likedByMe ??
                  false),
        );
    ref.read(communityPostUpdatesProvider.notifier).put(updated);
    final List<CommunityPostDto> current =
        state.asData?.value ?? const <CommunityPostDto>[];
    state = AsyncData<List<CommunityPostDto>>(
      current
          .map((CommunityPostDto p) => p.id == postId ? updated : p)
          .toList(growable: false),
    );
  }
}

final NotifierProvider<CommunityLeaderboardMetricNotifier, String>
communityLeaderboardMetricProvider =
    NotifierProvider<CommunityLeaderboardMetricNotifier, String>(
      CommunityLeaderboardMetricNotifier.new,
    );

class CommunityLeaderboardMetricNotifier extends Notifier<String> {
  @override
  String build() => 'study_week';

  void setMetric(String metric) => state = metric;
}

final AsyncNotifierProvider<
  CommunityLeaderboardNotifier,
  List<LeaderboardEntryDto>
>
communityLeaderboardProvider =
    AsyncNotifierProvider<
      CommunityLeaderboardNotifier,
      List<LeaderboardEntryDto>
    >(CommunityLeaderboardNotifier.new);

class CommunityLeaderboardNotifier
    extends AsyncNotifier<List<LeaderboardEntryDto>> {
  @override
  Future<List<LeaderboardEntryDto>> build() async {
    final String metric = ref.watch(communityLeaderboardMetricProvider);
    if (!ref.watch(authSessionProvider).isLoggedIn) {
      return const <LeaderboardEntryDto>[];
    }
    return ref
        .read(acquireApiClientProvider)
        .communityLeaderboard(metric: metric);
  }

  Future<void> setMetric(String metric) async {
    ref.read(communityLeaderboardMetricProvider.notifier).setMetric(metric);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<LeaderboardEntryDto>>();
    state = await AsyncValue.guard(build);
  }
}

final AsyncNotifierProvider<CommunityPeopleNotifier, CommunityPeopleBundle>
communityPeopleProvider =
    AsyncNotifierProvider<CommunityPeopleNotifier, CommunityPeopleBundle>(
      CommunityPeopleNotifier.new,
    );

class CommunityPeopleBundle {
  const CommunityPeopleBundle({
    required this.similar,
    required this.profile,
    required this.challenges,
  });

  final List<SimilarUserDto> similar;
  final CommunityProfileDto? profile;
  final List<VocabPkDto> challenges;
}

class CommunityPeopleNotifier extends AsyncNotifier<CommunityPeopleBundle> {
  @override
  Future<CommunityPeopleBundle> build() async {
    if (!ref.watch(authSessionProvider).isLoggedIn) {
      return const CommunityPeopleBundle(
        similar: <SimilarUserDto>[],
        profile: null,
        challenges: <VocabPkDto>[],
      );
    }
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    final List<SimilarUserDto> similar = await api.communitySimilarUsers();
    final CommunityProfileDto profile = await api.getCommunityProfile();
    final List<VocabPkDto> challenges = await api.myVocabPkChallenges();
    return CommunityPeopleBundle(
      similar: similar,
      profile: profile,
      challenges: challenges,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading<CommunityPeopleBundle>();
    state = await AsyncValue.guard(build);
  }

  Future<void> setLookingForPartner(bool value) async {
    final CommunityProfileDto updated = await ref
        .read(acquireApiClientProvider)
        .updateCommunityProfile(lookingForPartner: value);
    final CommunityPeopleBundle? current = state.asData?.value;
    if (current == null) return;
    state = AsyncData<CommunityPeopleBundle>(
      CommunityPeopleBundle(
        similar: current.similar,
        profile: updated,
        challenges: current.challenges,
      ),
    );
  }

  Future<VocabPkDto> challenge(int opponentId) async {
    final VocabPkDto pk = await ref
        .read(acquireApiClientProvider)
        .createVocabPk(opponentId: opponentId);
    await refresh();
    return pk;
  }

  Future<VocabPkDto> accept(int challengeId) async {
    final VocabPkDto pk = await ref
        .read(acquireApiClientProvider)
        .acceptVocabPk(challengeId);
    await refresh();
    return pk;
  }
}

final AsyncNotifierProvider<CommunityHotNotifier, CommunityHotBundle>
communityHotProvider =
    AsyncNotifierProvider<CommunityHotNotifier, CommunityHotBundle>(
      CommunityHotNotifier.new,
    );

class CommunityHotBundle {
  const CommunityHotBundle({required this.shares, required this.creators});

  final List<HotShareDto> shares;
  final List<HotCreatorDto> creators;
}

class CommunityHotNotifier extends AsyncNotifier<CommunityHotBundle> {
  @override
  Future<CommunityHotBundle> build() async {
    ref.watch(authSessionProvider.select((AuthSessionState s) => s.isLoggedIn));
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    return CommunityHotBundle(
      shares: await api.communityHotShares(),
      creators: await api.communityHotCreators(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading<CommunityHotBundle>();
    state = await AsyncValue.guard(build);
  }
}
