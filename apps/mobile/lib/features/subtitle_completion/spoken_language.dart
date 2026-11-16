import '../player/presentation/bilingual_subtitle_helpers.dart';

/// Spoken language of the video audio (not the UI language).
enum SpokenLanguage { english, chinese }

const Set<String> _englishLearningMarkers = <String>{
  'english',
  'tinglish',
  'ted',
  'voa',
  'ielts',
  'toefl',
  'bbc',
  'listening',
  'speaking',
  'vocabulary',
  'grammar',
  'podcast',
  '英语',
  '英文',
  '听力',
  '口语',
  '词汇',
  '雅思',
  '托福',
  '美音',
  '英音',
  '磨耳朵',
  '跟读',
  'shadowing',
};

const Set<String> _chineseSpokenMarkers = <String>{
  '普通话',
  '汉语',
  '中文课',
  '语文',
  '相声',
  '评书',
  '有声书',
  '朗读中文',
  'chinese podcast',
  'mandarin',
};

/// Infer spoken language for ASR-first fill.
///
/// Defaults to English (this app is English learning). Chinese wins only with
/// strong Chinese-spoken markers and no English-learning markers.
SpokenLanguage inferSpokenLanguage({
  String? title,
  String? description,
  bool hasReliableEnglish = false,
  bool hasReliableChinese = false,
  SpokenLanguage? force,
}) {
  if (force != null) {
    return force;
  }
  if (hasReliableEnglish && !hasReliableChinese) {
    return SpokenLanguage.english;
  }
  // Chinese CC alone is common on English Bilibili lessons — do not treat as
  // Chinese speech.
  if (hasReliableEnglish) {
    return SpokenLanguage.english;
  }

  final String blob = '${title ?? ''} ${description ?? ''}'.toLowerCase();
  final bool englishMark = _englishLearningMarkers.any(blob.contains);
  final bool chineseMark = _chineseSpokenMarkers.any(blob.contains);
  if (chineseMark && !englishMark) {
    return SpokenLanguage.chinese;
  }
  if (englishMark) {
    return SpokenLanguage.english;
  }

  // Title mostly Chinese characters and almost no Latin → weak Chinese hint.
  final String titleText = (title ?? '').trim();
  if (titleText.isNotEmpty) {
    int han = 0;
    int latin = 0;
    for (final int unit in titleText.runes) {
      if (unit >= 0x4E00 && unit <= 0x9FFF) {
        han += 1;
      } else if ((unit >= 0x41 && unit <= 0x5A) ||
          (unit >= 0x61 && unit <= 0x7A)) {
        latin += 1;
      }
    }
    if (han >= 8 && latin <= 2 && looksChinese(titleText) && !looksEnglish(titleText)) {
      return SpokenLanguage.chinese;
    }
  }
  return SpokenLanguage.english;
}

extension SpokenLanguageX on SpokenLanguage {
  String get code => this == SpokenLanguage.chinese ? 'zh' : 'en';
}

SpokenLanguage spokenLanguageFromCode(String? raw) {
  final String value = (raw ?? '').trim().toLowerCase();
  if (value.startsWith('zh') || value == 'chinese' || value == 'cn') {
    return SpokenLanguage.chinese;
  }
  return SpokenLanguage.english;
}
