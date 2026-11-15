import 'package:common_learn_english/features/player/data/livetalking_client.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults point at Tailscale MagicDNS and glass_man avatar', () {
    expect(defaultLiveTalkingUrl, contains('5060ti.tailc30b42.ts.net'));
    expect(defaultLiveTalkingUrl, startsWith('http://'));
    expect(defaultLiveTalkingUrlIp, contains('100.115.252.55'));
    expect(defaultLiveTalkingAvatarId, 'wav2lip_avatar_glass_man');
  });

  test('fresh client is disconnected without media', () {
    final LiveTalkingClient client = LiveTalkingClient();
    expect(client.isConnected, isFalse);
    expect(client.hasRemoteVideo, isFalse);
    expect(client.sessionId, isNull);
    expect(client.renderer, isNull);
  });
}
