import 'dart:convert';

import 'package:hive_ce/hive.dart';

enum JourneyStage { review, learn, tomorrow, done }

typedef JourneyActivity = ({String route, String title});

class TodayJourneyStore {
  TodayJourneyStore(String account, DateTime date)
    : _key =
          'dailyJourney:${Uri.encodeComponent(account)}:'
          '${date.year}-${date.month}-${date.day}';

  final String _key;

  Box<String>? get _prefs =>
      Hive.isBoxOpen('prefs') ? Hive.box<String>('prefs') : null;

  Map<String, Object?> _read() {
    final String? raw = _prefs?.get(_key);
    if (raw != null) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // Recover from an unreadable local journey.
      }
    }
    return <String, Object?>{};
  }

  JourneyStage get stage {
    final Object? name = _read()['stage'];
    return JourneyStage.values.firstWhere(
      (JourneyStage stage) => stage.name == name,
      orElse: () => JourneyStage.review,
    );
  }

  JourneyActivity? get activity {
    final Map<String, Object?> record = _read();
    final Object? route = record['route'];
    final Object? title = record['title'];
    if (route is! String || title is! String) return null;
    return (route: route, title: title);
  }

  /// True only when the learner tapped「稍后继续」— not when Journey merely
  /// opened a cold recommendation. Stale auto-saves must not block「接着看下一集」.
  bool get pausedExplicitly {
    final Object? flag = _read()['pausedExplicitly'];
    return flag == true;
  }

  /// Next-day plan written at Gate3 (or「换明天」). Distinct from [pausedExplicitly].
  bool get planned {
    final Object? flag = _read()['planned'];
    return flag == true;
  }

  /// Why this planned activity was chosen (shown on Gate3 / next-day banner).
  String? get reason {
    final Object? value = _read()['reason'];
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveStage(JourneyStage stage) async {
    await _prefs?.put(_key, jsonEncode({..._read(), 'stage': stage.name}));
  }

  Future<void> saveActivity(
    JourneyActivity activity, {
    bool pausedExplicitly = false,
    bool planned = false,
    String? reason,
  }) async {
    final Map<String, Object?> next = <String, Object?>{
      ..._read(),
      'route': activity.route,
      'title': activity.title,
      'pausedExplicitly': pausedExplicitly,
      'planned': planned && !pausedExplicitly,
    };
    if (reason != null) {
      final String trimmed = reason.trim();
      if (trimmed.isEmpty) {
        next.remove('reason');
      } else {
        next['reason'] = trimmed;
      }
    } else if (!planned || pausedExplicitly) {
      // Fresh non-plan saves drop a stale Gate3 reason.
      next.remove('reason');
    }
    await _prefs?.put(_key, jsonEncode(next));
  }

  Future<void> clearPausedFlag() async {
    final Map<String, Object?> next = {..._read()}..remove('pausedExplicitly');
    await _prefs?.put(_key, jsonEncode(next));
  }
}
