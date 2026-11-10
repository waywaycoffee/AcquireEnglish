import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:common_learn_english/features/settings/presentation/bilibili_login_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved QR PNG has opaque white quiet zone', () async {
    final Uint8List png = await encodeBilibiliLoginQrPng(
      'https://passport.bilibili.com/h5-app/passport/login/scan?qrcodeKey=test',
      size: 256,
      quietZone: 24,
    );
    expect(png.length, greaterThan(100));

    final ui.Codec codec = await ui.instantiateImageCodec(png);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    expect(image.width, 256);
    expect(image.height, 256);

    final ByteData? rgba = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    image.dispose();
    expect(rgba, isNotNull);

    // Corners must be opaque white so gallery/dark UIs stay scannable.
    for (final int offset in <int>[
      0, // top-left
      (255 * 4), // top-right-ish first row end uses x=255
      ((255 * 256) * 4), // bottom-left
      (((255 * 256) + 255) * 4), // bottom-right
    ]) {
      expect(rgba!.getUint8(offset), 255); // R
      expect(rgba.getUint8(offset + 1), 255); // G
      expect(rgba.getUint8(offset + 2), 255); // B
      expect(rgba.getUint8(offset + 3), 255); // A
    }
  });
}
