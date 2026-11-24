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
    expect(sprite(CoachMotion.listening, CoachViseme.closed, 0).frame, 6);
    expect(sprite(CoachMotion.thinking, CoachViseme.closed, 0).frame, 7);
    expect(sprite(CoachMotion.encouraging, CoachViseme.closed, 0).frame, 8);
    expect(
      sprite(CoachMotion.speaking, CoachViseme.closed, 0).frame,
      CoachViseme.closed.index,
    );
    expect(
      sprite(CoachMotion.speaking, CoachViseme.open, 0).frame,
      CoachViseme.open.index,
    );
    expect(
      sprite(CoachMotion.speaking, CoachViseme.wide, 0).frame,
      CoachViseme.open.index,
    );
  });
}
