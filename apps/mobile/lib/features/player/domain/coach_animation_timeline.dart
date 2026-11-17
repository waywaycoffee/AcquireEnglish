/// Fixed character states; speech timing comes from the audio playback clock.
enum CoachMotion { idle, listening, thinking, speaking, encouraging }
enum CoachViseme { closed, open, wide, rounded, teeth }

class CoachMouthCue {
  const CoachMouthCue({required this.startMs, required this.endMs, required this.shape});
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
        throw ArgumentError('Mouth cues must be ordered, non-overlapping and positive.');
      }
      previousEnd = cue.endMs;
    }
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
