import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../settings/presentation/settings_provider.dart';

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
  bool _hasRemoteVideo = false;

  RTCVideoRenderer? get renderer => _renderer;
  String? get sessionId => _sessionId;
  String? get baseUrl => _baseUrl;

  /// SDP + session accepted by LiveTalking (media may still be negotiating).
  bool get isConnected => _sessionId != null && _pc != null;

  /// True after the first remote video track is attached to the renderer.
  bool get hasRemoteVideo => _hasRemoteVideo && isConnected;

  Future<RTCVideoRenderer> connect(
    String rawBaseUrl, {
    String? avatar,
    Duration mediaTimeout = const Duration(seconds: 12),
  }) async {
    await disconnect();
    final String baseUrl = _normalizeBaseUrl(rawBaseUrl);
    _baseUrl = baseUrl;
    _hasRemoteVideo = false;

    await _probeHttp(baseUrl);

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

    final Completer<void> firstVideo = Completer<void>();
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) {
        return;
      }
      renderer.srcObject = event.streams.first;
      if (event.track.kind == 'video') {
        _hasRemoteVideo = true;
        if (!firstVideo.isCompleted) {
          firstVideo.complete();
        }
      }
    };

    final RTCSessionDescription offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _waitIceGatheringComplete(pc);

    final RTCSessionDescription? local = await pc.getLocalDescription();
    if (local?.sdp == null || local!.sdp!.isEmpty) {
      throw StateError('LiveTalking 未能生成本地 SDP。');
    }

    final String avatarId = (avatar ?? defaultLiveTalkingAvatarId).trim();
    final Map<String, Object?> offerBody = <String, Object?>{
      'type': 'offer',
      'sdp': local.sdp,
    };
    if (avatarId.isNotEmpty) {
      offerBody['avatar'] = avatarId;
    }

    final Map<String, dynamic> body;
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '$baseUrl/offer',
        data: offerBody,
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      body = _asMap(response.data);
    } on DioException catch (error) {
      throw StateError(_dioFailureHint(baseUrl, error));
    }
    if (body['code'] == -1) {
      throw StateError(
        'LiveTalking /offer 拒绝: ${body['msg'] ?? 'unknown'}',
      );
    }
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

    // Prefer waiting for video so the UI is not a black pane; do not fail
    // the whole connect if ICE/media is slow (UDP may be restricted).
    try {
      await firstVideo.future.timeout(mediaTimeout);
    } on TimeoutException {
      // Session is still usable for /human; UI can show “等待画面”.
    }
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
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
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
      final Map<String, dynamic> body = _asMap(response.data);
      if (body.isNotEmpty && body['code'] == -1) {
        throw StateError(
          'LiveTalking /human 失败: ${body['msg'] ?? 'session rejected'}',
        );
      }
    } on DioException catch (error) {
      throw StateError(_dioFailureHint(baseUrl, error));
    }
  }

  Future<void> disconnect() async {
    _sessionId = null;
    _baseUrl = null;
    _hasRemoteVideo = false;
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

  Future<void> _probeHttp(String baseUrl) async {
    try {
      await _dio.get<dynamic>(
        '$baseUrl/',
        options: Options(
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          validateStatus: (int? code) => code != null && code < 500,
        ),
      );
    } on DioException catch (error) {
      throw StateError(_dioFailureHint(baseUrl, error));
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

  String _dioFailureHint(String baseUrl, DioException error) {
    final String detail = error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : error.type.name;
    return '无法连接数字人 $baseUrl（$detail）。'
        '请确认：① 手机已登录 Tailscale；② GPU 箱 LiveTalking 已启动（:8010）；'
        '③ 设置地址可用 $defaultLiveTalkingUrl 或 $defaultLiveTalkingUrlIp。';
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
