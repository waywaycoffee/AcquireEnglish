import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../import_course/data/netdisk_local_download.dart';
import '../../sync/data/acquire_api_client.dart';

class MediaLearningSyncSession {
  MediaLearningSyncSession(this._api);

  final AcquireApiClient _api;
  MediaIdentityResolution? _identity;
  DateTime? _lastSentAt;
  int _lastSentPositionMs = -1;
  Future<void>? _inFlight;
  _PendingMediaState? _pending;

  Future<MediaLearningState?> initializeForMedia({
    required String? videoSource,
    String? fallbackSource,
    String title = '',
    String seriesTitle = '',
    int? episode,
    int? durationMs,
  }) async {
    final String primary = (videoSource ?? '').trim();
    final String fallback = (fallbackSource ?? '').trim();
    final String source = primary.isNotEmpty ? primary : fallback;
    if (source.isEmpty) return null;
    final String netdiskSource = parseNetdiskImportIdFromUrl(primary) != null
        ? primary
        : fallback;
    final int? importId = parseNetdiskImportIdFromUrl(netdiskSource);
    try {
      if (importId != null) {
        _identity = await _api.resolveNetdiskMediaIdentity(importId);
      } else {
        final _MediaFingerprint fingerprint = await _fingerprint(source);
        _identity = await _api.resolveMediaIdentity(
          fileFingerprint: fingerprint.fileFingerprint,
          contentFingerprint: _semanticContentFingerprint(
            title: title,
            seriesTitle: seriesTitle,
            episode: episode,
            durationMs: durationMs,
          ),
          sourceType: fingerprint.sourceType,
          sourceLocatorHash: sha256.convert(utf8.encode(source)).toString(),
          fileSize: fingerprint.fileSize,
          durationMs: durationMs,
          title: title,
          seriesTitle: seriesTitle,
          episode: episode,
        );
      }
      return await _api.mediaLearningState(_identity!.mediaIdentityId);
    } catch (_) {
      return null;
    }
  }

  void save({
    required int positionMs,
    required int cueIndex,
    required int durationMs,
    bool force = false,
  }) {
    if (_identity == null) return;
    final DateTime now = DateTime.now();
    final bool dueByTime =
        _lastSentAt == null || now.difference(_lastSentAt!).inSeconds >= 5;
    final bool dueByDistance =
        (positionMs - _lastSentPositionMs).abs() >= 10000;
    if (!force && !dueByTime && !dueByDistance) return;
    _pending = _PendingMediaState(
      positionMs: positionMs,
      cueIndex: cueIndex,
      completed: durationMs > 0 && positionMs >= durationMs - 1500,
    );
    _drain();
  }

  Future<void> flush() async {
    _drain();
    await _inFlight;
    if (_pending != null) {
      _drain();
      await _inFlight;
    }
  }

  void _drain() {
    if (_inFlight != null || _pending == null || _identity == null) return;
    final _PendingMediaState value = _pending!;
    _pending = null;
    final MediaIdentityResolution identity = _identity!;
    _inFlight = _api
        .putMediaLearningState(
          mediaIdentityId: identity.mediaIdentityId,
          mediaVariantId: identity.mediaVariantId,
          lastPositionMs: value.positionMs,
          lastCueIndex: value.cueIndex,
          completed: value.completed,
        )
        .then<void>((_) {
          _lastSentAt = DateTime.now();
          _lastSentPositionMs = value.positionMs;
        })
        .catchError((Object _) {})
        .whenComplete(() {
          _inFlight = null;
          if (_pending != null) _drain();
        });
  }
}

Future<_MediaFingerprint> _fingerprint(String source) async {
  final File file = File(source);
  if (!file.existsSync()) {
    return _MediaFingerprint(
      fileFingerprint: sha256.convert(utf8.encode(source)).toString(),
      sourceType: source.contains('bilibili.com') || source.contains('/BV')
          ? 'bilibili'
          : 'ecs',
    );
  }
  final int size = await file.length();
  final RandomAccessFile handle = await file.open();
  try {
    const int blockSize = 4096;
    final List<int> offsets = <int>[
      0,
      (size * 0.33).floor(),
      (size * 0.66).floor(),
      (size - blockSize).clamp(0, size),
    ];
    final List<String> blocks = <String>[];
    for (final int offset in offsets) {
      await handle.setPosition(offset.clamp(0, size));
      blocks.add(md5.convert(await handle.read(blockSize)).toString());
    }
    return _MediaFingerprint(
      fileFingerprint: blocks.join(';'),
      sourceType: 'local',
      fileSize: size,
    );
  } finally {
    await handle.close();
  }
}

String _semanticContentFingerprint({
  required String title,
  required String seriesTitle,
  required int? episode,
  required int? durationMs,
}) {
  final String normalized = <Object?>[
    seriesTitle.trim().toLowerCase(),
    title.trim().toLowerCase(),
    episode,
    (durationMs ?? 0) ~/ 5000,
  ].join('|');
  return 'semantic:${sha256.convert(utf8.encode(normalized))}';
}

class _MediaFingerprint {
  const _MediaFingerprint({
    required this.fileFingerprint,
    required this.sourceType,
    this.fileSize,
  });

  final String fileFingerprint;
  final String sourceType;
  final int? fileSize;
}

class _PendingMediaState {
  const _PendingMediaState({
    required this.positionMs,
    required this.cueIndex,
    required this.completed,
  });

  final int positionMs;
  final int cueIndex;
  final bool completed;
}
