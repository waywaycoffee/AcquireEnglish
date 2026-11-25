/// Bilibili BV ids that ship study softsubs on ECS (no 预约字幕 needed).
///
/// Keep in sync with `services/api/data/oral_core_9000/manifest.json` and any
/// other official series that map B站源 + `/media/course/...` SRT.
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
