import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Minimal LiveTalking WebRTC client (open-source realtime digital human).
///
/// Server: `python app.py --transport webrtc ...` then open `/offer` + `/human`.
class LiveTalkingClient {
  LiveTalkingClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  RTCPeerConnection? _pc;
  RTCVideoRenderer? _renderer;
  String? _sessionId;
  String? _baseUrl;

  RTCVideoRenderer? get renderer => _renderer;
  String? get sessionId => _sessionId;
  bool get isConnected => _sessionId != null && _pc != null;

  Future<RTCVideoRenderer> connect(String rawBaseUrl) async {
    await disconnect();
    final String baseUrl = _normalizeBaseUrl(rawBaseUrl);
    _baseUrl = baseUrl;

    final RTCVideoRenderer renderer = RTCVideoRenderer();
    await renderer.initialize();
    _renderer = renderer;

    final RTCPeerConnection pc = await createPeerConnection(<String, dynamic>{
      'sdpSemantics': 'unified-plan',
      'iceServers': <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    _pc = pc;

    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) {
        return;
      }
      renderer.srcObject = event.streams.first;
    };

    final RTCSessionDescription offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _waitIceGatheringComplete(pc);

    final RTCSessionDescription? local = await pc.getLocalDescription();
    if (local?.sdp == null || local!.sdp!.isEmpty) {
      throw StateError('LiveTalking 未能生成本地 SDP。');
    }

    final Response<dynamic> response = await _dio.post<dynamic>(
      '$baseUrl/offer',
      data: <String, Object?>{'type': 'offer', 'sdp': local.sdp},
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final Map<String, dynamic> body = _asMap(response.data);
    final String? answerSdp = body['sdp'] as String?;
    final String? answerType = body['type'] as String?;
    final Object? session = body['sessionid'];
    if (answerSdp == null ||
        answerSdp.isEmpty ||
        answerType == null ||
        session == null) {
      throw StateError('LiveTalking /offer 返回无效，请检查服务是否已启动。');
    }
    await pc.setRemoteDescription(
      RTCSessionDescription(answerSdp, answerType),
    );
    _sessionId = session.toString();
    return renderer;
  }

  /// Speak [text]. Use type `echo` for scripted demo, `chat` for LLM reply.
  Future<void> speak(
    String text, {
    String type = 'echo',
    bool interrupt = true,
  }) async {
    final String? baseUrl = _baseUrl;
    final String? sessionId = _sessionId;
    final String trimmed = text.trim();
    if (baseUrl == null || sessionId == null) {
      throw StateError('尚未连接 LiveTalking 服务。');
    }
    if (trimmed.isEmpty) {
      return;
    }
    await _dio.post<dynamic>(
      '$baseUrl/human',
      data: <String, Object?>{
        'sessionid': sessionId,
        'type': type,
        'text': trimmed,
        'interrupt': interrupt,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
  }

  Future<void> disconnect() async {
    _sessionId = null;
    _baseUrl = null;
    final RTCPeerConnection? pc = _pc;
    _pc = null;
    if (pc != null) {
      await pc.close();
      await pc.dispose();
    }
    final RTCVideoRenderer? renderer = _renderer;
    _renderer = null;
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
  }

  Future<void> _waitIceGatheringComplete(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final Completer<void> done = Completer<void>();
    void check(RTCIceGatheringState? state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    }

    pc.onIceGatheringState = check;
    check(pc.iceGatheringState);
    await done.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
  }

  String _normalizeBaseUrl(String raw) {
    String value = raw.trim();
    if (value.isEmpty) {
      throw StateError('请先在设置里填写 LiveTalking 服务地址。');
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String) {
      final Object? decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return <String, dynamic>{};
  }
}
