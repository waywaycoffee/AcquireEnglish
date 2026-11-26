import 'syllabus_book.dart';

/// Shelf browse tabs on 词书 screen (exact labels, display order).
enum SyllabusBookCategory {
  pattern('句型'),
  phonics('拼读'),
  primary('小学'),
  junior('初中'),
  senior('高中'),
  college('大学'),
  abroad('出国'),
  career('职业');

  const SyllabusBookCategory(this.label);

  final String label;

  static const List<SyllabusBookCategory> tabs = SyllabusBookCategory.values;

  /// Import / cloud kind hint for the selected browse tab.
  SyllabusBookKind get importKind => switch (this) {
        SyllabusBookCategory.pattern => SyllabusBookKind.pattern,
        SyllabusBookCategory.phonics => SyllabusBookKind.foundation,
        _ => SyllabusBookKind.word,
      };

  static SyllabusBookCategory fromInitialKind(SyllabusBookKind kind) {
    return switch (kind) {
      SyllabusBookKind.pattern => SyllabusBookCategory.pattern,
      SyllabusBookKind.foundation => SyllabusBookCategory.phonics,
      SyllabusBookKind.word => SyllabusBookCategory.college,
    };
  }
}

/// Map cloud / open-source book metadata → one of [SyllabusBookCategory].
///
/// Priority (first match wins):
/// 1. [SyllabusBookKind.pattern] → 句型
/// 2. [SyllabusBookKind.foundation] → 拼读
/// 3. examTag / title / path keywords:
///    - 句型 / 句式 / sentence pattern(s) / phrases / 情景句 / 日常口语 → 句型
///      (before career / abroad / school buckets so e.g. 程序员口语句型 → 句型)
///    - phonics / 拼读 / 自然拼读 / IPA → 拼读
///    - 商务 / BEC / IT / 职业 / 程序员 → 职业
///    - 托福 / 雅思 / SAT / GRE / 出国 → 出国
///    - 四六级 / 考研 / 专四专八 / 大学 / CET → 大学
///    - 高考 / 高中 / GK / SH → 高中
///    - 中考 / 初中 / JH / ZK → 初中
///    - 小学 / PEP / K12 / 课标 → 小学
/// 4. Unmapped → 大学 (soft fallback).
///
/// Uncategorized count among packaged API books (as of mapping rules): 0 —
/// highfreq_* intentionally map to 大学 via 高频/hf* tokens; lilinji OTHER → 出国.
SyllabusBookCategory classifySyllabusBookCategory({
  required String title,
  String examTag = '',
  String path = '',
  SyllabusBookKind kind = SyllabusBookKind.word,
}) {
  if (kind == SyllabusBookKind.pattern) {
    return SyllabusBookCategory.pattern;
  }
  if (kind == SyllabusBookKind.foundation) {
    return SyllabusBookCategory.phonics;
  }

  final String hay =
      '$examTag $title $path ${kind.storageName}'.toLowerCase();

  // 句型 keywords before other stage/career buckets.
  if (_matches(hay, const <String>[
        'sentence pattern',
        'sentence patterns',
        'oral pattern',
        'oral patterns',
        'pattern book',
        '句型',
        '句式',
        '情景句',
        '日常口语',
        '口语句型',
        '语块',
      ]) ||
      RegExp(r'(^|[^a-z])phrases?([^a-z]|$)').hasMatch(hay)) {
    return SyllabusBookCategory.pattern;
  }

  if (_matches(hay, const <String>[
    'phonics',
    '拼读',
    '自然拼读',
    'ipa',
    'cvc',
    '音标',
    '零基础',
  ])) {
    return SyllabusBookCategory.phonics;
  }

  if (_matches(hay, const <String>[
    'bec',
    '商务',
    '职业',
    '商务英语',
    'programmer',
    '程序员',
    '开发英语',
    '扇贝英语',
  ]) ||
      RegExp(r'(^|[^a-z])it([^a-z]|$)').hasMatch(hay)) {
    return SyllabusBookCategory.career;
  }

  if (_matches(hay, const <String>[
    'toefl',
    '托福',
    'ielts',
    '雅思',
    'sat',
    'gre',
    'gmat',
    '出国',
    '留学',
    '国际英语',
  ])) {
    return SyllabusBookCategory.abroad;
  }

  if (_matches(hay, const <String>[
    'cet4',
    'cet6',
    'cet-4',
    'cet-6',
    '四级',
    '六级',
    '四六级',
    '考研',
    'ky',
    'kaoyan',
    'tem4',
    'tem8',
    '专四',
    '专八',
    '大学',
    'college',
    '研究生',
    '考博',
    'grad',
    'phd',
    '英专',
    '新概念',
    'nce',
    '高频',
    'hf1k',
    'hf2k',
    'hf3k',
  ])) {
    return SyllabusBookCategory.college;
  }

  if (_matches(hay, const <String>[
    '高考',
    '高中',
    'gaokao',
    'senior',
  ]) ||
      RegExp(r'(^|[^a-z])(gk|sh)([^a-z]|$)').hasMatch(hay)) {
    return SyllabusBookCategory.senior;
  }

  if (_matches(hay, const <String>[
    '中考',
    '初中',
    'junior',
    'zhongkao',
  ]) ||
      RegExp(r'(^|[^a-z])(jh|zk)([^a-z]|$)').hasMatch(hay)) {
    return SyllabusBookCategory.junior;
  }

  if (_matches(hay, const <String>[
    '小学',
    'pep',
    'pep3',
    'kids',
    'primary',
    '一年级',
    '二年级',
    '三年级',
    '四年级',
    '五年级',
    '六年级',
    '中小学',
    'k12',
    '课标',
    '义务教育',
  ])) {
    return SyllabusBookCategory.primary;
  }

  // Soft fallback for truly unknown titles/tags.
  return SyllabusBookCategory.college;
}

bool _matches(String hay, List<String> tokens) {
  for (final String token in tokens) {
    if (token.isNotEmpty && hay.contains(token.toLowerCase())) {
      return true;
    }
  }
  return false;
}
