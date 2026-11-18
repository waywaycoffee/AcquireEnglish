/// Fixed character states; speech timing comes from the audio playback clock.
enum CoachMotion { idle, listening, thinking, speaking, encouraging }

enum CoachViseme { closed, open, wide, rounded, teeth }

class CoachMouthCue {
  const CoachMouthCue({
    required this.startMs,
    required this.endMs,
    required this.shape,
  });
  final int startMs;
  final int endMs;
  final CoachViseme shape;
}

/// Accepts timestamped mouth shapes from TTS/phoneme alignment. It deliberately
/// does not infer synchronization from an idle animation or wall-clock timer.
class CoachAnimationTimeline {
  CoachAnimationTimeline(Iterable<CoachMouthCue> cues)
    : cues = List<CoachMouthCue>.unmodifiable(cues) {
    int previousEnd = 0;
    for (final CoachMouthCue cue in this.cues) {
      if (cue.startMs < previousEnd || cue.endMs <= cue.startMs) {
        throw ArgumentError(
          'Mouth cues must be ordered, non-overlapping and positive.',
        );
      }
      previousEnd = cue.endMs;
    }
  }
  // Fallback for audio without phoneme timestamps. Weight pronounced
  // letter groups and pauses, then fit them to the actual audio duration.
  factory CoachAnimationTimeline.estimate(String text, Duration duration) {
    final List<({CoachViseme shape, int weight})> shapes = [];
    final RegExp groups = RegExp(
      r'[aeiouy]+|[bmp]|[fv]|[.!?,;:，。！？、]|[a-z]|[^\s]',
      unicode: true,
    );
    for (final Match match in groups.allMatches(text.toLowerCase())) {
      final String group = match[0]!;
      final (CoachViseme shape, int weight) = switch (group[0]) {
        'b' || 'm' || 'p' => (CoachViseme.closed, 2),
        'f' || 'v' => (CoachViseme.teeth, 2),
        'o' || 'u' => (CoachViseme.rounded, 4),
        'e' || 'i' || 'y' => (CoachViseme.wide, 4),
        'a' => (CoachViseme.open, 4),
        '.' || '!' || '?' || '。' || '！' || '？' => (CoachViseme.closed, 8),
        ',' || ';' || ':' || '，' || '、' => (CoachViseme.closed, 5),
        _ => (CoachViseme.open, 1),
      };
      shapes.add((shape: shape, weight: weight));
    }
    final int totalWeight = shapes.fold(
      0,
      (int sum, item) => sum + item.weight,
    );
    final List<CoachMouthCue> cues = [];
    int elapsedWeight = 0;
    int startMs = 0;
    for (final item in shapes) {
      elapsedWeight += item.weight;
      final int endMs = duration.inMilliseconds * elapsedWeight ~/ totalWeight;
      if (endMs > startMs) {
        cues.add(
          CoachMouthCue(startMs: startMs, endMs: endMs, shape: item.shape),
        );
        startMs = endMs;
      }
    }
    return CoachAnimationTimeline(cues);
  }

  final List<CoachMouthCue> cues;
  CoachViseme mouthAt(Duration audioPosition, {required bool playing}) {
    if (!playing || audioPosition.isNegative) return CoachViseme.closed;
    final int ms = audioPosition.inMilliseconds;
    for (final CoachMouthCue cue in cues) {
      if (ms < cue.startMs) break;
      if (ms < cue.endMs) return cue.shape;
    }
    return CoachViseme.closed;
  }
}
