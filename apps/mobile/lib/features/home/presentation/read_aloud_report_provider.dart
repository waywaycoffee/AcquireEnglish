import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';

String readAloudDay(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String newReadAloudAttemptId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';

class ReadAloudAttempt {
  const ReadAloudAttempt({
    required this.id,
    required this.day,
    required this.durationMs,
    required this.weakWords,
    this.pending = false,
  });

  final String id;
  final String day;
  final int durationMs;
  final Set<String> weakWords;
  final bool pending;

  factory ReadAloudAttempt.fromJson(Map<dynamic, dynamic> json) =>
      ReadAloudAttempt(
        id: json['id'] as String,
        day: json['day'] as String,
        durationMs: json['durationMs'] as int,
        weakWords: Set<String>.of(
          (json['weakWords'] as List? ?? []).whereType<String>(),
        ),
        pending: json['pending'] == true,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'day': day,
    'durationMs': durationMs,
    'weakWords': weakWords.toList(),
  };
}

final readAloudReportProvider =
    NotifierProvider<ReadAloudReport, Map<String, ReadAloudAttempt>>(
      ReadAloudReport.new,
    );

class ReadAloudReport extends Notifier<Map<String, ReadAloudAttempt>> {
  String _account = '';
  int _generation = 0;
  bool _syncing = false;
  bool _syncAgain = false;

  @override
  Map<String, ReadAloudAttempt> build() {
    _account = ref.watch(studyAccountProvider);
    _generation++;
    _syncing = false;
    _syncAgain = false;
    ref.onDispose(() => _generation++);
    final raw = readStudyStorage('read-aloud:v1', _account);
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as List;
      return {
        for (final row in data.whereType<Map>())
          row['id'] as String: ReadAloudAttempt.fromJson(row),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      studyStorageKey('read-aloud:v1', _account),
      jsonEncode([
        for (final attempt in state.values)
          {...attempt.toJson(), if (attempt.pending) 'pending': true},
      ]),
    );
  }

  Future<void> record({
    required String id,
    required DateTime at,
    required int durationMs,
    Set<String> weakWords = const {},
  }) async {
    if (durationMs <= 0) return;
    final int generation = _generation;
    final previous = state[id];
    final words = {...?previous?.weakWords, ...weakWords}.take(24).toSet();
    if (previous != null && words.length == previous.weakWords.length) return;
    state = {
      ...state,
      id: ReadAloudAttempt(
        id: id,
        day: previous?.day ?? readAloudDay(at),
        durationMs: previous?.durationMs ?? durationMs.clamp(1, 120000),
        weakWords: words,
        pending: _account.isNotEmpty,
      ),
    };
    await _save();
    if (generation == _generation) unawaited(sync());
  }

  Future<void> sync() async {
    final token = ref.read(authSessionProvider).accessToken;
    if (_account.isEmpty || token.isEmpty) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    final int generation = _generation;
    final api = ref.read(acquireApiClientProvider);
    try {
      final pending = state.values.where((e) => e.pending).toList();
      for (var i = 0; i < pending.length; i += 100) {
        final batch = pending.skip(i).take(100).toList();
        await api.putReadAloudAttempts(
          token,
          batch.map((e) => e.toJson()).toList(),
        );
        if (generation != _generation) return;
        state = {
          ...state,
          for (final sent in batch)
            if (identical(state[sent.id], sent))
              sent.id: ReadAloudAttempt.fromJson(sent.toJson()),
        };
        await _save();
        if (generation != _generation) return;
      }
      final now = DateTime.now();
      final since = readAloudDay(DateTime(now.year, now.month, now.day - 29));
      final rows = await api.getReadAloudAttempts(token, since);
      if (generation != _generation) return;
      final local = state;
      state = {
        for (final attempt in local.values)
          if (attempt.pending || attempt.day.compareTo(since) >= 0)
            attempt.id: attempt,
        for (final row in rows)
          if (local[row['id']]?.pending != true)
            row['id'] as String: ReadAloudAttempt.fromJson(row),
      };
      await _save();
    } catch (_) {
      // Keep unsent attempts on disk for the next sync.
    } finally {
      if (generation == _generation) {
        _syncing = false;
        if (_syncAgain) {
          _syncAgain = false;
          unawaited(sync());
        }
      }
    }
  }
}
