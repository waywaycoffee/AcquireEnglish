import '../presentation/word_book_provider.dart';

/// Export favorite vocab entries as Obsidian-friendly Markdown.
String exportVocabMarkdown(List<WordEntry> words) {
  final List<WordEntry> favorites =
      words.where((WordEntry w) => w.favorite).toList()
        ..sort((WordEntry a, WordEntry b) => a.word.compareTo(b.word));
  final StringBuffer buffer = StringBuffer('# AcquireEnglish 词库\n\n');
  for (final WordEntry entry in favorites) {
    buffer.writeln('## ${entry.word}');
    if ((entry.phonetic ?? '').trim().isNotEmpty) {
      buffer.writeln('*${entry.phonetic!.trim()}*');
      buffer.writeln();
    }
    final String gloss = entry.primaryGloss;
    if (gloss.isNotEmpty) {
      buffer.writeln('- 释义：$gloss');
    }
    if ((entry.cefr ?? '').isNotEmpty) {
      buffer.writeln('- CEFR：${entry.cefr}');
    }
    buffer.writeln('- 状态：${entry.scheduleStatus.label}');
    if (entry.tags.isNotEmpty) {
      buffer.writeln('- 标签：${entry.tags.join(', ')}');
    }
    if (entry.note.trim().isNotEmpty) {
      buffer.writeln('- 笔记：${entry.note.trim()}');
    }
    if (entry.sourceSentence.isNotEmpty) {
      buffer.writeln('- 主例句：${entry.sourceSentence}');
      if (entry.sourceSentenceCn.isNotEmpty) {
        buffer.writeln('  - ${entry.sourceSentenceCn}');
      }
      if (entry.occurrences.isNotEmpty) {
        final WordOccurrence o = entry.occurrences.first;
        buffer.writeln('  - 来源：${o.course} · ${o.episode} · ${o.time}');
      }
    }
    buffer.writeln();
  }
  return buffer.toString();
}
