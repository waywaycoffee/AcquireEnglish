/// Stable exam family ids used across onboarding, syllabus filters, and /exam.
enum ExamTrack {
  k12,
  cambridge,
  cet,
  postgraduate,
  toefl,
  ielts,
}

class ExamFamily {
  const ExamFamily({
    required this.id,
    required this.label,
    required this.track,
    required this.defaultCefr,
    this.targetHint = '',
    this.skills = const <String>['listening', 'reading', 'writing', 'speaking'],
    this.syllabusExamTags = const <String>[],
  });

  final String id;
  final String label;
  final ExamTrack track;
  final String defaultCefr;
  final String targetHint;
  final List<String> skills;

  /// Matches syllabus JSON `examTag` values when present.
  final List<String> syllabusExamTags;
}

const List<ExamFamily> kExamFamilies = <ExamFamily>[
  ExamFamily(
    id: 'k12_g1',
    label: '小学一年级',
    track: ExamTrack.k12,
    defaultCefr: 'A1',
    syllabusExamTags: <String>['K12_G1', 'PRIMARY'],
  ),
  ExamFamily(
    id: 'k12_g2',
    label: '小学二年级',
    track: ExamTrack.k12,
    defaultCefr: 'A1',
    syllabusExamTags: <String>['K12_G2', 'PRIMARY'],
  ),
  ExamFamily(
    id: 'k12_g3',
    label: '小学三年级',
    track: ExamTrack.k12,
    defaultCefr: 'A1',
    syllabusExamTags: <String>['K12_G3', 'PRIMARY'],
  ),
  ExamFamily(
    id: 'k12_g4',
    label: '小学四年级',
    track: ExamTrack.k12,
    defaultCefr: 'A1',
    syllabusExamTags: <String>['K12_G4', 'PRIMARY'],
  ),
  ExamFamily(
    id: 'k12_g5',
    label: '小学五年级',
    track: ExamTrack.k12,
    defaultCefr: 'A2',
    syllabusExamTags: <String>['K12_G5', 'PRIMARY'],
  ),
  ExamFamily(
    id: 'k12_g6',
    label: '小学六年级',
    track: ExamTrack.k12,
    defaultCefr: 'A2',
    syllabusExamTags: <String>['K12_G6', 'PRIMARY'],
  ),
  ExamFamily(
    id: 'k12_j1',
    label: '初一',
    track: ExamTrack.k12,
    defaultCefr: 'A2',
    syllabusExamTags: <String>['K12_J1', 'JUNIOR'],
  ),
  ExamFamily(
    id: 'k12_j2',
    label: '初二',
    track: ExamTrack.k12,
    defaultCefr: 'A2',
    syllabusExamTags: <String>['K12_J2', 'JUNIOR'],
  ),
  ExamFamily(
    id: 'k12_j3',
    label: '初三',
    track: ExamTrack.k12,
    defaultCefr: 'B1',
    syllabusExamTags: <String>['K12_J3', 'JUNIOR'],
  ),
  ExamFamily(
    id: 'zhongkao',
    label: '中考',
    track: ExamTrack.k12,
    defaultCefr: 'B1',
    targetHint: '按地区卷备考',
    syllabusExamTags: <String>['ZHONGKAO', 'JUNIOR'],
  ),
  ExamFamily(
    id: 'k12_s1',
    label: '高一',
    track: ExamTrack.k12,
    defaultCefr: 'B1',
    syllabusExamTags: <String>['K12_S1', 'SENIOR'],
  ),
  ExamFamily(
    id: 'k12_s2',
    label: '高二',
    track: ExamTrack.k12,
    defaultCefr: 'B1',
    syllabusExamTags: <String>['K12_S2', 'SENIOR'],
  ),
  ExamFamily(
    id: 'k12_s3',
    label: '高三',
    track: ExamTrack.k12,
    defaultCefr: 'B2',
    syllabusExamTags: <String>['K12_S3', 'SENIOR'],
  ),
  ExamFamily(
    id: 'gaokao',
    label: '高考',
    track: ExamTrack.k12,
    defaultCefr: 'B2',
    targetHint: '估分 / 档次',
    syllabusExamTags: <String>['GAOKAO', 'SENIOR'],
  ),
  ExamFamily(
    id: 'cn_english_taxonomy',
    label: 'K12 英语知识点（PEP / Go for it!）',
    track: ExamTrack.k12,
    defaultCefr: 'A2',
    targetHint: '带知识点图谱 · CC BY-NC',
    skills: <String>['vocab', 'reading'],
    syllabusExamTags: <String>['K12', 'PRIMARY', 'JUNIOR', 'SENIOR'],
  ),
  ExamFamily(
    id: 'race_middle',
    label: 'RACE 初中阅读（研究）',
    track: ExamTrack.k12,
    defaultCefr: 'A2',
    targetHint: '学术数据集 · 非商用',
    skills: <String>['reading'],
    syllabusExamTags: <String>['JUNIOR', 'ZHONGKAO'],
  ),
  ExamFamily(
    id: 'race_high',
    label: 'RACE 高中阅读（研究）',
    track: ExamTrack.k12,
    defaultCefr: 'B1',
    targetHint: '学术数据集 · 非商用',
    skills: <String>['reading'],
    syllabusExamTags: <String>['SENIOR', 'GAOKAO'],
  ),
  ExamFamily(
    id: 'ket',
    label: 'KET (A2 Key)',
    track: ExamTrack.cambridge,
    defaultCefr: 'A2',
    targetHint: 'Pass / Merit / Distinction',
    syllabusExamTags: <String>['KET', 'A2_KEY'],
  ),
  ExamFamily(
    id: 'pet',
    label: 'PET (B1 Preliminary)',
    track: ExamTrack.cambridge,
    defaultCefr: 'B1',
    targetHint: 'Pass / Merit / Distinction',
    syllabusExamTags: <String>['PET', 'B1_PRELIM'],
  ),
  ExamFamily(
    id: 'cet4',
    label: '大学英语四级',
    track: ExamTrack.cet,
    defaultCefr: 'B1',
    targetHint: '425+',
    syllabusExamTags: <String>['CET4'],
  ),
  ExamFamily(
    id: 'cet6',
    label: '大学英语六级',
    track: ExamTrack.cet,
    defaultCefr: 'B2',
    targetHint: '425+',
    syllabusExamTags: <String>['CET6'],
  ),
  ExamFamily(
    id: 'kaoyan',
    label: '考研英语',
    track: ExamTrack.postgraduate,
    defaultCefr: 'B2',
    targetHint: '分数段',
    syllabusExamTags: <String>['KAOYAN', 'PG'],
  ),
  ExamFamily(
    id: 'toefl',
    label: '托福',
    track: ExamTrack.toefl,
    defaultCefr: 'B2',
    targetHint: '0–120',
    syllabusExamTags: <String>['TOEFL'],
  ),
  ExamFamily(
    id: 'ielts_ac',
    label: '雅思学术类',
    track: ExamTrack.ielts,
    defaultCefr: 'B2',
    targetHint: '5.0–8.0',
    syllabusExamTags: <String>['IELTS', 'IELTS_AC'],
  ),
  ExamFamily(
    id: 'ielts_gt',
    label: '雅思培训类',
    track: ExamTrack.ielts,
    defaultCefr: 'B1',
    targetHint: '5.0–8.0',
    syllabusExamTags: <String>['IELTS', 'IELTS_GT'],
  ),
];

