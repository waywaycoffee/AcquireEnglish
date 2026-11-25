/// Bilibili BV ids that are official App series (or free-seed ECS softsubs)
/// and should **not** show「预约字幕」in browse/recommend cards.
///
/// Keep in sync with:
/// - `services/api/data/oral_core_9000/manifest.json`
/// - `american_ipa_20` / `british_ipa_bbc` / `phonics_nessy` course constants
/// - `services/api/data/free_trial_seeds.json` video seeds with shared_subtitles
const Set<String> kOfficialBilibiliSoftsubBvids = <String>{
  'BV1CS4Y1V7SQ', // 英语核心口语句型9000句 → oral_core_9000
  'BV1IY4Y1V7WQ', // 美式音标慢速跟读 → american_ipa_20
  'BV127411N7NJ', // BBC 官方音标 → british_ipa_bbc
  'BV1QG4MZKENH', // Nessy 自然拼读 → phonics_nessy
  // Free-trial video seeds that already point at shared ECS softsubs:
  'BV1FV4Y1P7EX', // 48 个地道音标口型
  'BV1GM411R7YZ', // Pronunciation with Emma
  'BV1AW4M1K7QU', // 美国人从小就说的英文100句
};

bool isOfficialBilibiliSoftsubBvid(String? bvid) {
  final String id = (bvid ?? '').trim().toUpperCase();
  if (id.isEmpty) return false;
  return kOfficialBilibiliSoftsubBvids.contains(id);
}

bool sourceLooksLikeOfficialBilibiliSoftsubSeries(String rawSource) {
  final String upper = rawSource.trim().toUpperCase();
  if (upper.isEmpty) return false;
  for (final String bvid in kOfficialBilibiliSoftsubBvids) {
    if (upper.contains(bvid)) return true;
  }
  return false;
}
