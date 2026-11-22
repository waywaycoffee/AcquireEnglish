import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';

/// Legacy phrase ladder is retired; send users into the unified FSRS session.
class PhraseReviewScreen extends StatelessWidget {
  const PhraseReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.go('${SGRoute.reviewSession.route}?kind=phrase');
    });
    return PadScaffold(
      currentDestination: AppNavDestination.home,
      showContinueLearning: false,
      topBar: const PadTopBar(
        title: '短语复习',
        description: '已并入统一 FSRS 背诵队列',
      ),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
