import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/digital_human/domain/scene_word_label.dart';
import 'package:common_learn_english/features/digital_human/presentation/widgets/scene_photo_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drag moves one overlapping label without collecting it', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('scene-photo-test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/image.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jC0sAAAAASUVORK5CYII=',
        ),
      );
    final saved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ScenePhotoSheet(
          imagePath: file.path,
          labels: const [
            SceneWordLabel(word: 'floor'),
            SceneWordLabel(word: 'fabric'),
          ],
          savedWords: const {},
          onAddWord: (label) async {
            saved.add(label.word);
          },
          onShareWithCoach: () async {},
          onRetake: () {},
          onRefine: () async {},
        ),
      ),
    );
    final fabric = find.text('fabric');
    final floor = find.text('floor');
    final origin = tester.getCenter(fabric);
    final fixed = tester.getCenter(floor);
    await tester.drag(fabric, const Offset(100, 75));
    await tester.pump();
    expect(tester.getCenter(fabric).dx, greaterThan(origin.dx + 50));
    expect(tester.getCenter(floor), fixed);
    expect(saved, isEmpty);
    await tester.tap(floor);
    await tester.pump();
    expect(saved, ['floor']);
  });
}
