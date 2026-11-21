import 'package:common_learn_english/features/digital_human/presentation/digital_human_picker.dart';
import 'package:common_learn_english/features/digital_human/presentation/widgets/cartoon_coach_sprite.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PickerSettings extends LearningSettingsNotifier {
  @override
  LearningSettingsState build() => LearningSettingsState.defaults();
}

void main() {
  testWidgets('shows portraits, voice previews and Chinese support', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [learningSettingsProvider.overrideWith(_PickerSettings.new)],
        child: const MaterialApp(home: Scaffold(body: DigitalHumanPicker())),
      ),
    );
    expect(find.byType(CartoonCoachSprite), findsNothing);
    expect(find.text('卡通版'), findsNothing);
    expect(find.byTooltip('试听 Mia'), findsOneWidget);
    expect(find.text('中文另用音色'), findsWidgets);
    final Iterable<Image> photos = tester.widgetList<Image>(find.byType(Image));
    expect(
      photos.any(
        (Image image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName.endsWith('/mia.webp'),
      ),
      isTrue,
    );
    await tester.tap(find.text('儿童伙伴'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('试听 Ruby'), findsOneWidget);
    expect(find.text('中英同音色'), findsNWidgets(2));
  });
}
