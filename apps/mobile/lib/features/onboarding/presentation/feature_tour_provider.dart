import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/feature_tour_prefs.dart';
import 'feature_tour_keys.dart';

enum FeatureTourStep {
  recentWatched,
  navLibrary,
  navReading,
  navOral,
  navMore,
  wrapUp,
}

class FeatureTourStepCopy {
  const FeatureTourStepCopy({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

const List<FeatureTourStepCopy> kFeatureTourCopy =
    <FeatureTourStepCopy>[
  FeatureTourStepCopy(
    title: '最近看过',
    body: '看过的视频和文章会出现在这里，方便接着上次继续学。',
  ),
  FeatureTourStepCopy(
    title: '视频',
    body: '浏览课程、查看集数进度，点进去就能逐句精听。',
  ),
  FeatureTourStepCopy(
    title: '阅读',
    body: '爱快阅读：泛读短文，点词进词书；也可从网盘导入 EPUB。',
  ),
  FeatureTourStepCopy(
    title: '口语',
    body: '和数字人开口练习，把听过的内容说出来。',
  ),
  FeatureTourStepCopy(
    title: '更多 · 导入',
    body: '这里可以导入 B 站、YouTube 或网盘课程，也能打开怎么学与设置。',
  ),
  FeatureTourStepCopy(
    title: '开始学习吧',
    body: '播放器里可看「怎么学」；收藏的句子会按复习回来。随时可在设置里重看本引导。',
  ),
];

@immutable
class FeatureTourState {
  const FeatureTourState({
    this.active = false,
    this.stepIndex = 0,
  });

  final bool active;
  final int stepIndex;

  FeatureTourStep get step =>
      FeatureTourStep.values[stepIndex.clamp(0, FeatureTourStep.values.length - 1)];

  FeatureTourStepCopy get copy => kFeatureTourCopy[stepIndex.clamp(
        0,
        kFeatureTourCopy.length - 1,
      )];

  int get stepCount => FeatureTourStep.values.length;

  FeatureTourState copyWith({bool? active, int? stepIndex}) {
    return FeatureTourState(
      active: active ?? this.active,
      stepIndex: stepIndex ?? this.stepIndex,
    );
  }
}

class FeatureTourNotifier extends Notifier<FeatureTourState> {
  @override
  FeatureTourState build() => const FeatureTourState();

  /// Starts the tour unless already seen (pass [force] from Settings replay).
  void start({bool force = false}) {
    if (!force && readHomeFeatureTourSeen()) {
      return;
    }
    state = const FeatureTourState(active: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareStep(FeatureTourStep.recentWatched);
    });
  }

  void next() {
    if (!state.active) return;
    final int last = FeatureTourStep.values.length - 1;
    if (state.stepIndex >= last) {
      complete();
      return;
    }
    final int nextIndex = state.stepIndex + 1;
    state = state.copyWith(stepIndex: nextIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareStep(FeatureTourStep.values[nextIndex]);
    });
  }

  Future<void> skip() => complete();

  Future<void> complete() async {
    if (!state.active && readHomeFeatureTourSeen()) {
      return;
    }
    state = const FeatureTourState();
    await markHomeFeatureTourSeen();
  }

  Future<void> resetAndStart() async {
    await resetHomeFeatureTourSeen();
    start(force: true);
  }

  void _prepareStep(FeatureTourStep step) {
    void ensure(GlobalKey key) {
      final BuildContext? ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    }

    switch (step) {
      case FeatureTourStep.recentWatched:
        ensure(FeatureTourKeys.recentWatched);
      case FeatureTourStep.navLibrary:
        ensure(FeatureTourKeys.navLibrary);
      case FeatureTourStep.navReading:
        ensure(FeatureTourKeys.navReading);
      case FeatureTourStep.navOral:
        ensure(FeatureTourKeys.navOral);
      case FeatureTourStep.navMore:
        ensure(FeatureTourKeys.navMore);
      case FeatureTourStep.wrapUp:
        break;
    }
  }
}

final NotifierProvider<FeatureTourNotifier, FeatureTourState>
    featureTourProvider =
    NotifierProvider<FeatureTourNotifier, FeatureTourState>(
  FeatureTourNotifier.new,
);
