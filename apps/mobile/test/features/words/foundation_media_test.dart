import 'package:common_learn_english/features/words/domain/foundation_media.dart';
import 'package:common_learn_english/features/words/presentation/foundation_media_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lookup normalizes book keys and resolves relative urls', () {
    final FoundationMediaManifest manifest = FoundationMediaManifest.fromJson(
      <String, dynamic>{
        'version': 1,
        'count': 1,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'book_id': 'foundation_ipa_48',
            'key': 'short-a',
            'audio_url': '/media/foundation/foundation_ipa_48/short-a.mp3',
            'video_url': null,
          },
        ],
      },
    );
    expect(manifest.lookup('foundation_ipa_48', 'short a')?.hasAudio, isTrue);

    final FoundationMediaManifest resolved = manifest.withResolvedUrls(
      'https://acquireenglish.curlhairai.com/',
    );
    expect(
      resolved.lookup('foundation_ipa_48', 'short a')!.audioUrl,
      'https://acquireenglish.curlhairai.com/media/foundation/foundation_ipa_48/short-a.mp3',
    );

    expect(
      foundationMediaForReviewKey(
        resolved,
        'syllabus:foundation_ipa_48:short a',
      )?.hasAudio,
      isTrue,
    );
  });
}
