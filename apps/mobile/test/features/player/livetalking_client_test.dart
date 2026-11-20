import 'package:common_learn_english/features/digital_human/data/livetalking_client.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults prefer public HTTPS (no Tailscale on phones)', () {
    expect(defaultLiveTalkingUrlPublic, startsWith('https://'));
    expect(defaultLiveTalkingUrlPublic, contains('curlhairai.com/livetalking'));
    expect(defaultLiveTalkingUrl, defaultLiveTalkingUrlPublic);
    expect(liveTalkingUrlCandidates.first, defaultLiveTalkingUrlPublic);
    expect(defaultLiveTalkingAvatarId, 'wav2lip_avatar_glass_man');
    expect(defaultLiveTalkingIceServers, isNotEmpty);
    expect(
      defaultLiveTalkingIceServers.any(
        (Map<String, dynamic> s) => '${s['urls']}'.contains('turn.curlhairai'),
      ),
      isTrue,
    );
  });

  test('fresh client is disconnected without media', () {
    final LiveTalkingClient client = LiveTalkingClient();
    expect(client.isConnected, isFalse);
    expect(client.hasRemoteVideo, isFalse);
    expect(client.sessionId, isNull);
    expect(client.renderer, isNull);
  });
}
