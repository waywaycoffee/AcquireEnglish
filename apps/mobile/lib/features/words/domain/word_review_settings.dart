/// Daily Ebbinghaus-style word plan + which practice modes run in a session.
enum WordPracticeMode {
  /// Flip card + self grade (认记).
  recognize,

  /// Audio only → recall meaning (听音).
  listen,

  /// Type the English spelling from Chinese/definition (拼写).
  spell,

  /// Listen + shadow the pronunciation (发音跟读).
  speak,

  /// Confusable / near-miss discrimination (辨异).
  contrast,
}

extension WordPracticeModeX on WordPracticeMode {
  String get label => switch (this) {
    WordPracticeMode.recognize => '认记',
    WordPracticeMode.listen => '听音',
    WordPracticeMode.spell => '拼写',
    WordPracticeMode.speak => '发音跟读',
    WordPracticeMode.contrast => '辨异',
  };

  String get hint => switch (this) {
    WordPracticeMode.recognize => '看词回想释义，自评难度',
    WordPracticeMode.listen => '只听发音，识别单词与释义',
    WordPracticeMode.spell => '根据中文释义默写英文单词',
    WordPracticeMode.speak => '听示范后跟读，再自评',
    WordPracticeMode.contrast => '对比易混词，分清形义差异',
  };

  static WordPracticeMode? tryParse(String? raw) {
    switch (raw) {
      case 'recognize':
        return WordPracticeMode.recognize;
      case 'listen':
        return WordPracticeMode.listen;
      case 'spell':
        return WordPracticeMode.spell;
      case 'speak':
        return WordPracticeMode.speak;
      case 'contrast':
        return WordPracticeMode.contrast;
      default:
        return null;
    }
  }
}

enum WordRecallStyle { flashcard, multipleChoice }

class WordReviewSettings {
  const WordReviewSettings({
    this.recallStyle = WordRecallStyle.flashcard,
    this.requireSpelling = false,
    this.dailyNewLimit = 20,
    this.dailyReviewLimit = 50,
    this.showWordRoots = true,
    this.enabledModes = const <WordPracticeMode>[
      WordPracticeMode.recognize,
      WordPracticeMode.listen,
    ],
  });

  final WordRecallStyle recallStyle;
  final bool requireSpelling;
  final int dailyNewLimit;
  final int dailyReviewLimit;

  /// Auto-show root breakdown on review / lookup / detail (default on).
  final bool showWordRoots;
  final List<WordPracticeMode> enabledModes;

  static const WordReviewSettings defaults = WordReviewSettings();

  List<WordPracticeMode> get orderedModes {
    final List<WordPracticeMode> all = WordPracticeMode.values;
    return all.where(enabledModes.contains).toList(growable: false);
  }

  bool isEnabled(WordPracticeMode mode) => enabledModes.contains(mode);

  WordReviewSettings copyWith({
    WordRecallStyle? recallStyle,
    bool? requireSpelling,
    int? dailyNewLimit,
    int? dailyReviewLimit,
    bool? showWordRoots,
    List<WordPracticeMode>? enabledModes,
  }) {
    final List<WordPracticeMode> modes = enabledModes ?? this.enabledModes;
    return WordReviewSettings(
      recallStyle: recallStyle ?? this.recallStyle,
      requireSpelling: requireSpelling ?? this.requireSpelling,
      dailyNewLimit: (dailyNewLimit ?? this.dailyNewLimit).clamp(0, 150),
      dailyReviewLimit: (dailyReviewLimit ?? this.dailyReviewLimit).clamp(
        0,
        500,
      ),
      showWordRoots: showWordRoots ?? this.showWordRoots,
      enabledModes: modes.isEmpty
          ? const <WordPracticeMode>[WordPracticeMode.recognize]
          : List<WordPracticeMode>.unmodifiable(modes),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'recallStyle': recallStyle.name,
    'requireSpelling': requireSpelling,
    'dailyNewLimit': dailyNewLimit,
    'dailyReviewLimit': dailyReviewLimit,
    'showWordRoots': showWordRoots,
    'enabledModes': enabledModes.map((WordPracticeMode m) => m.name).toList(),
  };

  factory WordReviewSettings.fromJson(Map<String, dynamic> json) {
    final List<WordPracticeMode> modes = <WordPracticeMode>[];
    final Object? rawModes = json['enabledModes'];
    if (rawModes is List) {
      for (final Object? item in rawModes) {
        final WordPracticeMode? mode = WordPracticeModeX.tryParse('$item');
        if (mode != null && !modes.contains(mode)) {
          modes.add(mode);
        }
      }
    }
    return WordReviewSettings(
      recallStyle: json['recallStyle'] == WordRecallStyle.multipleChoice.name
          ? WordRecallStyle.multipleChoice
          : WordRecallStyle.flashcard,
      requireSpelling: json['requireSpelling'] == true,
      dailyNewLimit: (json['dailyNewLimit'] as num?)?.toInt() ?? 20,
      dailyReviewLimit: (json['dailyReviewLimit'] as num?)?.toInt() ?? 50,
      showWordRoots: json['showWordRoots'] as bool? ?? true,
      enabledModes: modes.isEmpty
          ? WordReviewSettings.defaults.enabledModes
          : modes,
    );
  }
}
