import 'package:hive_ce/hive.dart';

/// Bumped when the 8-page cinematic guide became the cold-start 启动页.
const String kAuthSourceGuideCompleteKey = 'auth_source_guide_complete_v4';

bool readAuthSourceGuideCompletedSync() {
  if (!Hive.isBoxOpen('prefs')) return false;
  return Hive.box<String>('prefs').get(kAuthSourceGuideCompleteKey) == '1';
}

Future<void> markAuthSourceGuideCompleted() async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(kAuthSourceGuideCompleteKey, '1');
}
