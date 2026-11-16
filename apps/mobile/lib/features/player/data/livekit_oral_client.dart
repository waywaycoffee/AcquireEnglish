import 'dart:async';
import 'dart:convert';

import 'package:livekit_client/livekit_client.dart';

import '../../sync/data/acquire_api_client.dart';

typedef LiveKitScoreHandler = void Function(Map<String, dynamic> score);
typedef LiveKitStatusHandler = void Function(String status);

/// Mint token from API, join room, dispatch oral-coach agent, receive scores.
class LiveKitOralClient {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  LiveKitScoreHandler? onScore;
  LiveKitStatusHandler? onStatus;

  bool get isConnected =>
      _room != null && _room!.connectionState == ConnectionState.connected;

  Room? get room => _room;

  Future<Room> connect({
    required AcquireApiClient api,
    String? preferredUrl,
    String? roomName,
  }) async {
    await disconnect();
    final AcquireLiveKitToken creds = await api.createLiveKitToken(
      room: roomName,
    );
    // Token is bound to the API-issued host; settings URL is fallback only.
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
    // HTTP draft/confirm records via PronunciationMicrophone. Enabling the
    // LiveKit mic here steals the exclusive audio session on mobile and leaves
    // turns silent — keep room joined for agent audio + DataChannel scores.
    try {
      await room.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}

    final EventsListener<RoomEvent> listener = room.createListener();
    _listener = listener;
    listener
      ..on<ParticipantConnectedEvent>((ParticipantConnectedEvent event) {
        onStatus?.call('外教 Agent 已进房：${event.participant.identity}');
      })
      ..on<TrackSubscribedEvent>((TrackSubscribedEvent event) {
        onStatus?.call(
          '已订阅 Agent ${event.track.kind.name}'
          '（${event.participant.identity}）',
        );
      })
      ..on<DataReceivedEvent>((DataReceivedEvent event) {
        if (event.topic != null &&
            event.topic != 'score.partial' &&
            event.topic != 'score') {
          return;
        }
        try {
          final String raw = utf8.decode(event.data);
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            onScore?.call(decoded);
          } else if (decoded is Map) {
            onScore?.call(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      });

    _room = room;
    onStatus?.call('已加入 LiveKit 房间 ${creds.room}');
    return room;
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
      await room.disconnect();
    } catch (_) {}
    await room.dispose();
  }
}
