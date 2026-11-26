import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../words/presentation/learner_level_provider.dart';
import '../data/learner_skill_profile_store.dart';
import '../domain/learner_skill_profile.dart';

final Provider<LearnerSkillProfileStore> learnerSkillProfileStoreProvider =
    Provider<LearnerSkillProfileStore>((Ref ref) {
      return LearnerSkillProfileStore(ref.watch(studyAccountProvider));
    });

final NotifierProvider<LearnerSkillProfileNotifier, LearnerSkillProfile>
learnerSkillProfileProvider =
    NotifierProvider<LearnerSkillProfileNotifier, LearnerSkillProfile>(
      LearnerSkillProfileNotifier.new,
    );

class LearnerSkillProfileNotifier extends Notifier<LearnerSkillProfile> {
  @override
  LearnerSkillProfile build() {
    final String prior = ref.watch(adaptiveLearnerCefrProvider);
    return ref
        .watch(learnerSkillProfileStoreProvider)
        .load(priorBand: prior);
  }

  Future<void> recordVocabProbe({
    required String lemma,
    required bool correct,
    DateTime? day,
  }) async {
    final String prior = ref.read(adaptiveLearnerCefrProvider);
    final LearnerSkillProfileStore store = ref.read(
      learnerSkillProfileStoreProvider,
    );
    final SkillEstimate vocab = state.estimate(LearnerSkill.vocab);
    final LearnerSkillProfile next = await store.recordProbe(
      attempt: ProbeAttempt(
        skill: LearnerSkill.vocab,
        itemId: lemma.trim().toLowerCase(),
        band: vocab.band,
        day: day ?? DateTime.now(),
        correct: correct,
      ),
      priorBand: prior,
    );
    state = next;
  }
}
