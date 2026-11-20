import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../authentication/presentation/auth_session.dart';
import 'acquire_api_client.dart';

final studyActivityServiceProvider = Provider<StudyActivityService>((Ref ref) {
  final StudyActivityService service = StudyActivityService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Only called by actual player-duration/grade events, never by a page timer.
class StudyActivityService {
  StudyActivityService(this.ref);
  final Ref ref;
  bool _disposed = false;
  bool _sending = false;
  Completer<void>? _inFlight;
  String _token = '';
  int _pendingMs = 0;
  DateTime? _lastSent;
  void dispose() => _disposed = true;

  void playback(Duration duration) {
    if (_disposed ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed))
      return;
    if (duration <= Duration.zero || duration > const Duration(minutes: 1))
      return;
    final String token = ref.read(authSessionProvider).accessToken;
    if (token.isEmpty) return;
    if (_token != token) {
      _token = token;
      _pendingMs = 0;
      _lastSent = null;
    }
    _pendingMs += duration.inMilliseconds;
    if (_lastSent == null) unawaited(_send(0));
    if (_pendingMs >= 20000) unawaited(_send(20));
  }

  Future<void> touchReview() => _send(0);

  Future<void> _send(int seconds) async {
    if (_disposed || !ref.mounted) return;
    if (_sending) {
      await _inFlight?.future;
      return;
    }
    final String token = ref.read(authSessionProvider).accessToken;
    if (token.isEmpty) return;
    if (seconds == 0 &&
        _lastSent != null &&
        DateTime.now().difference(_lastSent!) < const Duration(seconds: 5) &&
        token == _token)
      return;
    if (_token != token) {
      _token = token;
      _pendingMs = 0;
    }
    _sending = true;
    _inFlight = Completer<void>();
    try {
      await ref
          .read(acquireApiClientProvider)
          .studyPlayRequest(
            'POST',
            '/activity',
            data: <String, dynamic>{'seconds': seconds},
          );
      if (!_disposed &&
          ref.mounted &&
          token == ref.read(authSessionProvider).accessToken) {
        _pendingMs = (_pendingMs - seconds * 1000).clamp(0, 60000);
        _lastSent = DateTime.now();
      }
    } catch (_) {
      // Failure does not invent credited time; local progress remains intact.
    } finally {
      _sending = false;
      _inFlight?.complete();
      _inFlight = null;
    }
  }
}
