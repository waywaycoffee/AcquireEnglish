import 'package:flutter/material.dart';

import 'study_oral_coach_tab.dart';

/// Standalone digital-human module entry (scenario dialogue without a video).
class DigitalHumanCoachScreen extends StatelessWidget {
  const DigitalHumanCoachScreen({
    super.key,
    this.initialScenarioId,
  });

  final String? initialScenarioId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14102A),
      appBar: AppBar(
        title: const Text('数字人口语'),
        backgroundColor: const Color(0xFF14102A),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        child: StudyOralCoachTab(
          topicSummary: '英语口语闲聊',
          articleExcerpt: '',
          courseTitle: '数字人口语',
          hasTranscript: false,
          standalone: true,
          initialScenarioId: initialScenarioId ?? 'freechat',
        ),
      ),
    );
  }
}
