import 'package:hive_ce/hive.dart';

/// One-time discoverability tip for the swipeable bottom bar.
const String kBottomNavScrollHintKey = 'bottom_nav_scroll_hint_seen_v1';

bool readBottomNavScrollHintSeen() {
  // Without a prefs box we cannot persist dismiss — skip the tip rather than
  // resurfacing it on every rebuild (widget tests, early boot).
  if (!Hive.isBoxOpen('prefs')) return true;
  return Hive.box<String>('prefs').get(kBottomNavScrollHintKey) == '1';
}

Future<void> markBottomNavScrollHintSeen() async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(kBottomNavScrollHintKey, '1');
}
