/// A recognized object/word label from a scene photo (live-style chip).
class SceneWordLabel {
  const SceneWordLabel({
    required this.word,
    this.phonetic = '',
    this.chinese = '',
    this.confidence = 0,
    this.anchorX = 0.5,
    this.anchorY = 0.42,
    this.source = 'local',
  });

  factory SceneWordLabel.fromJson(Map<String, dynamic> json) {
    return SceneWordLabel(
      word: (json['word'] as String? ?? '').trim().toLowerCase(),
      phonetic: (json['phonetic'] as String? ?? '').trim(),
      chinese: (json['chinese'] as String? ?? '').trim(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      anchorX: (json['anchor_x'] as num?)?.toDouble() ?? 0.5,
      anchorY: (json['anchor_y'] as num?)?.toDouble() ?? 0.42,
      source: (json['source'] as String? ?? 'cloud').trim(),
    );
  }

  final String word;
  final String phonetic;
  final String chinese;
  final double confidence;

  /// Normalized 0–1 position for floating chip on the photo.
  final double anchorX;
  final double anchorY;

  /// `local` (ML Kit) or `cloud` (VL refine).
  final String source;

  SceneWordLabel copyWith({
    String? word,
    String? phonetic,
    String? chinese,
    double? confidence,
    double? anchorX,
    double? anchorY,
    String? source,
  }) {
    return SceneWordLabel(
      word: word ?? this.word,
      phonetic: phonetic ?? this.phonetic,
      chinese: chinese ?? this.chinese,
      confidence: confidence ?? this.confidence,
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
      source: source ?? this.source,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'word': word,
        'phonetic': phonetic,
        'chinese': chinese,
        'confidence': confidence,
        'anchor_x': anchorX,
        'anchor_y': anchorY,
        'source': source,
      };
}
