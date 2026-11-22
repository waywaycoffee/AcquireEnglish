/// Immersion hides inline glosses by default; intensive shows hard-word Chinese.
enum ReadingStudyMode {
  immersion,
  intensive,
}

extension ReadingStudyModeX on ReadingStudyMode {
  String get storageValue => name;

  String get labelCn => switch (this) {
    ReadingStudyMode.immersion => '沉浸',
    ReadingStudyMode.intensive => '精读',
  };

  bool get showInlineChinese => this == ReadingStudyMode.intensive;

  bool get showChunkLegend => this == ReadingStudyMode.intensive;

  static ReadingStudyMode fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'intensive':
        return ReadingStudyMode.intensive;
      case 'immersion':
      default:
        // New users default to immersion (PRD).
        return ReadingStudyMode.immersion;
    }
  }
}

const String kReadingStudyModeKey = 'reading_study_mode_v1';
const String kReadingSentenceTranslateKey = 'reading_sentence_translate_v1';
const String kReadingFreqThresholdKey = 'reading_freq_threshold_v1';

/// Frequency rank bands for the difficulty slider (1 = most common).
/// Floor at 1500 so long novels (绿野仙踪) do not gloss nearly every word and OOM.
const List<int> kReadingFreqThresholdBands = <int>[
  1500,
  3000,
  5000,
  8000,
  12000,
  20000,
  30000,
  45000,
];

const int kReadingDefaultFreqThreshold = 3000;

/// Hard floor for adaptive gloss / i+1 frontier (below this freezes long books).
const int kReadingGlossThresholdFloor = 1500;
