import 'package:common_learn_english/features/learning_modules/american_ipa_course.dart';
import 'package:common_learn_english/features/learning_modules/british_ipa_course.dart';
import 'package:common_learn_english/features/learning_modules/official_skill_course_media.dart';
import 'package:common_learn_english/features/learning_modules/phonics_nessy_course.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official skill series ids are recognized', () {
    expect(OfficialSkillCourseMedia.isOfficialSkillSeries('british_ipa_bbc'), isTrue);
    expect(
      OfficialSkillCourseMedia.isOfficialSkillSeries('british_ipa_bbc-02'),
      isTrue,
    );
    expect(OfficialSkillCourseMedia.isOfficialSkillSeries('bilibili-BV1xx'), isFalse);
  });

  test('skill course episodes point at ECS media + bilibili fallback', () {
    final british = BritishIpaCourse.toLibraryCourse().episodes.first;
    expect(british.videoAsset, startsWith('/media/course/british_ipa_bbc/'));
    expect(british.sourceUrl, contains('bilibili.com'));
    expect(british.enSubtitleAsset, contains('/media/course/british_ipa_bbc/'));
    expect(british.cnSubtitleAsset, contains('/media/course/british_ipa_bbc/'));

    final american = AmericanIpaCourse.toLibraryCourse().episodes.first;
    expect(american.videoAsset, startsWith('/media/course/american_ipa_20/'));
    expect(american.enSubtitleAsset, contains('/media/course/american_ipa_20/'));

    final phonics = PhonicsNessyCourse.toLibraryCourse().episodes.first;
    expect(phonics.videoAsset, startsWith('/media/course/phonics_nessy/'));
    expect(phonics.cnSubtitleAsset, contains('/media/course/phonics_nessy/'));
  });
}
