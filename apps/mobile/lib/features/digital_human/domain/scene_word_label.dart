/// A recognized object/word label from a scene photo (live-style chip).
class SceneWordLabel {
  const SceneWordLabel({
    required this.word,
    this.phonetic = '',
    this.chinese = '',
    this.confidence = 0,
    this.anchorX = 0.5,
    this.anchorY = 0.42,
  });

  final String word;
  final String phonetic;
  final String chinese;
  final double confidence;

  /// Normalized 0–1 position for floating chip on the photo.
  final double anchorX;
  final double anchorY;

  SceneWordLabel copyWith({
    String? word,
    String? phonetic,
    String? chinese,
    double? confidence,
    double? anchorX,
    double? anchorY,
  }) {
    return SceneWordLabel(
      word: word ?? this.word,
      phonetic: phonetic ?? this.phonetic,
      chinese: chinese ?? this.chinese,
      confidence: confidence ?? this.confidence,
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'word': word,
    'phonetic': phonetic,
    'chinese': chinese,
    'confidence': confidence,
    'anchor_x': anchorX,
    'anchor_y': anchorY,
  };
}
