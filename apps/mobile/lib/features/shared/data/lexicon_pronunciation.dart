import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/settings_provider.dart';
import '../domain/word_lookup_entry.dart';
import 'word_lookup_service.dart';
import 'word_pronunciation_service.dart';

/// Resolve public-lexicon audio for [word], then play it (TTS fallback).
Future<WordLookupEntry?> speakWithPublicLexicon(
  WidgetRef ref,
  String word, {
  bool allowSynthesisFallback = true,
}) async {
  final String lemma = word.trim().toLowerCase().replaceAll('’', "'");
  if (lemma.isEmpty) return null;

  final LearningSettingsState settings = ref.read(learningSettingsProvider);
  WordLookupEntry? entry;
  try {
    entry = await ref
        .read(wordLookupServiceProvider)
        .publicLookup
        ?.call(lemma, settings);
  } catch (_) {
    entry = null;
  }

  await ref.read(wordPronunciationServiceProvider).speak(
        lemma,
        recordedUrl: entry?.audioUrl,
        allowSynthesisFallback: allowSynthesisFallback,
      );
  return entry;
}
