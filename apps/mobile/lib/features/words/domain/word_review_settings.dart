/// Daily Ebbinghaus-style word plan + which practice modes run in a session.
enum WordPracticeMode {
  /// Flip card + self grade (认记).
  recognize,

  /// Type the English spelling from Chinese/definition (拼写).
  spell,

  /// Listen + shadow the pronunciation (发音跟读).
  speak,
}

extension WordPracticeModeX on WordPracticeMode {
  String get label => switch (this) {
    WordPracticeMode.recognize => '认记',
    WordPracticeMode.spell => '拼写',
    WordPracticeMode.speak => '发音跟读',
  };

  String get hint => switch (this) {
    WordPracticeMode.recognize => '看词回想释义，自评难度',
    WordPracticeMode.spell => '根据中文释义默写英文单词',
    WordPracticeMode.speak => '听示范后跟读，再自评',
  };

  static WordPracticeMode? tryParse(String? raw) {
    switch (raw) {
      case 'recognize':
        return WordPracticeMode.recognize;
      case 'spell':
        return WordPracticeMode.spell;
      case 'speak':
        return WordPracticeMode.speak;
      default:
        return null;
    }
  }
}

class WordReviewSettings {
  const WordReviewSettings({
    this.dailyNewLimit = 20,
    this.dailyReviewLimit = 50,
    this.enabledModes = const <WordPracticeMode>[
      WordPracticeMode.recognize,
      WordPracticeMode.spell,
      WordPracticeMode.speak,
    ],
  });

  final int dailyNewLimit;
  final int dailyReviewLimit;
  final List<WordPracticeMode> enabledModes;

  static const WordReviewSettings defaults = WordReviewSettings();

  List<WordPracticeMode> get orderedModes {
    final List<WordPracticeMode> all = WordPracticeMode.values;
    return all.where(enabledModes.contains).toList(growable: false);
  }

  bool isEnabled(WordPracticeMode mode) => enabledModes.contains(mode);

  WordReviewSettings copyWith({
    int? dailyNewLimit,
    int? dailyReviewLimit,
    List<WordPracticeMode>? enabledModes,
  }) {
    final List<WordPracticeMode> modes =
        enabledModes ?? this.enabledModes;
    return WordReviewSettings(
      dailyNewLimit: (dailyNewLimit ?? this.dailyNewLimit).clamp(0, 200),
      dailyReviewLimit: (dailyReviewLimit ?? this.dailyReviewLimit).clamp(0, 500),
      enabledModes: modes.isEmpty
          ? const <WordPracticeMode>[WordPracticeMode.recognize]
          : List<WordPracticeMode>.unmodifiable(modes),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'dailyNewLimit': dailyNewLimit,
    'dailyReviewLimit': dailyReviewLimit,
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
      dailyNewLimit: (json['dailyNewLimit'] as num?)?.toInt() ?? 20,
      dailyReviewLimit: (json['dailyReviewLimit'] as num?)?.toInt() ?? 50,
      enabledModes: modes.isEmpty
          ? WordReviewSettings.defaults.enabledModes
          : modes,
    );
  }
}
