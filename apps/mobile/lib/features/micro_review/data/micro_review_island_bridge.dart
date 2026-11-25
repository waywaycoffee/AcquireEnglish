import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/micro_review_session.dart';

/// Platform surface for the 5-minute micro-review island / Live Activity.
abstract class MicroReviewIslandBridge {
  Future<bool> start(MicroReviewIslandPayload payload);
  Future<void> update(MicroReviewIslandPayload payload);
  Future<void> end();
  Stream<MicroReviewIslandAction> get actions;
  void dispose();
}

class MicroReviewIslandPayload {
  const MicroReviewIslandPayload({
    required this.word,
    required this.gloss,
    required this.remainingSec,
    required this.ratedCount,
    required this.total,
    required this.endsAtMs,
  });

  final String word;
  final String gloss;
  final int remainingSec;
  final int ratedCount;
  final int total;
  final int endsAtMs;

  Map<String, Object?> toMap() => <String, Object?>{
    'word': word,
    'gloss': gloss,
    'remainingSec': remainingSec,
    'ratedCount': ratedCount,
    'total': total,
    'endsAtMs': endsAtMs,
  };

  factory MicroReviewIslandPayload.fromSession(MicroReviewSession session) {
    final MicroReviewCard? card = session.current;
    final DateTime endsAt = session.startedAt.add(session.duration);
    return MicroReviewIslandPayload(
      word: card?.word ?? '—',
      gloss: card?.gloss ?? '',
      remainingSec: session.remainingAt(DateTime.now()).inSeconds,
      ratedCount: session.ratedCount,
      total: session.cards.length,
      endsAtMs: endsAt.millisecondsSinceEpoch,
    );
  }
}

enum MicroReviewIslandActionKind { know, fuzzy, forget, open, end }

class MicroReviewIslandAction {
  const MicroReviewIslandAction(this.kind);
  final MicroReviewIslandActionKind kind;

  static MicroReviewIslandAction? parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'know':
      case 'good':
        return const MicroReviewIslandAction(MicroReviewIslandActionKind.know);
      case 'fuzzy':
      case 'hard':
        return const MicroReviewIslandAction(MicroReviewIslandActionKind.fuzzy);
      case 'forget':
      case 'again':
        return const MicroReviewIslandAction(MicroReviewIslandActionKind.forget);
      case 'open':
        return const MicroReviewIslandAction(MicroReviewIslandActionKind.open);
      case 'end':
      case 'stop':
        return const MicroReviewIslandAction(MicroReviewIslandActionKind.end);
      default:
        return null;
    }
  }
}

MicroReviewIslandBridge createMicroReviewIslandBridge() {
  if (kIsWeb) return _NoopIslandBridge();
  if (Platform.isAndroid) return AndroidMicroReviewIslandBridge();
  if (Platform.isIOS) return IosMicroReviewIslandBridge();
  return _NoopIslandBridge();
}

class _NoopIslandBridge implements MicroReviewIslandBridge {
  final StreamController<MicroReviewIslandAction> _actions =
      StreamController<MicroReviewIslandAction>.broadcast();

  @override
  Stream<MicroReviewIslandAction> get actions => _actions.stream;

  @override
  Future<bool> start(MicroReviewIslandPayload payload) async => false;

  @override
  Future<void> update(MicroReviewIslandPayload payload) async {}

  @override
  Future<void> end() async {}

  @override
  void dispose() {
    _actions.close();
  }
}

/// Xiaomi 超级岛 via `miui.focus.param`, else ongoing notification.
class AndroidMicroReviewIslandBridge implements MicroReviewIslandBridge {
  AndroidMicroReviewIslandBridge() {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.acquire.english/micro_review_island',
  );

  final StreamController<MicroReviewIslandAction> _actions =
      StreamController<MicroReviewIslandAction>.broadcast();

  @override
  Stream<MicroReviewIslandAction> get actions => _actions.stream;

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'action') {
      final Object? args = call.arguments;
      final String? raw = args is String
          ? args
          : (args is Map ? args['action']?.toString() : null);
      final MicroReviewIslandAction? action = MicroReviewIslandAction.parse(raw);
      if (action != null) _actions.add(action);
    }
    return null;
  }

  @override
  Future<bool> start(MicroReviewIslandPayload payload) async {
    try {
      final Object? ok = await _channel.invokeMethod<Object?>(
        'start',
        payload.toMap(),
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> update(MicroReviewIslandPayload payload) async {
    try {
      await _channel.invokeMethod<void>('update', payload.toMap());
    } catch (_) {}
  }

  @override
  Future<void> end() async {
    try {
      await _channel.invokeMethod<void>('end');
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _actions.close();
  }
}

/// iOS Dynamic Island bridge.
///
/// Requires the `MicroReviewWidget` Widget Extension to be embedded in Xcode
/// (see docs/MICRO_REVIEW_ISLAND.md). Until then, start() returns false and the
/// in-app micro-review card still works.
class IosMicroReviewIslandBridge implements MicroReviewIslandBridge {
  IosMicroReviewIslandBridge() {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.acquire.english/micro_review_live_activity',
  );

  final StreamController<MicroReviewIslandAction> _actions =
      StreamController<MicroReviewIslandAction>.broadcast();

  @override
  Stream<MicroReviewIslandAction> get actions => _actions.stream;

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'action') {
      final Object? args = call.arguments;
      final String? raw = args is String
          ? args
          : (args is Map ? args['action']?.toString() : null);
      final MicroReviewIslandAction? action = MicroReviewIslandAction.parse(raw);
      if (action != null) _actions.add(action);
    }
    return null;
  }

  @override
  Future<bool> start(MicroReviewIslandPayload payload) async {
    try {
      final Object? ok = await _channel.invokeMethod<Object?>(
        'start',
        payload.toMap(),
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> update(MicroReviewIslandPayload payload) async {
    try {
      await _channel.invokeMethod<void>('update', payload.toMap());
    } catch (_) {}
  }

  @override
  Future<void> end() async {
    try {
      await _channel.invokeMethod<void>('end');
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _actions.close();
  }
}
