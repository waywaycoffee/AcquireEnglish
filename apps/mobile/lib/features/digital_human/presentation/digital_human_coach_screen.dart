import 'package:flutter/material.dart';

import 'study_oral_coach_tab.dart';

/// Digital human conversation, with a guided lesson when material is supplied.
class DigitalHumanCoachScreen extends StatelessWidget {
  const DigitalHumanCoachScreen({
    super.key,
    this.initialScenarioId,
    this.lessonTitle,
    this.guidedLesson = false,
    this.lessonText,
    this.practiceRole,
    this.onConfirmedLearnerTurn,
  });

  final String? initialScenarioId;
  final bool guidedLesson;
  final String? lessonTitle, lessonText, practiceRole;
  final ValueChanged<String>? onConfirmedLearnerTurn;

  @override
  Widget build(BuildContext context) {
    final String title = lessonTitle?.trim() ?? '';
    final bool hasMaterial = lessonText?.trim().isNotEmpty == true;
    final String displayTitle = title.isNotEmpty
        ? title
        : (guidedLesson && hasMaterial ? 'AI 外教课' : '数字人口语');
    return Scaffold(
      backgroundColor: const Color(0xFF14102A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(displayTitle),
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
            topicSummary: hasMaterial
                ? 'Practise the scenario: $displayTitle. The learner plays role ${practiceRole ?? 'learner'}. You play the other role. Use the example dialogue as context and provide helpful feedback.'
                : '英语口语闲聊',
            articleExcerpt: lessonText ?? '',
            courseTitle: displayTitle,
            hasTranscript: hasMaterial,
            standalone: true,
            guidedLesson: guidedLesson,
            onConfirmedLearnerTurn: onConfirmedLearnerTurn,
            initialScenarioId: hasMaterial
                ? 'video_line'
                : initialScenarioId ?? 'freechat',
          ),
        ),
      ),
    );
  }
}