ExamFamily? examFamilyById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final ExamFamily f in kExamFamilies) {
    if (f.id == id) return f;
  }
  return null;
}

String examTrackLabel(ExamTrack track) => switch (track) {
  ExamTrack.k12 => 'K12 / 中高考',
  ExamTrack.cambridge => '剑桥英语',
  ExamTrack.cet => '四六级',
  ExamTrack.postgraduate => '考研',
  ExamTrack.toefl => '托福',
  ExamTrack.ielts => '雅思',
};

/// Research / extended datasets — hide from main K12 grade chips.
bool examFamilyIsResearch(ExamFamily f) =>
    f.id == 'cn_english_taxonomy' ||
    f.id == 'race_middle' ||
    f.id == 'race_high' ||
    f.id == 'cloth_cloze' ||
    f.id == 'scques_grammar';

/// Featured entrance exams shown first under K12.
const List<String> kK12EntranceExamIds = <String>['zhongkao', 'gaokao'];

List<ExamFamily> examFamiliesForTrack(
  ExamTrack track, {
  bool includeResearch = true,
}) {
  return kExamFamilies
      .where(
        (ExamFamily f) =>
            f.track == track &&
            (includeResearch || !examFamilyIsResearch(f)),
      )
      .toList(growable: false);
}

List<ExamFamily> k12FamiliesPrimary() => examFamiliesForTrack(
      ExamTrack.k12,
      includeResearch: false,
    )
        .where((ExamFamily f) => f.id.startsWith('k12_g'))
        .toList(growable: false);

List<ExamFamily> k12FamiliesJunior() => examFamiliesForTrack(
      ExamTrack.k12,
      includeResearch: false,
    )
        .where(
          (ExamFamily f) =>
              f.id.startsWith('k12_j') || f.id == 'zhongkao',
        )
        .toList(growable: false);

List<ExamFamily> k12FamiliesSenior() => examFamiliesForTrack(
      ExamTrack.k12,
      includeResearch: false,
    )
        .where(
          (ExamFamily f) => f.id.startsWith('k12_s') || f.id == 'gaokao',
        )
        .toList(growable: false);

List<ExamFamily> k12FamiliesResearch() => kExamFamilies
    .where((ExamFamily f) => f.track == ExamTrack.k12 && examFamilyIsResearch(f))
    .toList(growable: false);

String examWarmUpSubtitle(ExamFamily? family) {
  if (family == null) return '听读配速热身';
  switch (family.track) {
    case ExamTrack.k12:
      if (family.id == 'zhongkao' || family.id.startsWith('k12_j')) {
        return '中考听读配速';
      }
      if (family.id == 'gaokao' || family.id.startsWith('k12_s')) {
        return '高考听读配速';
      }
      return 'K12 听读配速';
    case ExamTrack.cet:
      return '四六级听读配速';
    case ExamTrack.postgraduate:
      return '考研听读配速';
    case ExamTrack.cambridge:
      return '剑桥听读配速';
    case ExamTrack.toefl:
      return '托福听读配速';
    case ExamTrack.ielts:
      return '雅思听读配速';
  }
}

/// Map IELTS band string to coarse CEFR used by learning preferences.
String cefrForIeltsBand(String band) {
  final double? n = double.tryParse(band);
  if (n == null) return 'B2';
  if (n < 5.0) return 'B1';
  if (n < 6.5) return 'B2';
  if (n < 7.5) return 'C1';
  return 'C2';
}

const List<String> kIeltsTargetBands = <String>[
  '5.0',
  '5.5',
  '6.0',
  '6.5',
  '7.0',
  '7.5',
  '8.0',
];
