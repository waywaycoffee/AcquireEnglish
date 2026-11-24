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
    expect(sprite(CoachMotion.listening, CoachViseme.closed, 0).frame, 0);
    expect(sprite(CoachMotion.thinking, CoachViseme.closed, 0).frame, 0);
    expect(sprite(CoachMotion.encouraging, CoachViseme.closed, 0).frame, 0);
    // Speaking holds open cell only — no closed↔open thrash.
    for (final CoachViseme mouth in CoachViseme.values) {
      expect(
        sprite(CoachMotion.speaking, mouth, 0).frame,
        CoachViseme.open.index,
      );
    }
  });
}
