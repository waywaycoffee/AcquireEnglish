import 'package:common_learn_english/features/digital_human/presentation/digital_human_picker.dart';
import 'package:common_learn_english/features/digital_human/presentation/widgets/cartoon_coach_sprite.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PickerSettings extends LearningSettingsNotifier {
  @override
  LearningSettingsState build() => LearningSettingsState.defaults();

  @override
  void setCartoonDigitalHuman(bool value) {
    state = state.copyWith(cartoonDigitalHuman: value);
  }
}

void main() {
  testWidgets('persona cards switch between photo and cartoon', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [learningSettingsProvider.overrideWith(_PickerSettings.new)],
        child: const MaterialApp(home: Scaffold(body: DigitalHumanPicker())),
      ),
    );
    expect(find.byType(CartoonCoachSprite), findsWidgets);
    await tester.tap(find.text('真人版'));
    await tester.pumpAndSettle();
    expect(find.byType(CartoonCoachSprite), findsNothing);
    final Iterable<Image> photos = tester.widgetList<Image>(find.byType(Image));
    expect(
      photos.any(
        (Image image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName.endsWith('/mia.webp'),
      ),
      isTrue,
    );
    await tester.tap(find.text('卡通版'));
    await tester.pumpAndSettle();
    final Iterable<CartoonCoachSprite> sprites = tester
        .widgetList<CartoonCoachSprite>(find.byType(CartoonCoachSprite));
    expect(
      sprites.any(
        (CartoonCoachSprite sprite) =>
            sprite.asset.endsWith('/mia-cartoon.webp') && sprite.frame == 0,
      ),
      isTrue,
    );
  });
}
