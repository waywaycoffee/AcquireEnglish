import 'package:flutter/material.dart';

import '../../../library/presentation/widgets/ensuring_course_poster.dart';
import '../../../player/presentation/learning_resume_provider.dart';

/// Home "继续学习" poster: prefers episode cover, backfills Bilibili posters.
class ContinueLearningPoster extends StatelessWidget {
  const ContinueLearningPoster({
    required this.target,
    required this.borderRadius,
    super.key,
  });

  final ContinueLearningTarget target;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return EnsuringCoursePoster(
      course: target.course,
      episode: target.episode,
      borderRadius: borderRadius,
    );
  }
}
