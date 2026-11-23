import 'package:hive_ce/hive.dart';

/// Legacy prefs key (older installs may still have it).
const String kAuthSourceGuideCompleteKey = 'auth_source_guide_complete_v4';

/// Process-lifetime flag: cold-start splash shows once per app launch.
bool _sessionSplashDone = false;

bool readSessionSplashDone() => _sessionSplashDone;

void markSessionSplashDone() {
  _sessionSplashDone = true;
}

bool readAuthSourceGuideCompletedSync() {
  // Splash is per-process now; prefs only matter for very old redirect paths.
  if (_sessionSplashDone) return true;
  if (!Hive.isBoxOpen('prefs')) return false;
  return Hive.box<String>('prefs').get(kAuthSourceGuideCompleteKey) == '1';
}

Future<void> markAuthSourceGuideCompleted() async {
  markSessionSplashDone();
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(kAuthSourceGuideCompleteKey, '1');
}
