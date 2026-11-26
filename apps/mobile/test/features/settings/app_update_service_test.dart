import 'package:common_learn_english/features/settings/data/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts only the official HTTPS downloads channel', () {
    expect(
      isOfficialAndroidDownloadUrl(
        'https://acquireenglish.curlhairai.com/downloads/AcquireEnglish-android-latest.apk',
      ),
      isTrue,
    );
    expect(
      isOfficialAndroidDownloadUrl(
        'http://acquireenglish.curlhairai.com/downloads/app.apk',
      ),
      isFalse,
    );
    expect(
      isOfficialAndroidDownloadUrl(
        'https://github.com/example/releases/download/app.apk',
      ),
      isFalse,
    );
    expect(
      isOfficialAndroidDownloadUrl(
        'https://acquireenglish.curlhairai.com/other/app.apk',
      ),
      isFalse,
    );
  });
}
