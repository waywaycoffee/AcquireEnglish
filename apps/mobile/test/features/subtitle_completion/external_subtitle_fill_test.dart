import 'package:common_learn_english/features/subtitle_completion/external_subtitle_fill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ExternalSubtitleFill reports unavailable on mobile-shaped hosts', () async {
    // On CI / analyzer hosts without tools/subtitle/.venv this is typically
    // false; the important contract is that fillMissing returns null instead
    // of throwing when the sidecar is missing.
    const ExternalSubtitleFill fill = ExternalSubtitleFill();
    final ExternalSubtitleFillResult? result = await fill.fillMissing(
      videoPath: '/tmp/does-not-exist-acquire-english.mp4',
      outDir: '/tmp/acquire-english-fill-out',
      needEnglish: true,
      needChinese: false,
    );
    expect(result, isNull);
  });
}
