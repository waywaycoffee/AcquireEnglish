import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../domain/onboarding_profile.dart';

const String kOnboardingProfileKey = 'onboarding_profile_v1';
const String kOnboardingCompleteKey = 'onboarding_complete_v1';

bool readOnboardingCompletedSync() {
  if (!Hive.isBoxOpen('prefs')) return false;
  final Box<String> box = Hive.box<String>('prefs');
  if (box.get(kOnboardingCompleteKey) == '1') return true;
  // Upgrade path: installs that already saved prefs are past first-open.
  final String? legacyPrefs = box.get('learning_preferences_v1');
  return legacyPrefs != null && legacyPrefs.isNotEmpty;
}

class OnboardingNotifier extends Notifier<OnboardingProfile> {
  @override
  OnboardingProfile build() {
    if (!Hive.isBoxOpen('prefs')) return const OnboardingProfile();
    final String? raw = Hive.box<String>('prefs').get(kOnboardingProfileKey);
    if (raw == null || raw.isEmpty) return const OnboardingProfile();
    try {
      return OnboardingProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const OnboardingProfile();
    }
  }

  Future<void> _persist(OnboardingProfile profile) async {
    state = profile;
    if (!Hive.isBoxOpen('prefs')) return;
    final Box<String> box = Hive.box<String>('prefs');
    await box.put(kOnboardingProfileKey, jsonEncode(profile.toJson()));
    if (profile.completed) {
      await box.put(kOnboardingCompleteKey, '1');
    }
  }

  Future<void> update(OnboardingProfile Function(OnboardingProfile) fn) async {
    await _persist(fn(state));
  }

  Future<void> setFocus(String focusId) async {
    await _persist(state.copyWith(focusId: focusId));
    final AcquirePreferencesDto current = ref.read(learningPreferencesProvider);
    await ref.read(learningPreferencesProvider.notifier).save(
          current.copyWith(
            tags: prefsTagsForProfile(
              interestIds: state.interestIds.isEmpty
                  ? current.tags
                      .where(
                        (String t) => kOnboardingInterests.any(
                          (OnboardingInterest i) => i.id == t,
                        ),
                      )
                      .toList(growable: false)
                  : state.interestIds,
              ageBandId: state.ageBandId,
              focusId: focusId,
              keepTags: current.tags,
            ),
          ),
        );
  }

  Future<void> completeAndApply() async {
    final OnboardingProfile done = state.copyWith(completed: true);
    await _persist(done);

    final AcquirePreferencesDto current = ref.read(learningPreferencesProvider);
    await ref.read(learningPreferencesProvider.notifier).save(
          current.copyWith(
            level: done.resolvedLevel,
            tags: prefsTagsForProfile(
              interestIds: done.interestIds,
              ageBandId: done.ageBandId,
              focusId: done.focusId,
              keepTags: current.tags,
            ),
          ),
        );
  }

  Future<void> skipForNow() async {
    await _persist(state.copyWith(completed: true, focusId: null));
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(kOnboardingCompleteKey, '1');
    }
  }
}

final NotifierProvider<OnboardingNotifier, OnboardingProfile>
    onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingProfile>(
  OnboardingNotifier.new,
);
