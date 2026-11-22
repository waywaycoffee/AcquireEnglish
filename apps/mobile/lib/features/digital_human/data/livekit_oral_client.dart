import 'dart:async';
import 'dart:convert';

import 'package:livekit_client/livekit_client.dart';

import '../../sync/data/acquire_api_client.dart';

typedef LiveKitScoreHandler = void Function(Map<String, dynamic> score);
typedef LiveKitStatusHandler = void Function(String status);
typedef LiveKitAgentTextHandler = void Function(String text);

/// Mint token from API, join room, dispatch oral-coach agent, receive scores.
///
/// Duplex mode enables the local mic so Silero VAD / barge-in on the GPU agent
/// can hear the learner. HTTP hold-to-talk must be paused while duplex is on.
class LiveKitOralClient {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  LiveKitScoreHandler? onScore;
  LiveKitStatusHandler? onStatus;
  LiveKitAgentTextHandler? onAgentText;

  bool get isConnected =>
      _room != null && _room!.connectionState == ConnectionState.connected;

  Room? get room => _room;

  Future<Room> connect({
    required AcquireApiClient api,
    String? preferredUrl,
    String? roomName,
    bool enableMicrophone = true,
    Map<String, dynamic>? context,
  }) async {
    await disconnect();
    final AcquireLiveKitToken creds = await api.createLiveKitToken(
      room: roomName,
    );
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
      await room.localParticipant?.setMicrophoneEnabled(enableMicrophone);
    } catch (_) {}

    _room = room;
    if (context != null && context.isNotEmpty) {
      await publishContext(context);
    }

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
        final String? topic = event.topic;
        try {
          final String raw = utf8.decode(event.data);
          final Object? decoded = jsonDecode(raw);
          final Map<String, dynamic>? map = decoded is Map<String, dynamic>
              ? decoded
              : (decoded is Map
                  ? Map<String, dynamic>.from(decoded)
                  : null);
          if (map == null) return;
          if (topic == null ||
              topic == 'score.partial' ||
              topic == 'score') {
            onScore?.call(map);
          }
          if (topic == 'coach.text' || map['coach_text'] is String) {
            final String text = '${map['coach_text'] ?? map['text'] ?? ''}'.trim();
            if (text.isNotEmpty) onAgentText?.call(text);
          }
        } catch (_) {}
      });

    onStatus?.call(
      enableMicrophone
          ? '全双工已接通 · ${creds.room}'
          : '已加入 LiveKit 房间 ${creds.room}（仅听）',
    );
    return room;
  }

  bool get hasRemoteParticipant {
    final Room? room = _room;
    if (room == null) return false;
    return room.remoteParticipants.isNotEmpty;
  }

  /// Wait until a remote agent joins, or [timeout] elapses.
  Future<bool> awaitRemoteParticipant({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final Room? room = _room;
    if (room == null) return false;
    if (room.remoteParticipants.isNotEmpty) return true;

    final Completer<bool> done = Completer<bool>();
    Timer? timer;
    EventsListener<RoomEvent>? waitListener;
    void finish(bool value) {
      if (done.isCompleted) return;
      done.complete(value);
      timer?.cancel();
      final EventsListener<RoomEvent>? toDispose = waitListener;
      waitListener = null;
      if (toDispose != null) {
        unawaited(
          () async {
            try {
              await toDispose.dispose();
            } catch (_) {}
          }(),
        );
      }
    }

    waitListener = room.createListener()
      ..on<ParticipantConnectedEvent>((_) => finish(true))
      ..on<TrackSubscribedEvent>((_) => finish(true));
    // Cover the race where the agent joined between the emptiness check and
    // listener attachment.
    if (room.remoteParticipants.isNotEmpty) {
      finish(true);
    } else {
      timer = Timer(timeout, () => finish(false));
    }
    return done.future;
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
    } catch (_) {}
  }

  Future<void> publishContext(Map<String, dynamic> context) async {
    final LocalParticipant? local = _room?.localParticipant;
    if (local == null) return;
    try {
      final List<int> bytes = utf8.encode(jsonEncode(context));
      await local.publishData(
        bytes,
        reliable: true,
        topic: 'coach.context',
      );
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
      await room.disconnect();
    } catch (_) {}
    await room.dispose();
  }
}
