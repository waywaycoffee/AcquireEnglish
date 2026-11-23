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

  Future<void> saveStage(JourneyStage stage) async {
    await _prefs?.put(_key, jsonEncode({..._read(), 'stage': stage.name}));
  }

  Future<void> saveActivity(JourneyActivity activity) async {
    await _prefs?.put(
      _key,
      jsonEncode({
        ..._read(),
        'route': activity.route,
        'title': activity.title,
      }),
    );
  }
}
