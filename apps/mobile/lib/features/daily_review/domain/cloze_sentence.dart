/// Build a cloze (fill-in-the-blank) prompt from a subtitle sentence.
String clozeSentence(String sentence, String word) {
  final String needle = word.trim();
  if (needle.isEmpty || sentence.trim().isEmpty) {
    return sentence.trim();
  }
  final RegExp pattern = RegExp(
    r'(?<![A-Za-z])' + RegExp.escape(needle) + r"(?![A-Za-z])",
    caseSensitive: false,
  );
  if (!pattern.hasMatch(sentence)) {
    final String last = needle.split(RegExp(r'\s+')).last;
    if (last.isNotEmpty && last.toLowerCase() != needle.toLowerCase()) {
      return clozeSentence(sentence, last);
    }
    return '${sentence.trim()}\n（找出并回忆：$needle）';
  }
  return sentence.replaceFirstMapped(
    pattern,
    (Match match) => '_' * (match.group(0)!.length.clamp(3, 12)),
  );
}

bool sentenceContainsWord(String sentence, String word) {
  final String needle = word.trim();
  if (needle.isEmpty) return false;
  return RegExp(
    r'(?<![A-Za-z])' + RegExp.escape(needle) + r"(?![A-Za-z])",
    caseSensitive: false,
  ).hasMatch(sentence);
}
