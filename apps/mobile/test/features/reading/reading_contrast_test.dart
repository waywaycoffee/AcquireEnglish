import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_learn_english/features/reading/presentation/reading_text_spans.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('reader text remains visible under opposite app theme: $dark', (
      tester,
    ) async {
      final foreground = readingForegroundColor(dark);
      final background = readingBackgroundColor(dark);
      final light = foreground.computeLuminance();
      final surface = background.computeLuminance();
      final contrast =
          (light > surface ? light + 0.05 : surface + 0.05) /
          (light > surface ? surface + 0.05 : light + 0.05);
      expect(contrast, greaterThan(7));
      final spans = buildReadingTextSpans(
        text: 'I wake up early.',
        textColor: foreground,
        fontSize: 20,
        lineHeight: 1.7,
        dark: dark,
        showChinese: false,
        showChunks: false,
        learnedWords: {},
        hardGlosses: {},
        chunkHighlighter: null,
        onWordTap: (_, __, ___) {},
        onWordLongPress: (_, __, ___) {},
        onChunkDoubleTap: (_, __, ___) {},
        onChunkLongPress: (_, __, ___) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? ThemeData.light() : ThemeData.dark(),
          home: Scaffold(
            body: ColoredBox(
              color: background,
              child: Text.rich(TextSpan(children: spans)),
            ),
          ),
        ),
      );
      final word = tester.widget<Text>(find.text('early'));
      expect(word.style!.color, foreground);
      expect(tester.takeException(), isNull);
    });
  }
}
