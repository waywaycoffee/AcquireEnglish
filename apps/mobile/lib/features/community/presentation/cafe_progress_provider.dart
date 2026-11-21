import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/cafe_adventure.dart';

class CafeProgress {
  const CafeProgress({
    required this.profile,
    required this.completed,
    required this.weekLevels,
    this.peerWeekCount,
    this.together = false,
  });

  final String profile;
  final Set<int> completed;
  final Set<int> weekLevels;
  final int? peerWeekCount;
  final bool together;

  int get clearedCount => completed.length;
  int get nodeCount => kCafeLevels.length;
  int get weekCount => weekLevels.length;
  int get weekTarget => kCafeWeeklyTarget;

  int get nextIndex {
    for (int i = 0; i < kCafeLevels.length; i++) {
      if (!completed.contains(i)) return i;
    }
    return kCafeLevels.length - 1;
  }

  String get nextTitle => kCafeLevels[nextIndex].title;
  String get stageLabel =>
      clearedCount >= nodeCount ? '本章已通关 · 可重练' : '当前关卡 · $nextTitle';
  String get progressLabel => '$clearedCount / $nodeCount 站';
  String get weekLabel => '本周有效练习 $weekCount / $weekTarget';

  String partnerLabel({required bool hasPeer, String? peerName}) {
    if (!hasPeer) return '同桌加分（可选）· 去学习桌邀请';
    final String name = (peerName ?? '搭子').trim();
    final int peer = peerWeekCount ?? 0;
    if (together) return '已一起完成本周 · $name';
    return '同桌本周 $name · 我 $weekCount/$weekTarget · 对方 $peer/$weekTarget';
  }
}

class CafeProgressNotifier extends AsyncNotifier<CafeProgress> {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  String _profile() {
    final AuthSessionState session = ref.read(authSessionProvider);
    return session.isLoggedIn ? 'account:${session.email}' : 'guest';
  }

  String _doneKey(String profile, int index) =>
      'community.exploration.cafe.v1.$profile.$index';

  String _weekKey(String profile, String week) =>
      'community.exploration.cafe.week.v1.$profile.$week';

  @override
  Future<CafeProgress> build() async {
    ref.watch(authSessionProvider.select((AuthSessionState s) => s.email));
    return _load();
  }

  Future<CafeProgress> _load() async {
    final String profile = _profile();
    final String week = cafeWeekId();
    final List<bool?> flags = await Future.wait(<Future<bool?>>[
      for (int i = 0; i < kCafeLevels.length; i++) _prefs.getBool(_doneKey(profile, i)),
    ]);
    final Set<int> completed = <int>{
      for (int i = 0; i < flags.length; i++)
        if (flags[i] == true) i,
    };
    final List<String> weekRaw =
        await _prefs.getStringList(_weekKey(profile, week)) ?? <String>[];
    final Set<int> weekLevels = <int>{
      for (final String s in weekRaw)
        if (int.tryParse(s) != null) int.parse(s),
    };

    int? peerWeek;
    bool together = false;
    final AuthSessionState session = ref.read(authSessionProvider);
    if (session.isLoggedIn) {
      try {
        final Map<String, dynamic> remote = await ref
            .read(acquireApiClientProvider)
            .studyDeskRequest(
              'GET',
              '/weekly-quest',
              query: <String, dynamic>{'chapter': 'cafe'},
            );
        peerWeek = (remote['peer_count'] as num?)?.toInt();
        together = remote['together'] == true;
        final int remoteMe = (remote['me_count'] as num?)?.toInt() ?? 0;
        // Prefer union of local + server unique levels when server returns levels.
        final Object? levels = remote['me_levels'];
        if (levels is List) {
          for (final Object? item in levels) {
            final int? n = item is num ? item.toInt() : int.tryParse('$item');
            if (n != null) weekLevels.add(n);
          }
        } else if (remoteMe > weekLevels.length) {
          // Server ahead but no detail — keep local, show at least remote count via pad.
          while (weekLevels.length < remoteMe && weekLevels.length < kCafeLevels.length) {
            weekLevels.add(weekLevels.length);
          }
        }
      } catch (_) {
        // Offline / no desk — local progress still works.
      }
    }

    return CafeProgress(
      profile: profile,
      completed: completed,
      weekLevels: weekLevels,
      peerWeekCount: peerWeek,
      together: together,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading<CafeProgress>();
    state = AsyncData<CafeProgress>(await _load());
  }

  Future<void> markLevelComplete(int index) async {
    if (index < 0 || index >= kCafeLevels.length) return;
    final String profile = _profile();
    final String week = cafeWeekId();
    await _prefs.setBool(_doneKey(profile, index), true);
    final CafeProgress current = state.asData?.value ?? await _load();
    final Set<int> weekLevels = Set<int>.of(current.weekLevels)..add(index);
    await _prefs.setStringList(
      _weekKey(profile, week),
      weekLevels.map((int i) => '$i').toList(growable: false),
    );

    final AuthSessionState session = ref.read(authSessionProvider);
    if (session.isLoggedIn) {
      try {
        await ref.read(acquireApiClientProvider).studyDeskRequest(
              'POST',
              '/weekly-quest',
              data: <String, dynamic>{
                'chapter': 'cafe',
                'level': index,
              },
            );
      } catch (_) {}
    }
    state = AsyncData<CafeProgress>(await _load());
  }
}

final AsyncNotifierProvider<CafeProgressNotifier, CafeProgress>
    cafeProgressProvider =
    AsyncNotifierProvider<CafeProgressNotifier, CafeProgress>(
  CafeProgressNotifier.new,
);
