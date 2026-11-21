import 'package:flutter/material.dart';

import 'study_oral_coach_tab.dart';

/// Standalone digital-human module entry (scenario dialogue without a video).
class DigitalHumanCoachScreen extends StatelessWidget {
  const DigitalHumanCoachScreen({
    super.key,
    this.initialScenarioId,
    this.lessonTitle,
    this.lessonText,
    this.practiceRole,
  });

  final String? initialScenarioId;
  final String? lessonTitle, lessonText, practiceRole;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14102A),
      appBar: AppBar(
        title: Text(lessonTitle ?? '数字人口语'),
        backgroundColor: const Color(0xFF14102A),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        child: StudyOralCoachTab(
          topicSummary: lessonTitle == null
              ? '英语口语闲聊'
              : 'Practise the scenario: $lessonTitle. The learner plays role $practiceRole. You play the other role. Use the example dialogue as context and provide helpful feedback.',
          articleExcerpt: lessonText ?? '',
          courseTitle: '数字人口语',
          hasTranscript: lessonText?.isNotEmpty == true,
          standalone: true,
          initialScenarioId: lessonText?.isNotEmpty == true
              ? 'video_line'
              : initialScenarioId ?? 'freechat',
        ),
      ),
    );
  }
}
