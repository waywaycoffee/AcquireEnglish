/// Default free-trial / seed catalog (~5 items × video/reading/exam/course).
///
/// Media is never shipped in the APK; seeds are auto-downloaded into local
/// cache from ECS/API on bootstrap (`freeTrialSeedBootstrapProvider`).
/// Cap stays aligned with API `FREE_PREVIEW_COUNT`.
///
/// Product promises:
/// - each module always keeps enough permanent free content;
/// - bookshelf items acquired as free stay free;
/// - free users may keep ≥15 personal video + reading uploads.

/// Per-module free experience quota (lessons / docs / passages / courses).
const int kModuleFreePreviewCount = 5;

/// Free users may keep at least this many personal video + reading uploads.
const int kFreePersonalUploadSlotsMin = 15;

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
    this.learningPath = const <String>[],
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
  final List<String> learningPath;

  factory FreeTrialSeedItem.fromJson(
    Map<String, dynamic> json, {
    String? module,
  }) {
    final Object? pathRaw = json['learningPath'] ?? json['learning_path'];
    final List<String> path = pathRaw is List
        ? pathRaw.map((Object? e) => '$e'.trim()).where((String s) => s.isNotEmpty).toList()
        : const <String>[];
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
      learningPath: path,
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
      learningPath: <String>['字幕', '分句精听', '跟读', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'video',
      id: 'bilibili:BV12L4y1B7D2',
      title: 'Sounds American · 美式音标（试看第1P）',
      kind: 'bilibili',
      bvid: 'BV12L4y1B7D2',
      page: 1,
      watchUrl: 'https://www.bilibili.com/video/BV12L4y1B7D2?p=1',
      learningPath: <String>['字幕', '分句精听', '跟读', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'video',
      id: 'bilibili:BV1CS4y1v7sQ',
      title: '英语核心口语句型（试看第1课）',
      kind: 'bilibili',
      bvid: 'BV1CS4y1v7sQ',
      page: 1,
      watchUrl: 'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=1',
      learningPath: <String>['字幕', '分句精听', '跟读', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'video',
      id: 'bilibili:BV1MN4dewEQZ',
      title: '英语播客初级版 · 磨耳朵（试看第1P）',
      kind: 'bilibili',
      bvid: 'BV1MN4dewEQZ',
      page: 1,
      watchUrl: 'https://www.bilibili.com/video/BV1MN4dewEQZ?p=1',
      learningPath: <String>['字幕', '分句精听', '跟读', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'video',
      id: 'bilibili:BV1phynYEEBx',
      title: '老友记影子跟读（试看第1P）',
      kind: 'bilibili',
      bvid: 'BV1phynYEEBx',
      page: 1,
      watchUrl: 'https://www.bilibili.com/video/BV1phynYEEBx?p=1',
      learningPath: <String>['字幕', '分句精听', '跟读', '复习'],
    ),
  ],
  'reading': <FreeTrialSeedItem>[
    FreeTrialSeedItem(
      module: 'reading',
      id: 'starter-first-morning',
      title: 'A Quiet Morning',
      kind: 'starter_doc',
      learningPath: <String>['阅读一章', '查词', '收藏难词', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'reading',
      id: 'starter-small-cafe',
      title: 'The Small Cafe',
      kind: 'starter_doc',
      learningPath: <String>['阅读一章', '查词', '收藏难词', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'reading',
      id: 'starter-new-route',
      title: 'A Different Way Home',
      kind: 'starter_doc',
      learningPath: <String>['阅读一章', '查词', '收藏难词', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'reading',
      id: 'starter-rainy-afternoon',
      title: 'A Rainy Afternoon',
      kind: 'starter_doc',
      learningPath: <String>['阅读一章', '查词', '收藏难词', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'reading',
      id: 'starter-library-corner',
      title: 'The Library Corner',
      kind: 'starter_doc',
      learningPath: <String>['阅读一章', '查词', '收藏难词', '复习'],
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
      learningPath: <String>['练习', '看解析', '错题本', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'exam',
      id: 'exam:cet4:vocab:c4v2',
      title: 'CET4 词汇体验 · desire',
      kind: 'exam_item',
      familyId: 'cet4',
      skill: 'vocab',
      itemId: 'c4v2',
      learningPath: <String>['练习', '看解析', '错题本', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'exam',
      id: 'exam:cet4:reading:c4r1',
      title: 'CET4 阅读体验 · Campus Clubs',
      kind: 'exam_item',
      familyId: 'cet4',
      skill: 'reading',
      itemId: 'c4r1',
      learningPath: <String>['阅读短文', '答题', '解析', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'exam',
      id: 'exam:cet4:reading:c4r2',
      title: 'CET4 阅读体验 · Online Learning',
      kind: 'exam_item',
      familyId: 'cet4',
      skill: 'reading',
      itemId: 'c4r2',
      learningPath: <String>['阅读短文', '答题', '解析', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'exam',
      id: 'exam:cet4:listening:c4l1',
      title: 'CET4 听力体验 · Conversation: Report',
      kind: 'exam_item',
      familyId: 'cet4',
      skill: 'listening',
      itemId: 'c4l1',
      learningPath: <String>['听脚本', '答题', '精听回放', '复习'],
    ),
  ],
  'course': <FreeTrialSeedItem>[
    FreeTrialSeedItem(
      module: 'course',
      id: 'course-seed-quiet-morning',
      title: '体验课 · A Quiet Morning',
      kind: 'course_demo',
      sourceStarterId: 'starter-first-morning',
      learningPath: <String>['选课', '精读', '跟读/查词', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'course',
      id: 'course-seed-small-cafe',
      title: '体验课 · The Small Cafe',
      kind: 'course_demo',
      sourceStarterId: 'starter-small-cafe',
      learningPath: <String>['选课', '精读', '跟读/查词', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'course',
      id: 'course-seed-new-route',
      title: '体验课 · A Different Way Home',
      kind: 'course_demo',
      sourceStarterId: 'starter-new-route',
      learningPath: <String>['选课', '精读', '跟读/查词', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'course',
      id: 'course-seed-rainy-afternoon',
      title: '体验课 · A Rainy Afternoon',
      kind: 'course_demo',
      sourceStarterId: 'starter-rainy-afternoon',
      learningPath: <String>['选课', '精读', '跟读/查词', '复习'],
    ),
    FreeTrialSeedItem(
      module: 'course',
      id: 'course-seed-library-corner',
      title: '体验课 · The Library Corner',
      kind: 'course_demo',
      sourceStarterId: 'starter-library-corner',
      learningPath: <String>['选课', '精读', '跟读/查词', '复习'],
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
        : parsed.take(kModuleFreePreviewCount).toList(growable: false);
  }
  return out;
}
