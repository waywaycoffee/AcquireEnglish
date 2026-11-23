import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../sync/data/acquire_api_client.dart';

typedef LiveKitScoreHandler = void Function(Map<String, dynamic> score);
typedef LiveKitStatusHandler = void Function(String status);
typedef LiveKitAgentTextHandler = void Function(String text);

/// Mint token from API, join room, dispatch oral-coach agent, receive scores.
///
/// Duplex mode keeps the local mic published so Silero VAD / barge-in on the
/// GPU agent can hear the learner while the coach is speaking.
class LiveKitOralClient {
  Room? _room;
  bool _agentReady = false;
  String? _agentIdentity;
  Timer? _replyTimeout;
  Timer? _reconnectTimeout;
  int _connectionGeneration = 0;
  bool _learnerSpeaking = false;
  bool _agentSpeaking = false;
  bool _liveKitBootstrapped = false;
  void Function(bool learner, bool agent)? onSpeakingChanged;
  int _latestTurn = 0;

  static const AudioCaptureOptions _duplexMicOptions = AudioCaptureOptions(
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
    // Keep the capture pipeline alive when toggling mute so barge-in stays
    // responsive (stop/replace would drop frames mid-agent turn).
    stopAudioCaptureOnMute: false,
  );

  /// Soft wait only — never tear down the room when the coach is slow to reply.
  void _expectReply() {
    _replyTimeout?.cancel();
    _replyTimeout = Timer(const Duration(seconds: 45), () {
      if (!isConnected || !_agentReady) return;
      onStatus?.call('外教还在组织回复，请继续说或稍等');
    });
  }

  void _clearReplyWait() {
    _replyTimeout?.cancel();
    _replyTimeout = null;
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

  Future<void> _ensureLiveKitAudioBootstrap() async {
    if (_liveKitBootstrapped) return;
    _liveKitBootstrapped = true;
    if (kIsWeb) return;
    try {
      // Voice-call audio attributes so Android/iOS keep full-duplex AEC path.
      await LiveKitClient.initialize(
        initialAudioSessionOptions: const AudioSessionOptions.communication(),
      );
    } catch (_) {}
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(true, force: true);
    } catch (_) {}
  }

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
    await _ensureLiveKitAudioBootstrap();
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
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: _duplexMicOptions,
      ),
    );
    onStatus?.call('正在连接实时语音…');
    _room = room;
    final EventsListener<RoomEvent> listener = room.createListener();
    _listener = listener;
    listener
      ..on<RoomDisconnectedEvent>((_) => onUnavailable?.call())
      ..on<RoomReconnectingEvent>((_) {
        _clearReplyWait();
        _reconnectTimeout?.cancel();
        onStatus?.call('正在恢复实时语音…');
        _reconnectTimeout = Timer(const Duration(seconds: 10), () {
          onUnavailable?.call();
        });
      })
      ..on<RoomReconnectedEvent>((_) {
        _reconnectTimeout?.cancel();
        _clearSpeaking();
        if (context != null) unawaited(publishContext(context));
        // Re-assert open mic after reconnect so barge-in keeps working.
        unawaited(setMicrophoneEnabled(true));
        onStatus?.call('实时语音已恢复，可以继续说');
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        if (!_agentReady) return;
        final local = room.localParticipant;
        final learner = local != null && event.speakers.contains(local);
        final agent = event.speakers.any((Participant p) {
          if (identical(p, local)) return false;
          if (_agentIdentity == null) return true;
          return p.identity == _agentIdentity;
        });
        if (_learnerSpeaking && !learner) _expectReply();
        if (learner || agent) _clearReplyWait();
        if (learner != _learnerSpeaking || agent != _agentSpeaking) {
          _learnerSpeaking = learner;
          _agentSpeaking = agent;
          onSpeakingChanged?.call(learner, agent);
        }
      })
      ..on<TrackSubscribedEvent>((TrackSubscribedEvent event) {
        if (event.track.kind == TrackType.AUDIO &&
            !identical(event.participant, room.localParticipant)) {
          _agentIdentity ??= event.participant.identity;
          _clearReplyWait();
        }
      })
      ..on<ParticipantDisconnectedEvent>((ParticipantDisconnectedEvent event) {
        if (_agentIdentity != null &&
            event.participant.identity == _agentIdentity) {
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
            _clearReplyWait();
            return;
          }
          if (_agentIdentity != null &&
              participant.identity != _agentIdentity) {
            return;
          }
          if (topic == 'coach.turn') {
            final turn = map['turn'];
            if (turn is int) {
              if (turn <= _latestTurn) return;
              _latestTurn = turn;
            }
            _expectReply();
            final text = map['text'];
            if (text is String && text.trim().isNotEmpty) {
              onUserText?.call(text);
            }
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
            if (text.isNotEmpty) {
              _clearReplyWait();
              onAgentText?.call(text);
            }
          }
        } catch (_) {}
      });

    try {
      await room.connect(url, creds.token).timeout(const Duration(seconds: 15));
      if (_room != room) throw StateError('语音连接已取消');
      try {
        await AudioManager.instance.setSpeakerOutputPreferred(true, force: true);
      } catch (_) {}
      if (enableMicrophone) {
        final publication = await room.localParticipant?.setMicrophoneEnabled(
          true,
          audioCaptureOptions: _duplexMicOptions,
        );
        if (publication == null) throw StateError('麦克风未发布');
      }
      if (context != null) await publishContext(context);
      onStatus?.call('实时麦已打开，可直接说');
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
      await _room?.localParticipant?.setMicrophoneEnabled(
        enabled,
        audioCaptureOptions: _duplexMicOptions,
      );
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

  void _clearSpeaking() {
    if (!_learnerSpeaking && !_agentSpeaking) return;
    _learnerSpeaking = false;
    _agentSpeaking = false;
    onSpeakingChanged?.call(false, false);
  }

  Future<void> disconnect() async {
    _connectionGeneration++;
    _clearReplyWait();
    _reconnectTimeout?.cancel();
    _clearSpeaking();
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
