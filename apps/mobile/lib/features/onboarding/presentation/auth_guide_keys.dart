import 'package:hive_ce/hive.dart';

const String kAuthSourceGuideCompleteKey = 'auth_source_guide_complete_v3';

bool readAuthSourceGuideCompletedSync() {
  if (!Hive.isBoxOpen('prefs')) return false;
  return Hive.box<String>('prefs').get(kAuthSourceGuideCompleteKey) == '1';
}

Future<void> markAuthSourceGuideCompleted() async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(kAuthSourceGuideCompleteKey, '1');
}
