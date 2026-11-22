/// Lightweight target-word pick for a unit (P0: stopwords + length; no full SUBTLEX).
const Set<String> kCourseStopWords = <String>{
  'a', 'an', 'the', 'and', 'or', 'but', 'if', 'then', 'else', 'when', 'at', 'by',
  'for', 'with', 'about', 'against', 'between', 'into', 'through', 'during',
  'before', 'after', 'above', 'below', 'to', 'from', 'up', 'down', 'in', 'out',
  'on', 'off', 'over', 'under', 'again', 'further', 'once', 'here', 'there',
  'all', 'any', 'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such',
  'no', 'nor', 'not', 'only', 'own', 'same', 'so', 'than', 'too', 'very', 'can',
  'will', 'just', 'don', 'should', 'now', 'i', 'me', 'my', 'myself', 'we', 'our',
  'you', 'your', 'he', 'him', 'his', 'she', 'her', 'it', 'its', 'they', 'them',
  'their', 'what', 'which', 'who', 'whom', 'this', 'that', 'these', 'those',
  'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has',
  'had', 'having', 'do', 'does', 'did', 'doing', 'would', 'could', 'ought',
  'i\'m', 'you\'re', 'he\'s', 'she\'s', 'it\'s', 'we\'re', 'they\'re', 'i\'ve',
  'you\'ve', 'we\'ve', 'they\'ve', 'i\'d', 'you\'d', 'he\'d', 'she\'d', 'we\'d',
  'they\'d', 'i\'ll', 'you\'ll', 'he\'ll', 'she\'ll', 'we\'ll', 'they\'ll',
  'isn\'t', 'aren\'t', 'wasn\'t', 'weren\'t', 'hasn\'t', 'haven\'t', 'hadn\'t',
  'doesn\'t', 'don\'t', 'didn\'t', 'won\'t', 'wouldn\'t', 'shan\'t', 'shouldn\'t',
  'can\'t', 'cannot', 'couldn\'t', 'mustn\'t', 'let\'s', 'that\'s', 'who\'s',
  'what\'s', 'here\'s', 'there\'s', 'when\'s', 'where\'s', 'why\'s', 'how\'s',
  'of', 'as', 'mr', 'mrs', 'ms', 'dr', 'eg', 'ie',
};

final RegExp _wordToken = RegExp(r"[A-Za-z][A-Za-z'-]{1,}");

List<String> extractCourseWordIds(
  Iterable<String> sentences, {
  int minCount = 5,
  int maxCount = 12,
}) {
  final Map<String, int> counts = <String, int>{};
  for (final String sentence in sentences) {
    for (final RegExpMatch m in _wordToken.allMatches(sentence)) {
      final String raw = m.group(0)!.toLowerCase();
      final String stem = raw.replaceAll(RegExp(r"'s$"), '');
      if (stem.length < 3) continue;
      if (kCourseStopWords.contains(stem)) continue;
      counts[stem] = (counts[stem] ?? 0) + 1;
    }
  }
  final List<MapEntry<String, int>> ranked = counts.entries.toList()
    ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
      final int byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return b.key.length.compareTo(a.key.length);
    });
  final List<String> picked = ranked
      .map((MapEntry<String, int> e) => e.key)
      .take(maxCount)
      .toList(growable: false);
  if (picked.length >= minCount) return picked;
  return picked;
}
