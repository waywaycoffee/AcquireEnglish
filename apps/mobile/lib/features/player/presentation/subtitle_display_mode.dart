/// Learning subtitle display modes shown in the study player.
///
/// Product rules:
/// - Default is always [bilingual]: English primary + Chinese secondary.
/// - English primary is required whenever subtitles are shown, unless the user
///   explicitly chooses not to show English ([chinese] / [blind] / [hidden]).
///
/// Persisted settings may still contain legacy values (`单英` / `单中` / `隐藏`).
class SubtitleDisplayMode {
  SubtitleDisplayMode._();

  static const String bilingual = '双语';
  static const String english = '英文';
  static const String chinese = '中文';
  static const String blind = '盲听';
  static const String hidden = '隐藏';

  /// The four modes users can pick in study UI.
  static const List<String> learningModes = <String>[
    bilingual,
    english,
    chinese,
    blind,
  ];

  static const List<String> allModes = <String>[
    bilingual,
    english,
    chinese,
    blind,
    hidden,
  ];

  static String normalize(String? raw) {
    switch ((raw ?? '').trim()) {
      case '单英':
      case english:
        return english;
      case '单中':
      case chinese:
        return chinese;
      case blind:
        return blind;
      case hidden:
        return hidden;
      case bilingual:
        return bilingual;
      default:
        return bilingual;
    }
  }

  /// Open-course / fallback mode — always bilingual.
  static String get defaultMode => bilingual;

  static bool isBlind(String? mode) => normalize(mode) == blind;

  static bool isChineseOnly(String? mode) => normalize(mode) == chinese;

  static bool isEnglishOnly(String? mode) => normalize(mode) == english;

  /// User chose not to show the English primary line.
  static bool hidesEnglishPrimary(String? mode) {
    final String normalized = normalize(mode);
    return normalized == chinese ||
        normalized == blind ||
        normalized == hidden;
  }

  /// English must be the hero line for these display modes.
  static bool requiresEnglishPrimary(String? mode) {
    return !hidesEnglishPrimary(mode);
  }

  /// Content rules while revealing a blind cue (English stays primary).
  static String contentMode(String? mode) {
    final String normalized = normalize(mode);
    return normalized == blind ? bilingual : normalized;
  }

  static String label(String? mode) => normalize(mode);
}
