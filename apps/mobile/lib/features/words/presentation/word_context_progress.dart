import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../daily_review/data/word_encounter_store.dart';
import 'learned_vocabulary_provider.dart';
import 'word_book_provider.dart';

final _contextCountProvider = StreamProvider.autoDispose.family<int, String>(
  (Ref ref, String word) => WordEncounterStore(
    account: ref.watch(studyAccountProvider),
  ).watchContextCount(word),
);

class WordContextProgress extends ConsumerWidget {
  const WordContextProgress({
    required this.word,
    this.showDetails = false,
    super.key,
  });

  final String word;
  final bool showDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String key = normalizeWord(word);
    final bool learned = ref.watch(
      learnedVocabularyProvider.select(
        (Set<String> words) => words.contains(key),
      ),
    );
    if (!learned) return const SizedBox.shrink();

    final int? count = ref.watch(_contextCountProvider(key)).asData?.value;
    if (count == null || (!showDetails && count == 0)) {
      return const SizedBox.shrink();
    }
    const int goal = WordEncounterStore.contextGoal;
    final String label = '语境再遇 $count/$goal';
    if (!showDetails) {
      return Text(label, style: Theme.of(context).textTheme.bodySmall);
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: const Text('在阅读或字幕中点查绿色单词，即可记录新的句子。'),
      leading: Icon(
        count == goal
            ? Icons.check_circle_outline
            : Icons.auto_stories_outlined,
      ),
    );
  }
}
