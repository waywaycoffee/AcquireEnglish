import '../../digital_human/data/digital_human_catalog.dart';
import '../../digital_human/data/oral_coach_pipeline_client.dart';
import '../domain/reading_doc.dart';

const int kReadingCoachExcerptMaxChars = 3500;

/// Sample start / middle / end of the article for the oral-coach LLM context.
String readingCoachArticleExcerpt(String plainText, {int maxChars = kReadingCoachExcerptMaxChars}) {
  final String text = plainText.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.length <= maxChars) return text;
  final int chunk = (maxChars / 3).floor().clamp(200, 1200);
  final String head = text.substring(0, chunk);
  final int midStart = ((text.length - chunk) / 2).floor().clamp(0, text.length - chunk);
  final String mid = text.substring(midStart, midStart + chunk);
  final String tail = text.substring(text.length - chunk);
  return '$head\n…\n$mid\n…\n$tail';
}

OralCoachVideoContext buildReadingCoachContext({
  required ReadingDoc doc,
  required DigitalHumanPersona persona,
  String focusedSentence = '',
  String ttsVoice = '',
  String replyLanguage = 'zh',
  String difficulty = 'B1',
}) {
  final String focused = focusedSentence.trim();
  final String title = doc.title.trim().isEmpty ? '阅读文章' : doc.title.trim();
  return OralCoachVideoContext(
    courseTitle: doc.courseTitle.trim().isNotEmpty ? doc.courseTitle.trim() : '阅读',
    episodeTitle: doc.episodeTitle.trim().isNotEmpty
        ? doc.episodeTitle.trim()
        : title,
    topicSummary: focused.isNotEmpty ? '当前句 · $focused' : '阅读陪练 · $title',
    articleExcerpt: readingCoachArticleExcerpt(doc.plainText),
    currentEnglish: focused,
    difficulty: difficulty.trim().isEmpty ? 'B1' : difficulty.trim(),
    digitalHumanId: persona.id,
    ttsVoice: ttsVoice,
    replyLanguage: replyLanguage,
    scenarioTitle: '阅读答疑',
    scenarioGoal: '帮助学生理解当前阅读内容，用简明中英解释难词、句子与文化背景。',
    scenarioPrompt:
        'You are a friendly reading tutor. The learner is reading an English article. '
        'Answer questions about vocabulary, grammar, meaning, and culture. '
        'Keep answers short and clear. Prefer Chinese explanations with key English phrases.',
  );
}

String readingCoachVoiceForPersona(DigitalHumanPersona persona) {
  final String? recommended = persona.recommendedVoiceId?.trim();
  if (recommended != null && recommended.isNotEmpty) return recommended;
  return persona.isFemaleVoice
      ? 'qwen-audio-3.0-tts-flash-loongolivialin'
      : 'qwen-audio-3.0-tts-flash-loongadriangao';
}
