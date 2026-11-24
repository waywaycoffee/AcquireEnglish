import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/features/digital_human/domain/coach_animation_timeline.dart';
import '../../../lib/features/digital_human/presentation/widgets/cartoon_coach_sprite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fixed actions and visemes select matching atlas cells', () {
    CartoonCoachSprite sprite(
      CoachMotion motion,
      CoachViseme mouth,
      double phase,
    ) => CartoonCoachSprite(
      asset: '',
      motion: motion,
      mouth: mouth,
      phase: phase,
    );
    expect(sprite(CoachMotion.idle, CoachViseme.open, 0).frame, 0);
    expect(sprite(CoachMotion.idle, CoachViseme.closed, .98).frame, 5);
    expect(sprite(CoachMotion.listening, CoachViseme.closed, 0).frame, 6);
    expect(sprite(CoachMotion.thinking, CoachViseme.closed, 0).frame, 7);
    expect(sprite(CoachMotion.encouraging, CoachViseme.closed, 0).frame, 8);
    for (final CoachViseme mouth in CoachViseme.values) {
      expect(sprite(CoachMotion.speaking, mouth, 0).frame, mouth.index);
    }
  });
}
