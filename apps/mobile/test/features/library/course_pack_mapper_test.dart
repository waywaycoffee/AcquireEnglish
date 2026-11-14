import 'package:common_learn_english/features/library/data/course_pack_mapper.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder cloud courses are detected', () {
    const AcquireCourseDto demo = AcquireCourseDto(
      id: 'slow-english-demo',
      title: 'Slow English Demo',
      titleZh: '慢速英语演示',
      level: 'A2',
      tags: <String>['demo'],
      lessons: <AcquireLessonDto>[
        AcquireLessonDto(
          id: 'slow-english-demo-01',
          title: 'Walking on the Path',
          index: 1,
          durationSec: 96,
          videoUrl: 'https://cdn.example.com/courses/slow-english-demo/01.mp4',
          subtitleEn: 'https://cdn.example.com/courses/slow-english-demo/01.en.srt',
        ),
      ],
    );
    expect(isPlaceholderCloudCourse(demo), isTrue);
    final LibraryCourseData mapped = mapAcquireCourseToLibrary(demo);
    expect(isPlaceholderLibraryCourse(mapped), isTrue);
    expect(mapped.episodes.single.videoMissing, isTrue);
  });

  test('real video URLs are not placeholders', () {
    const AcquireCourseDto real = AcquireCourseDto(
      id: 'link-1',
      title: 'Real',
      level: 'B1',
      tags: <String>['import'],
      lessons: <AcquireLessonDto>[
        AcquireLessonDto(
          id: 'l1',
          title: 'One',
          index: 1,
          durationSec: 60,
          videoUrl: 'https://acquireenglish.curlhairai.com/media/x.mp4',
          subtitleEn: '',
        ),
      ],
    );
    expect(isPlaceholderCloudCourse(real), isFalse);
  });
}
