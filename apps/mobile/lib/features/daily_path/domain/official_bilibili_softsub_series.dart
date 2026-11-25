/// Bilibili BV ids that ship **bilingual** study softsubs on ECS
/// (EN + ZH) for every lesson —「预约字幕」can be hidden for these alone.
///
/// Only include series with confirmed `/media/.../en.srt` **and** `zh.srt`.
/// Skill courses that rely on B站硬字幕 / EN-only must NOT be listed here.
const Set<String> kOfficialBilibiliSoftsubBvids = <String>{
  'BV1CS4Y1V7SQ', // 英语核心口语句型9000句 → oral_core_9000
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
