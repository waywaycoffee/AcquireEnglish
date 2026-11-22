import 'package:flutter/material.dart';

import 'study_oral_coach_tab.dart';

/// Standalone AI 外教 entry (video-call lesson). Not AI 伴读 / 口语跟读.
class DigitalHumanCoachScreen extends StatelessWidget {
  const DigitalHumanCoachScreen({
    super.key,
    this.initialScenarioId,
    this.lessonTitle,
    this.lessonText,
    this.practiceRole,
    this.onConfirmedLearnerTurn,
  });

  final String? initialScenarioId;
  final String? lessonTitle, lessonText, practiceRole;
  final ValueChanged<String>? onConfirmedLearnerTurn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14102A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(lessonTitle ?? 'AI 外教'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 4),
          child: StudyOralCoachTab(
            topicSummary: lessonTitle == null
                ? '英语口语闲聊'
                : 'Practise the scenario: $lessonTitle. The learner plays role $practiceRole. You play the other role. Use the example dialogue as context and provide helpful feedback.',
            articleExcerpt: lessonText ?? '',
            courseTitle: lessonTitle?.trim().isNotEmpty == true
                ? lessonTitle!.trim()
                : 'AI 外教课',
            hasTranscript: lessonText?.isNotEmpty == true,
            standalone: true,
            onConfirmedLearnerTurn: onConfirmedLearnerTurn,
            initialScenarioId: lessonText?.isNotEmpty == true
                ? 'video_line'
                : initialScenarioId ?? 'freechat',
          ),
        ),
      ),
    );
  }
}
