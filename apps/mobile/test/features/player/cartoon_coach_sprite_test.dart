import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/player/domain/coach_animation_timeline.dart';
import '../../../lib/features/player/presentation/widgets/cartoon_coach_sprite.dart';
void main() {
  test('fixed actions and visemes select matching atlas cells', () {
    CartoonCoachSprite sprite(CoachMotion motion, CoachViseme mouth, double phase) => CartoonCoachSprite(asset: '', motion: motion, mouth: mouth, phase: phase);
    expect(sprite(CoachMotion.idle, CoachViseme.open, 0).frame, 0);
    expect(sprite(CoachMotion.idle, CoachViseme.closed, .98).frame, 5);
    expect(sprite(CoachMotion.listening, CoachViseme.closed, 0).frame, 6);
    expect(sprite(CoachMotion.thinking, CoachViseme.closed, 0).frame, 7);
    expect(sprite(CoachMotion.encouraging, CoachViseme.closed, 0).frame, 8);
    for (final CoachViseme mouth in CoachViseme.values) {
      expect(sprite(CoachMotion.speaking, mouth, 0).frame, mouth.index);
    }
  });
  testWidgets('atlas renders one bounded cell', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: SizedBox(width: 240, height: 240,
      child: CartoonCoachSprite(asset: 'assets/img/digital_human/mia-cartoon.png', motion: CoachMotion.idle, mouth: CoachViseme.closed, phase: 0)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ClipRect)), const Size(240, 240));
  });
}
