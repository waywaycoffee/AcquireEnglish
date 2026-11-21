import 'package:common_learn_english/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolvedLevel maps ability ids', () {
    expect(
      const OnboardingProfile(abilityId: 'beginner').resolvedLevel,
      '零基础',
    );
    expect(const OnboardingProfile(abilityId: 'daily').resolvedLevel, 'B1');
    expect(const OnboardingProfile(abilityId: 'unsure').resolvedLevel, 'A2');
    expect(const OnboardingProfile().resolvedLevel, 'A2');
  });

  test('primary and other modes + warm-up routes', () {
    const OnboardingProfile profile = OnboardingProfile(
      modeIds: <String>['video', 'oral', 'vocab'],
      primaryModeId: 'oral',
      canSyllableSplit: false,
      learnedPhonics: false,
    );
    expect(profile.primaryMode?.id, 'oral');
    expect(
      profile.otherModes.map((OnboardingMode m) => m.id).toList(),
      <String>['video', 'vocab'],
    );
    expect(profile.warmUpRoutes, <String>['/learn/ipa', '/learn/phonics']);
  });

  test('copyWith can clear primaryModeId', () {
    const OnboardingProfile profile = OnboardingProfile(
      modeIds: <String>['reading'],
      primaryModeId: 'reading',
    );
    final OnboardingProfile cleared = profile.copyWith(primaryModeId: null);
    expect(cleared.primaryModeId, isNull);
    expect(cleared.modeIds, <String>['reading']);
  });

  test('json round-trip', () {
    const OnboardingProfile original = OnboardingProfile(
      interestIds: <String>['travel', 'tech'],
      ageBandId: 'college',
      modeIds: <String>['reading', 'vocab'],
      primaryModeId: 'reading',
      abilityId: 'words',
      canSyllableSplit: true,
      learnedPhonics: false,
      completed: true,
    );
    final OnboardingProfile restored = OnboardingProfile.fromJson(
      original.toJson(),
    );
    expect(restored.interestIds, original.interestIds);
    expect(restored.ageBandId, 'college');
    expect(restored.primaryModeId, 'reading');
    expect(restored.abilityId, 'words');
    expect(restored.canSyllableSplit, isTrue);
    expect(restored.learnedPhonics, isFalse);
    expect(restored.completed, isTrue);
  });
}
