import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Short celebratory cues for rewards / milestones.
///
/// Tones are synthesized to a temp WAV (not shipped in the APK) so media stays
/// off the package while offline UX still works.
enum SuccessSfxKind {
  /// Soft confirm — tap, shadowing cue, small step.
  nudge,

  /// Points / coupon / small reward.
  reward,

  /// Word session / daily tasks cleared.
  complete,

  /// Streak / honor / welcome Pro.
  fanfare,
}

class SuccessSfx {
  SuccessSfx._();

  static final SuccessSfx instance = SuccessSfx._();

  Player? _player;
  bool _busy = false;
  DateTime? _lastAt;
  SuccessSfxKind? _lastKind;

  /// Mute for tests / accessibility.
  bool enabled = true;

  Future<void> play(SuccessSfxKind kind) async {
    if (!enabled) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastKind == kind &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(milliseconds: 450)) {
      return;
    }
    _lastAt = now;
    _lastKind = kind;

    try {
      switch (kind) {
        case SuccessSfxKind.nudge:
          await HapticFeedback.selectionClick();
        case SuccessSfxKind.reward:
          await HapticFeedback.lightImpact();
        case SuccessSfxKind.complete:
          await HapticFeedback.mediumImpact();
        case SuccessSfxKind.fanfare:
          await HapticFeedback.heavyImpact();
      }
    } catch (_) {}

    if (_busy) {
      return;
    }
    _busy = true;
    try {
      final File wav = await _ensureWav(kind);
      final Player player = _player ??= Player();
      await player.open(Media(wav.uri.toString()), play: true);
    } catch (_) {
      // Haptic already fired; ignore audio failures (web / missing libs).
    } finally {
      _busy = false;
    }
  }

  Future<File> _ensureWav(SuccessSfxKind kind) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File('${dir.path}/ae_sfx_${kind.name}.wav');
    if (await file.exists() && await file.length() > 44) {
      return file;
    }
    final Uint8List bytes = _synthesize(kind);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Uint8List _synthesize(SuccessSfxKind kind) {
    const int sampleRate = 22050;
    final List<({double hz, int ms, double gain})> notes;
    switch (kind) {
      case SuccessSfxKind.nudge:
        notes = <({double hz, int ms, double gain})>[
          (hz: 784, ms: 70, gain: 0.28),
          (hz: 988, ms: 90, gain: 0.32),
        ];
      case SuccessSfxKind.reward:
        notes = <({double hz, int ms, double gain})>[
          (hz: 523, ms: 80, gain: 0.30),
          (hz: 659, ms: 90, gain: 0.34),
          (hz: 784, ms: 120, gain: 0.36),
        ];
      case SuccessSfxKind.complete:
        notes = <({double hz, int ms, double gain})>[
          (hz: 392, ms: 90, gain: 0.30),
          (hz: 523, ms: 90, gain: 0.34),
          (hz: 659, ms: 110, gain: 0.36),
          (hz: 784, ms: 160, gain: 0.38),
        ];
      case SuccessSfxKind.fanfare:
        notes = <({double hz, int ms, double gain})>[
          (hz: 523, ms: 100, gain: 0.32),
          (hz: 659, ms: 100, gain: 0.34),
          (hz: 784, ms: 100, gain: 0.36),
          (hz: 1046, ms: 180, gain: 0.40),
          (hz: 784, ms: 140, gain: 0.30),
        ];
    }

    final BytesBuilder pcm = BytesBuilder(copy: false);
    for (final ({double hz, int ms, double gain}) note in notes) {
      final int n = (sampleRate * note.ms / 1000).round();
      for (int i = 0; i < n; i++) {
        final double t = i / sampleRate;
        final double env = _envelope(i, n);
        final double sample =
            math.sin(2 * math.pi * note.hz * t) * note.gain * env;
        final int v = (sample * 32767).round().clamp(-32768, 32767);
        pcm.addByte(v & 0xff);
        pcm.addByte((v >> 8) & 0xff);
      }
      // Tiny gap between notes.
      final int gap = (sampleRate * 0.012).round();
      for (int i = 0; i < gap; i++) {
        pcm.addByte(0);
        pcm.addByte(0);
      }
    }
    final Uint8List data = pcm.takeBytes();
    return _wrapWav(data, sampleRate: sampleRate);
  }

  static double _envelope(int i, int n) {
    if (n <= 1) {
      return 1;
    }
    final double attack = math.min(1.0, i / (n * 0.08));
    final double release = math.min(1.0, (n - 1 - i) / (n * 0.22));
    return attack * release;
  }

  static Uint8List _wrapWav(Uint8List pcm, {required int sampleRate}) {
    final int dataSize = pcm.length;
    final BytesBuilder out = BytesBuilder(copy: false);
    void writeString(String s) => out.add(s.codeUnits);
    void writeUint32(int v) {
      out.addByte(v & 0xff);
      out.addByte((v >> 8) & 0xff);
      out.addByte((v >> 16) & 0xff);
      out.addByte((v >> 24) & 0xff);
    }

    void writeUint16(int v) {
      out.addByte(v & 0xff);
      out.addByte((v >> 8) & 0xff);
    }

    writeString('RIFF');
    writeUint32(36 + dataSize);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16);
    writeUint16(1); // PCM
    writeUint16(1); // mono
    writeUint32(sampleRate);
    writeUint32(sampleRate * 2);
    writeUint16(2);
    writeUint16(16);
    writeString('data');
    writeUint32(dataSize);
    out.add(pcm);
    return out.takeBytes();
  }

  Future<void> dispose() async {
    final Player? player = _player;
    _player = null;
    await player?.dispose();
  }
}

void playSuccessSfx(SuccessSfxKind kind) {
  unawaited(SuccessSfx.instance.play(kind));
}
