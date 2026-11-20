import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/digital_human/domain/coach_animation_timeline.dart';
void main() {
  test('mouth follows audio time, pauses, gaps and seeks', () {
    final CoachAnimationTimeline timeline = CoachAnimationTimeline(const <CoachMouthCue>[
      CoachMouthCue(startMs: 100, endMs: 200, shape: CoachViseme.open),
      CoachMouthCue(startMs: 250, endMs: 400, shape: CoachViseme.rounded),
    ]);
    expect(timeline.mouthAt(const Duration(milliseconds: 150), playing: true), CoachViseme.open);
    expect(timeline.mouthAt(const Duration(milliseconds: 150), playing: false), CoachViseme.closed);
    expect(timeline.mouthAt(const Duration(milliseconds: 220), playing: true), CoachViseme.closed);
    expect(timeline.mouthAt(const Duration(milliseconds: 300), playing: true), CoachViseme.rounded);
    expect(timeline.mouthAt(const Duration(milliseconds: 150), playing: true), CoachViseme.open);
    expect(timeline.mouthAt(const Duration(seconds: 1), playing: true), CoachViseme.closed);
  });
  test('estimated mouth cues vary within a word and close for punctuation', () {
    final CoachAnimationTimeline timeline =
        CoachAnimationTimeline.estimate('Move!', const Duration(seconds: 1));
    expect(
      timeline.cues.map((CoachMouthCue cue) => cue.shape),
      <CoachViseme>[
        CoachViseme.closed,
        CoachViseme.rounded,
        CoachViseme.teeth,
        CoachViseme.wide,
        CoachViseme.closed,
      ],
    );
    expect(timeline.cues.last.endMs, 1000);
    expect(
      CoachAnimationTimeline.estimate('', Duration.zero).cues,
      isEmpty,
    );
  });
  test('rejects overlapping cues', () {
    expect(() => CoachAnimationTimeline(const <CoachMouthCue>[
      CoachMouthCue(startMs: 0, endMs: 100, shape: CoachViseme.open),
      CoachMouthCue(startMs: 90, endMs: 200, shape: CoachViseme.wide),
    ]), throwsArgumentError);
  });
}
