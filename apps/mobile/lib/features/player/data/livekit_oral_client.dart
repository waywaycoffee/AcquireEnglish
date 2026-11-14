import 'package:livekit_client/livekit_client.dart';

import '../../sync/data/acquire_api_client.dart';

/// Thin wrapper: mint token from API then join a LiveKit room.
class LiveKitOralClient {
  Room? _room;

  bool get isConnected => _room != null && _room!.connectionState == ConnectionState.connected;

  Room? get room => _room;

  Future<Room> connect({
    required AcquireApiClient api,
    String? preferredUrl,
    String? roomName,
  }) async {
    await disconnect();
    final AcquireLiveKitToken creds = await api.createLiveKitToken(room: roomName);
    // Token is bound to the API-issued host; settings URL is fallback only.
    final String fromApi = creds.url.trim();
    final String fromSettings = (preferredUrl ?? '').trim();
    final String url = fromApi.isNotEmpty ? fromApi : fromSettings;
    if (url.isEmpty || creds.token.isEmpty) {
      throw StateError('LiveKit 未配置或 token 无效。');
    }
    final Room room = Room();
    await room.connect(url, creds.token);
    // HTTP draft/confirm records via PronunciationMicrophone. Enabling the
    // LiveKit mic here steals the exclusive audio session on mobile and leaves
    // turns silent — keep room joined for agent audio only.
    try {
      await room.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    _room = room;
    return room;
  }

  Future<void> disconnect() async {
    final Room? room = _room;
    _room = null;
    if (room == null) {
      return;
    }
    try {
      await room.disconnect();
    } catch (_) {}
    await room.dispose();
  }
}
