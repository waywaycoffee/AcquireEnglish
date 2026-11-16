import 'package:common_learn_english/features/player/presentation/widgets/hardsub_mosaic_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows mosaic when enabled and hides when disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: HardsubMosaicCover(enabled: true),
          ),
        ),
      ),
    );
    expect(find.textContaining('拖动手柄'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: HardsubMosaicCover(enabled: false),
          ),
        ),
      ),
    );
    expect(find.textContaining('拖动手柄'), findsNothing);
  });

  testWidgets('vertical drag on band moves bottom inset', (
    WidgetTester tester,
  ) async {
    HardsubMosaicBand? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 200,
            child: HardsubMosaicCover(
              enabled: true,
              band: const HardsubMosaicBand(
                bottomFraction: 0.0,
                heightFraction: 0.30,
              ),
              onBandChanged: (HardsubMosaicBand band) => latest = band,
            ),
          ),
        ),
      ),
    );

    // Drag near the middle of the mosaic strip (not the thin top handle).
    final Offset center = tester.getCenter(find.textContaining('拖动手柄'));
    await tester.dragFrom(center, const Offset(0, 24));
    await tester.pumpAndSettle();
    expect(latest, isNotNull);
    expect(latest!.bottomFraction, greaterThan(0));
  });

  test('band clamp keeps height and bottom in range', () {
    final HardsubMosaicBand band = const HardsubMosaicBand(
      bottomFraction: 0.9,
      heightFraction: 0.8,
    ).clamped();
    expect(band.heightFraction, lessThanOrEqualTo(0.55));
    expect(band.bottomFraction + band.heightFraction, lessThanOrEqualTo(1.0));
  });
}
