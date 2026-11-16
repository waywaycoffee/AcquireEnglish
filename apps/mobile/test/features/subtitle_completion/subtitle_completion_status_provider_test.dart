import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_queue.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_status_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forCourse shows active banner and progress', () {
    const SubtitleCompletionStatusState state = SubtitleCompletionStatusState(
      byEpisodeId: <String, SubtitleCompletionEpisodeUi>{
        'ep1': SubtitleCompletionEpisodeUi(
          episodeId: 'ep1',
          status: SubtitleCompletionStatus.running,
          needEnglish: true,
          needChinese: true,
          label: '正在用语音生成英文字幕…',
        ),
        'ep2': SubtitleCompletionEpisodeUi(
          episodeId: 'ep2',
          status: SubtitleCompletionStatus.pending,
          needEnglish: true,
          needChinese: false,
        ),
      },
    );

    final SubtitleCompletionCourseUi? ui = state.forCourse(
      courseId: 'c1',
      episodeIds: <String>['ep1', 'ep2', 'ep3'],
    );
    expect(ui, isNotNull);
    expect(ui!.showBanner, isTrue);
    expect(ui.activeCount, 2);
    expect(ui.message, contains('补字幕中'));
    expect(ui.progress, greaterThan(0));
  });

  test('forCourse shows failed banner', () {
    const SubtitleCompletionStatusState state = SubtitleCompletionStatusState(
      byEpisodeId: <String, SubtitleCompletionEpisodeUi>{
        'ep1': SubtitleCompletionEpisodeUi(
          episodeId: 'ep1',
          status: SubtitleCompletionStatus.failed,
          needEnglish: true,
          needChinese: false,
          lastError: 'whisper failed',
        ),
      },
    );
    final SubtitleCompletionCourseUi? ui = state.forCourse(
      courseId: 'c1',
      episodeIds: <String>['ep1'],
    );
    expect(ui!.failedCount, 1);
    expect(ui.message, contains('失败'));
  });
}
