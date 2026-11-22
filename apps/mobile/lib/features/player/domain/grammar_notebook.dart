class GrammarNote {
  const GrammarNote({
    required this.id,
    required this.sentence,
    required this.episodeId,
    this.structure = '',
    this.grammarPoints = const <String>[],
    this.keyPhrases = const <String>[],
    this.translation = '',
    this.createdAtMs = 0,
  });

  final String id;
  final String sentence;
  final String episodeId;
  final String structure;
  final List<String> grammarPoints;
  final List<String> keyPhrases;
  final String translation;
  final int createdAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sentence': sentence,
        'episodeId': episodeId,
        'structure': structure,
        'grammarPoints': grammarPoints,
        'keyPhrases': keyPhrases,
        'translation': translation,
        'createdAtMs': createdAtMs,
      };

  factory GrammarNote.fromJson(Map<String, dynamic> json) {
    return GrammarNote(
      id: (json['id'] as String? ?? '').trim(),
      sentence: (json['sentence'] as String? ?? '').trim(),
      episodeId: (json['episodeId'] as String? ?? '').trim(),
      structure: (json['structure'] as String? ?? '').trim(),
      grammarPoints: (json['grammarPoints'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => '$e'.trim())
          .where((String s) => s.isNotEmpty)
          .toList(),
      keyPhrases: (json['keyPhrases'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => '$e'.trim())
          .where((String s) => s.isNotEmpty)
          .toList(),
      translation: (json['translation'] as String? ?? '').trim(),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
