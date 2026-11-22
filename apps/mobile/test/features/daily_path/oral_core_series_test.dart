import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/daily_path/domain/course_plan.dart';
import 'package:common_learn_english/features/daily_path/domain/oral_core_series.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled manifest has 151 lessons and sample packs', () {
    final File file = File('assets/courses/manifest.json');
    expect(file.existsSync(), isTrue);
    final OralCoreSeries series = OralCoreSeries.fromJson(
      Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map),
    );
    expect(series.seriesId, OralCoreSeries.kSeriesId);
    expect(series.lessons.length, 151);
    expect(series.lessons.first.title, '起床');
    expect(series.lessons.first.pack.quiz, isNotEmpty);
    expect(series.lessons[5].pack.quiz, isEmpty);

    final CoursePlan plan = series.toCoursePlan(dailyLessons: 3);
    expect(plan.type, CoursePlanType.videoSeries);
    expect(plan.params.dailyLessons, 3);
    expect(plan.units.length, 151);
    expect(plan.units.first.episodePage, 1);
    expect(plan.units.first.quiz, isNotEmpty);
  });
}
