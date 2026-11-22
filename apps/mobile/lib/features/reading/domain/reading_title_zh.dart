/// Known Chinese titles for public-domain / catalog classics.
const Map<String, String> kReadingTitleZhByNormalizedEnglish =
    <String, String>{
      'the wonderful wizard of oz': '绿野仙踪',
      'wonderful wizard of oz': '绿野仙踪',
      'pride and prejudice': '傲慢与偏见',
      'frankenstein': '弗兰肯斯坦',
      'dracula': '德古拉',
      "alice's adventures in wonderland": '爱丽丝漫游奇境',
      'alices adventures in wonderland': '爱丽丝漫游奇境',
      'the adventures of sherlock holmes': '福尔摩斯探案集',
      'adventures of sherlock holmes': '福尔摩斯探案集',
      'a christmas carol': '圣诞颂歌',
      'treasure island': '金银岛',
      "gulliver's travels": '格列佛游记',
      'gullivers travels': '格列佛游记',
      'the adventures of huckleberry finn': '哈克贝利·费恩历险记',
      'adventures of huckleberry finn': '哈克贝利·费恩历险记',
      'moby dick': '白鲸',
      'moby-dick': '白鲸',
    };

String normalizeReadingTitleKey(String title) {
  return title
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirst(RegExp(r'（[^）]*）\s*$'), '')
      .replaceFirst(RegExp(r'\([^)]*\)\s*$'), '')
      .trim();
}

String? readingTitleZhFor(String title, {String? titleZh}) {
  final String explicit = (titleZh ?? '').trim();
  if (explicit.isNotEmpty) return explicit;
  final String key = normalizeReadingTitleKey(title);
  if (key.isEmpty) return null;
  return kReadingTitleZhByNormalizedEnglish[key] ??
      kReadingTitleZhByNormalizedEnglish[
          key.replaceFirst(RegExp(r'^the\s+'), '')];
}

/// `The Wonderful Wizard of Oz（绿野仙踪）`
String readingDisplayTitle(String title, {String? titleZh}) {
  final String en = title
      .trim()
      .replaceFirst(RegExp(r'（[^）]*）\s*$'), '')
      .replaceFirst(RegExp(r'\([^)]*\)\s*$'), '')
      .trim();
  final String? zh = readingTitleZhFor(en, titleZh: titleZh);
  if (zh == null || zh.isEmpty) return en.isEmpty ? title.trim() : en;
  if (en.contains(zh)) return en;
  return '$en（$zh）';
}

String readingDisplayTitleForDoc({
  required String title,
  String titleZh = '',
}) =>
    readingDisplayTitle(title, titleZh: titleZh);
