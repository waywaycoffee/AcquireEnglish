import 'package:hive_ce/hive.dart';

/// One-time home feature coach-mark tour.
const String kHomeFeatureTourKey = 'home_feature_tour_v1';

/// First-open tip inside the study player (sentence focus).
const String kPlayerListenTipKey = 'player_listen_tip_v1';

bool readHomeFeatureTourSeen() {
  if (!Hive.isBoxOpen('prefs')) return true;
  return Hive.box<String>('prefs').get(kHomeFeatureTourKey) == '1';
}

Future<void> markHomeFeatureTourSeen() async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(kHomeFeatureTourKey, '1');
}

Future<void> resetHomeFeatureTourSeen() async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').delete(kHomeFeatureTourKey);
}

bool readPlayerListenTipSeen() {
  if (!Hive.isBoxOpen('prefs')) return true;
  return Hive.box<String>('prefs').get(kPlayerListenTipKey) == '1';
}

Future<void> markPlayerListenTipSeen() async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(kPlayerListenTipKey, '1');
}
