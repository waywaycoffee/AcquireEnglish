import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../settings/presentation/settings_provider.dart';

/// Minimal LiveTalking WebRTC client (open-source realtime digital human).
///
/// Server: `python app.py --transport webrtc ...` then open `/offer` + `/human`.
class LiveTalkingClient {
  LiveTalkingClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );

  final Dio _dio;

  /// Fast HTTP reachability check.
  ///
  /// Probes `/index.html` (not `/`) so nginx never returns a 302 that older
  /// proxies absolutized as `https://host:8443/...` (phones cannot open :8443).
  static Future<bool> isReachable(
    String rawBaseUrl, {
    Duration timeout = const Duration(seconds: 3),
    Dio? dio,
  }) async {
    final Dio client =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: timeout,
            sendTimeout: timeout,
            receiveTimeout: timeout,
            followRedirects: false,
            maxRedirects: 0,
          ),
        );
    try {
      String value = rawBaseUrl.trim();
      if (value.isEmpty) {
        return false;
      }
      if (!value.startsWith('http://') && !value.startsWith('https://')) {
        value = 'http://$value';
      }
      while (value.endsWith('/')) {
        value = value.substring(0, value.length - 1);
      }
      // Reject Tailscale-only endpoints on phones.
      if (value.contains('100.115.') || value.contains('ts.net')) {
        return false;
      }
      final Response<dynamic> response = await client.get<dynamic>(
        '$value/index.html',
        options: Options(
          validateStatus: (int? code) =>
              code != null && code >= 200 && code < 400,
          followRedirects: false,
        ),
      );
      final String? location = response.headers.value('location');
      if (location != null && location.contains(':8443')) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Prefer the first reachable candidate (LAN → preferred → MagicDNS → TS IP).
  static Future<String> pickReachableBaseUrl({
    String? preferred,
    List<String> candidates = liveTalkingUrlCandidates,
    Dio? dio,
  }) async {
    final List<String> ordered = <String>[];
    void add(String raw) {
      final String normalized = raw.trim().replaceAll(RegExp(r'/+$'), '');
      if (normalized.isNotEmpty && !ordered.contains(normalized)) {
        ordered.add(normalized);
      }
    }

    // Public HTTPS first — phones must not depend on Tailscale.
    add(defaultLiveTalkingUrlPublic);
    final String pref = (preferred ?? '').trim();
    if (pref.isNotEmpty &&
        !pref.contains('100.115.252.55') &&
        !pref.contains('ts.net')) {
      add(pref);
    }
    for (final String url in candidates) {
      add(url);
    }
    for (final String url in ordered) {
      if (await isReachable(url, dio: dio)) {
        return url;
      }
    }
    // Fall back to public HTTPS so the caller still gets a concrete error.
    return defaultLiveTalkingUrlPublic;
  }
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
    List<Map<String, dynamic>>? iceServers,
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

    // Prefer ICE from oral-coach /api/health (CurlHair-style: phone only uses
    // public config). Fallback: built-in STUN + TURNS.
    final List<Map<String, dynamic>> ice =
        (iceServers != null && iceServers.isNotEmpty)
        ? iceServers
        : defaultLiveTalkingIceServers;
    final RTCPeerConnection pc = await createPeerConnection(<String, dynamic>{
      'sdpSemantics': 'unified-plan',
      'iceServers': ice,
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
      final String msg = '${body['msg'] ?? 'unknown'}';
      if (msg.toLowerCase().contains('maximum session') ||
          msg.toLowerCase().contains('max session') ||
          msg.contains('会话')) {
        throw StateError(
          '外教线路忙线（会话已满）。正在自动重试，也可在 GPU 上运行 '
          'tools/livetalking/restart_livetalking.ps1 清理占用。',
        );
      }
      throw StateError('LiveTalking /offer 拒绝: $msg');
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

  /// Flush the talk queue without tearing down the WebRTC session.
  Future<void> interruptTalk() async {
    final String? baseUrl = _baseUrl;
    final String? sessionId = _sessionId;
    if (baseUrl == null || sessionId == null) {
      return;
    }
    try {
      await _dio.post<dynamic>(
        '$baseUrl/interrupt_talk',
        data: <String, Object?>{'sessionid': sessionId},
        options: Options(
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
    } catch (_) {}
  }

  /// True when the peer is still open and the session id is set.
  bool get isSessionAlive {
    final RTCPeerConnection? pc = _pc;
    if (_sessionId == null || pc == null) {
      return false;
    }
    final RTCPeerConnectionState? state = pc.connectionState;
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
      return false;
    }
    return true;
  }

  /// Best-effort hangup: interrupt speech, close PC so the GPU frees the slot.
  Future<void> disconnect() async {
    final String? baseUrl = _baseUrl;
    final String? sessionId = _sessionId;
    try {
      await interruptTalk();
    } catch (_) {}
    _sessionId = null;
    _baseUrl = null;
    _hasRemoteVideo = false;
    final RTCPeerConnection? pc = _pc;
    _pc = null;
    if (pc != null) {
      try {
        // Nudge ICE to closed so LiveTalking's session_manager can release.
        pc.onConnectionState = null;
        await pc.close();
      } catch (_) {}
      try {
        await pc.dispose();
      } catch (_) {}
    }
    final RTCVideoRenderer? renderer = _renderer;
    _renderer = null;
    if (renderer != null) {
      try {
        renderer.srcObject = null;
        await renderer.dispose();
      } catch (_) {}
    }
    // Drop references so GC / server timeouts can reclaim zombies faster.
    if (baseUrl != null && sessionId != null) {
      try {
        await _dio.post<dynamic>(
          '$baseUrl/interrupt_talk',
          data: <String, Object?>{'sessionid': sessionId},
          options: Options(
            contentType: Headers.jsonContentType,
            sendTimeout: const Duration(seconds: 2),
            receiveTimeout: const Duration(seconds: 2),
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _probeHttp(String baseUrl) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$baseUrl/index.html',
        options: Options(
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (int? code) =>
              code != null && code >= 200 && code < 400,
        ),
      );
      final String? location = response.headers.value('location');
      if (location != null && location.contains(':8443')) {
        throw StateError(
          '数字人地址被错误重定向到 :8443（$location）。'
          '请使用公网 $defaultLiveTalkingUrlPublic。',
        );
      }
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
        '请使用公网地址 $defaultLiveTalkingUrlPublic '
        '（ECS 反代 → GPU LiveTalking；手机无需 Tailscale）。'
        '并确认 GPU 箱 LiveTalking :8010 在线。';
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
