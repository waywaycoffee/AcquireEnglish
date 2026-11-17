import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/player/domain/coach_animation_timeline.dart';
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
  test('rejects overlapping cues', () {
    expect(() => CoachAnimationTimeline(const <CoachMouthCue>[
      CoachMouthCue(startMs: 0, endMs: 100, shape: CoachViseme.open),
      CoachMouthCue(startMs: 90, endMs: 200, shape: CoachViseme.wide),
    ]), throwsArgumentError);
  });
}
