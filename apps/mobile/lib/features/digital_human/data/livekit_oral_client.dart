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
  bool _agentReady = false;
  String? _agentIdentity;
  Timer? _replyTimeout;
  Timer? _reconnectTimeout;
  int _connectionGeneration = 0;
  bool _learnerSpeaking = false;
  int _latestTurn = 0;

  void _expectReply() {
    _replyTimeout?.cancel();
    _replyTimeout = Timer(const Duration(seconds: 15), () {
      onUnavailable?.call();
    });
  }

  void Function()? onUnavailable;
  LiveKitAgentTextHandler? onUserText;
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
    final disconnecting = disconnect();
    final generation = _connectionGeneration;
    await disconnecting;
    final AcquireLiveKitToken creds = await api
        .createLiveKitToken(room: roomName)
        .timeout(const Duration(seconds: 10));
    if (generation != _connectionGeneration) {
      throw StateError('语音连接已取消');
    }
    final String fromApi = creds.url.trim();
    final String fromSettings = (preferredUrl ?? '').trim();
    final String url = fromApi.isNotEmpty ? fromApi : fromSettings;
    if (url.isEmpty || creds.token.isEmpty) {
      throw StateError('LiveKit 未配置或 token 无效。');
    }
    final Room room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    onStatus?.call('正在连接实时语音…');
    _room = room;
    final EventsListener<RoomEvent> listener = room.createListener();
    _listener = listener;
    listener
      ..on<RoomDisconnectedEvent>((_) => onUnavailable?.call())
      ..on<RoomReconnectingEvent>((_) {
        _replyTimeout?.cancel();
        _reconnectTimeout?.cancel();
        onStatus?.call('正在恢复实时语音…');
        _reconnectTimeout = Timer(const Duration(seconds: 10), () {
          onUnavailable?.call();
        });
      })
      ..on<RoomReconnectedEvent>((_) {
        _reconnectTimeout?.cancel();
        _learnerSpeaking = false;
        if (context != null) unawaited(publishContext(context));
        onStatus?.call('实时语音已恢复，可以继续说');
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        if (!_agentReady) return;
        final local = room.localParticipant;
        final speaking = local != null && event.speakers.contains(local);
        if (_learnerSpeaking && !speaking) _expectReply();
        _learnerSpeaking = speaking;
        if (speaking ||
            event.speakers.any((p) => p.identity == _agentIdentity)) {
          _replyTimeout?.cancel();
        }
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        if (event.participant.identity == _agentIdentity) {
          onUnavailable?.call();
        }
      })
      ..on<DataReceivedEvent>((DataReceivedEvent event) {
        final String? topic = event.topic;
        try {
          final String raw = utf8.decode(event.data);
          final Object? decoded = jsonDecode(raw);
          final Map<String, dynamic>? map = decoded is Map<String, dynamic>
              ? decoded
              : (decoded is Map ? Map<String, dynamic>.from(decoded) : null);
          if (map == null) return;
          final participant = event.participant;
          if (participant == null) return;
          if (topic == 'coach.ready' && map['ready'] == true) {
            _agentReady = true;
            _agentIdentity = participant.identity;
            return;
          }
          if (participant.identity != _agentIdentity) return;
          if (topic == 'coach.turn') {
            final turn = map['turn'];
            if (turn is int) {
              if (turn <= _latestTurn) return;
              _latestTurn = turn;
            }
            _expectReply();
            final text = map['text'];
            if (text is String && text.trim().isNotEmpty)
              onUserText?.call(text);
            return;
          }

          if (topic == null || topic == 'score.partial' || topic == 'score') {
            onScore?.call(map);
          }
          if (topic == 'coach.text' || map['coach_text'] is String) {
            final turn = map['turn'];
            if (turn is int && turn < _latestTurn) return;
            final String text = '${map['coach_text'] ?? map['text'] ?? ''}'
                .trim();
            if (text.isNotEmpty) onAgentText?.call(text);
          }
        } catch (_) {}
      });

    try {
      await room.connect(url, creds.token).timeout(const Duration(seconds: 15));
      if (_room != room) throw StateError('语音连接已取消');
      if (enableMicrophone) {
        final publication = await room.localParticipant?.setMicrophoneEnabled(
          true,
        );
        if (publication == null) throw StateError('麦克风未发布');
      }
      if (context != null) await publishContext(context);
      return room;
    } catch (_) {
      if (_room == room) await disconnect();
      rethrow;
    }
  }

  Future<bool> awaitAgentReady(Map<String, dynamic> context) async {
    final Room? room = _room;
    final Stopwatch elapsed = Stopwatch()..start();
    while (room != null && identical(room, _room) && isConnected) {
      if (_agentReady) return true;
      if (elapsed.elapsed >= const Duration(seconds: 8)) break;
      await publishContext(context);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
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
      await local.publishData(bytes, reliable: true, topic: 'coach.context');
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _connectionGeneration++;
    _replyTimeout?.cancel();
    _reconnectTimeout?.cancel();
    _learnerSpeaking = false;
    _latestTurn = 0;
    _agentReady = false;
    _agentIdentity = null;
    final Room? room = _room;
    _room = null;
    final EventsListener<RoomEvent>? listener = _listener;
    _listener = null;
    try {
      await listener?.dispose();
    } catch (_) {}
    if (room == null) {
      return;
    }
    try {
      await room.disconnect();
    } catch (_) {}
    await room.dispose();
  }
}
