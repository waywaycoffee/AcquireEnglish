/// Default free-trial / seed catalog (~3 items × video/reading/exam/course).
///
/// Media is never shipped in the APK; seeds are auto-downloaded into local
/// cache from ECS/API on bootstrap (`freeTrialSeedBootstrapProvider`).
/// Cap stays aligned with `kModuleFreePreviewCount` / API `FREE_PREVIEW_COUNT`.

class FreeTrialSeedItem {
  const FreeTrialSeedItem({
    required this.module,
    required this.id,
    required this.title,
    required this.kind,
    this.freeTrial = true,
    this.defaultSeed = true,
    this.bvid = '',
    this.page = 1,
    this.watchUrl = '',
    this.familyId = '',
    this.skill = '',
    this.itemId = '',
    this.sourceStarterId = '',
  });

  final String module;
  final String id;
  final String title;
  final String kind;
  final bool freeTrial;
  final bool defaultSeed;
  final String bvid;
  final int page;
  final String watchUrl;
  final String familyId;
  final String skill;
  final String itemId;
  final String sourceStarterId;

  factory FreeTrialSeedItem.fromJson(
    Map<String, dynamic> json, {
    String? module,
  }) {
    return FreeTrialSeedItem(
      module: (module ?? '${json['module'] ?? ''}').trim(),
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      kind: '${json['kind'] ?? ''}'.trim(),
      freeTrial: json['freeTrial'] != false,
      defaultSeed: json['defaultSeed'] != false,
      bvid: '${json['bvid'] ?? ''}'.trim(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      watchUrl: '${json['watchUrl'] ?? json['watch_url'] ?? ''}'.trim(),
      familyId: '${json['familyId'] ?? json['family_id'] ?? ''}'.trim(),
      skill: '${json['skill'] ?? ''}'.trim(),
      itemId: '${json['itemId'] ?? json['item_id'] ?? ''}'.trim(),
      sourceStarterId:
          '${json['sourceStarterId'] ?? json['source_starter_id'] ?? ''}'
              .trim(),
    );
  }
}

/// Bundled fallback when `/api/commerce/free-trial-seeds` is unreachable.
const Map<String, List<FreeTrialSeedItem>> kDefaultFreeTrialSeeds =
    <String, List<FreeTrialSeedItem>>{
  'video': <FreeTrialSeedItem>[
    FreeTrialSeedItem(
      module: 'video',
      id: 'bilibili:BV1fV4y1p7Ex',
      title: '48个地道音标口型对照',
      kind: 'bilibili',
      bvid: 'BV1fV4y1p7Ex',
      page: 1,
      watchUrl: 'https://www.bilibili.com/video/BV1fV4y1p7Ex?p=1',
    ),
    FreeTrialSeedItem(
      module: 'video',
      id: 'bilibili:BV1gm411r7yz',
      title: 'Pronunciation with Emma · 英音语调',
      kind: 'bilibili',
      bvid: 'BV1gm411r7yz',
      page: 1,
      watchUrl: 'https://www.bilibili.com/video/BV1gm411r7yz?p=1',
    ),
    FreeTrialSeedItem(
      module: 'video',
      id: 'bilibili:BV1Aw4m1k7qU',
      title: '美国人从小就说的英文100句（试看第1P）',
      kind: 'bilibili',
      bvid: 'BV1Aw4m1k7qU',
      page: 1,
      watchUrl: 'https://www.bilibili.com/video/BV1Aw4m1k7qU?p=1',
    ),
  ],
  'reading': <FreeTrialSeedItem>[
    FreeTrialSeedItem(
      module: 'reading',
      id: 'starter-first-morning',
      title: 'A Quiet Morning',
      kind: 'starter_doc',
    ),
    FreeTrialSeedItem(
      module: 'reading',
      id: 'starter-small-cafe',
      title: 'The Small Cafe',
      kind: 'starter_doc',
    ),
    FreeTrialSeedItem(
      module: 'reading',
      id: 'starter-new-route',
      title: 'A Different Way Home',
      kind: 'starter_doc',
    ),
  ],
  'exam': <FreeTrialSeedItem>[
    FreeTrialSeedItem(
      module: 'exam',
      id: 'exam:cet4:vocab:c4v1',
      title: 'CET4 词汇体验 · abandon',
      kind: 'exam_item',
      familyId: 'cet4',
      skill: 'vocab',
      itemId: 'c4v1',
    ),
    FreeTrialSeedItem(
      module: 'exam',
      id: 'exam:cet4:reading:c4r1',
      title: 'CET4 阅读体验 · Campus Clubs',
      kind: 'exam_item',
      familyId: 'cet4',
      skill: 'reading',
      itemId: 'c4r1',
    ),
    FreeTrialSeedItem(
      module: 'exam',
      id: 'exam:cet4:listening:c4l1',
      title: 'CET4 听力体验 · Conversation: Report',
      kind: 'exam_item',
      familyId: 'cet4',
      skill: 'listening',
      itemId: 'c4l1',
    ),
  ],
  'course': <FreeTrialSeedItem>[
    FreeTrialSeedItem(
      module: 'course',
      id: 'course-seed-quiet-morning',
      title: '体验课 · A Quiet Morning',
      kind: 'course_demo',
      sourceStarterId: 'starter-first-morning',
    ),
    FreeTrialSeedItem(
      module: 'course',
      id: 'course-seed-small-cafe',
      title: '体验课 · The Small Cafe',
      kind: 'course_demo',
      sourceStarterId: 'starter-small-cafe',
    ),
    FreeTrialSeedItem(
      module: 'course',
      id: 'course-seed-new-route',
      title: '体验课 · A Different Way Home',
      kind: 'course_demo',
      sourceStarterId: 'starter-new-route',
    ),
  ],
};

List<FreeTrialSeedItem> freeTrialSeedsFor(String moduleCode) {
  return List<FreeTrialSeedItem>.unmodifiable(
    kDefaultFreeTrialSeeds[moduleCode] ?? const <FreeTrialSeedItem>[],
  );
}

Iterable<FreeTrialSeedItem> get allDefaultFreeTrialSeeds sync* {
  for (final List<FreeTrialSeedItem> rows in kDefaultFreeTrialSeeds.values) {
    yield* rows;
  }
}

bool isFreeTrialSeedId(String id) {
  final String want = id.trim();
  if (want.isEmpty) return false;
  for (final FreeTrialSeedItem item in allDefaultFreeTrialSeeds) {
    if (item.id == want) return true;
  }
  return false;
}

bool isFreeTrialBilibiliBvid(String bvid, {int? page}) {
  final String bv = bvid.trim();
  if (bv.isEmpty) return false;
  for (final FreeTrialSeedItem item in freeTrialSeedsFor('video')) {
    if (item.kind != 'bilibili') continue;
    if (item.bvid.toUpperCase() != bv.toUpperCase()) continue;
    if (page != null && item.page != page) continue;
    return true;
  }
  return false;
}

bool isFreeTrialExamItem({
  required String skill,
  required String itemId,
  String familyId = 'cet4',
}) {
  final String sk = skill.trim();
  final String id = itemId.trim();
  if (sk.isEmpty || id.isEmpty) return false;
  for (final FreeTrialSeedItem item in freeTrialSeedsFor('exam')) {
    if (item.skill == sk &&
        item.itemId == id &&
        (familyId.isEmpty || item.familyId == familyId)) {
      return true;
    }
  }
  return false;
}

bool isFreeTrialCourseSeedId(String id) =>
    id.trim().startsWith('course-seed-') && isFreeTrialSeedId(id.trim());

Map<String, List<FreeTrialSeedItem>> parseFreeTrialSeedsPayload(
  Map<String, dynamic>? raw,
) {
  if (raw == null) return kDefaultFreeTrialSeeds;
  final Object? modules = raw['modules'];
  if (modules is! Map) return kDefaultFreeTrialSeeds;
  final Map<String, List<FreeTrialSeedItem>> out =
      <String, List<FreeTrialSeedItem>>{};
  for (final String code in kDefaultFreeTrialSeeds.keys) {
    final Object? rows = modules[code];
    if (rows is! List || rows.isEmpty) {
      out[code] = freeTrialSeedsFor(code);
      continue;
    }
    final List<FreeTrialSeedItem> parsed = <FreeTrialSeedItem>[];
    for (final Object? row in rows) {
      if (row is! Map) continue;
      final FreeTrialSeedItem item = FreeTrialSeedItem.fromJson(
        Map<String, dynamic>.from(row),
        module: code,
      );
      if (item.id.isEmpty) continue;
      parsed.add(item);
    }
    out[code] = parsed.isEmpty
        ? freeTrialSeedsFor(code)
        : parsed.take(3).toList(growable: false);
  }
  return out;
}
