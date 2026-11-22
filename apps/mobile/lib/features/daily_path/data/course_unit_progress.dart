import 'package:shared_preferences/shared_preferences.dart';

/// Local checkpoint for an individual course unit. A seek never counts as
/// watching: the player only advances watchedMs while playback is running.
class CourseUnitProgress {
  const CourseUnitProgress({
    this.positionMs = 0,
    this.watchedMs = 0,
    this.shadowScore,
    this.quizCorrect,
    this.quizTotal,
    this.oralTurns = 0,
  });

  final int positionMs;
  final int watchedMs;
  final int? shadowScore;
  final int? quizCorrect;
  final int? quizTotal;
  final int oralTurns;

  static String _key(String courseId, String unitId, String field) =>
      'course_unit:$courseId:$unitId:$field';

  static Future<CourseUnitProgress> load(String courseId, String unitId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return CourseUnitProgress(
      positionMs: prefs.getInt(_key(courseId, unitId, 'position')) ?? 0,
      watchedMs: prefs.getInt(_key(courseId, unitId, 'watched')) ?? 0,
      shadowScore: prefs.getInt(_key(courseId, unitId, 'shadow')),
      quizCorrect: prefs.getInt(_key(courseId, unitId, 'quizCorrect')),
      quizTotal: prefs.getInt(_key(courseId, unitId, 'quizTotal')),
      oralTurns: prefs.getInt(_key(courseId, unitId, 'oralTurns')) ?? 0,
    );
  }

  static Future<void> save(
    String courseId,
    String unitId,
    CourseUnitProgress progress,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(courseId, unitId, 'position'), progress.positionMs);
    await prefs.setInt(_key(courseId, unitId, 'watched'), progress.watchedMs);
  }

  static Future<void> saveShadow(
    String courseId,
    String unitId,
    int score,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(courseId, unitId, 'shadow'), score);
  }

  static Future<void> saveQuiz(
    String courseId,
    String unitId,
    int correct,
    int total,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(courseId, unitId, 'quizCorrect'), correct);
    await prefs.setInt(_key(courseId, unitId, 'quizTotal'), total);
  }

  static Future<void> saveOralTurns(String courseId, String unitId, int turns) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(courseId, unitId, 'oralTurns'), turns);
  }
}
