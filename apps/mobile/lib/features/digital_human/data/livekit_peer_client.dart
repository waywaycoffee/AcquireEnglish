import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

import '../../sync/data/acquire_api_client.dart';

typedef LiveKitPeerStatusHandler = void Function(String status);
typedef LiveKitPeerPresenceHandler = void Function({required bool peerConnected});

/// LiveKit audio room for 1:1 peer oral practice (no coach agent).
class LiveKitPeerClient {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  LiveKitPeerStatusHandler? onStatus;
  LiveKitPeerPresenceHandler? onPeerPresence;

  bool get isConnected =>
      _room != null && _room!.connectionState == ConnectionState.connected;

  bool get micEnabled =>
      _room?.localParticipant?.isMicrophoneEnabled() ?? false;

  Future<void> connectWithToken({
    required AcquireLiveKitToken creds,
    String? preferredUrl,
  }) async {
    await disconnect();
    final String fromApi = creds.url.trim();
    final String fromSettings = (preferredUrl ?? '').trim();
    final String url = fromApi.isNotEmpty ? fromApi : fromSettings;
    if (url.isEmpty || creds.token.isEmpty) {
      throw StateError('LiveKit 未配置或 token 无效。');
    }
    final Room room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ),
    );
    await room.connect(url, creds.token);
    try {
      await room.localParticipant?.setMicrophoneEnabled(true);
    } catch (_) {}

    final EventsListener<RoomEvent> listener = room.createListener();
    _listener = listener;
    listener
      ..on<ParticipantConnectedEvent>((ParticipantConnectedEvent event) {
        if (event.participant is RemoteParticipant) {
          onPeerPresence?.call(peerConnected: true);
          onStatus?.call('对方已进入语音房间');
        }
      })
      ..on<ParticipantDisconnectedEvent>((ParticipantDisconnectedEvent event) {
        if (event.participant is RemoteParticipant) {
          onPeerPresence?.call(peerConnected: false);
          onStatus?.call('对方语音已断开');
        }
      })
      ..on<TrackSubscribedEvent>((TrackSubscribedEvent event) {
        if (event.track.kind == TrackType.AUDIO) {
          onStatus?.call('已接通对方语音');
          onPeerPresence?.call(peerConnected: true);
        }
      })
      ..on<RoomDisconnectedEvent>((RoomDisconnectedEvent event) {
        onStatus?.call('语音房间已断开');
        onPeerPresence?.call(peerConnected: false);
      });

    // Someone may already be in the room.
    final bool peerAlreadyHere = room.remoteParticipants.isNotEmpty;
    if (peerAlreadyHere) {
      onPeerPresence?.call(peerConnected: true);
    }

    _room = room;
    onStatus?.call('语音已连接 · ${creds.room}');
  }

  Future<void> setMicrophoneEnabled({required bool enabled}) async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
    } catch (_) {}
  }

  Future<void> disconnect() async {
    final EventsListener<RoomEvent>? listener = _listener;
    _listener = null;
    try {
      await listener?.dispose();
    } catch (_) {}
    final Room? room = _room;
    _room = null;
    if (room == null) {
      return;
    }
    try {
      await room.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    try {
      await room.disconnect();
    } catch (_) {}
    await room.dispose();
  }
}
