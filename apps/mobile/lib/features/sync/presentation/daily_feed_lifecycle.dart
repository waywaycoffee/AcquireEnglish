import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../data/acquire_api_client.dart';
import '../data/vocab_sync_service.dart';
import 'cloud_catalog_sync.dart';
import 'daily_feed_provider.dart';

/// Cold-start + resume refresh for daily Bilibili recommendations (>20h / force).
class DailyFeedLifecycleHost extends ConsumerStatefulWidget {
  const DailyFeedLifecycleHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DailyFeedLifecycleHost> createState() =>
      _DailyFeedLifecycleHostState();
}

class _DailyFeedLifecycleHostState extends ConsumerState<DailyFeedLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refresh(showSnack: false));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh(showSnack: true));
    }
  }

  Future<void> _refresh({required bool showSnack}) async {
    final int before = ref.read(dailyFeedProvider).length;
    final Set<String> beforeIds = ref
        .read(dailyFeedProvider)
        .map((AcquireDailyFeedItemDto item) => item.id)
        .toSet();
    ref.invalidate(cloudCatalogSyncProvider);
    await ref.read(cloudCatalogSyncProvider.future);
    await ref.read(vocabSyncServiceProvider).pullAndMerge();
    if (!mounted || !showSnack) {
      return;
    }
    final AcquirePreferencesDto prefs = ref.read(learningPreferencesProvider);
    if (!prefs.notifyDailyFeed) {
      return;
    }
    final List<AcquireDailyFeedItemDto> feed = ref.read(dailyFeedProvider);
    final int newCount = feed
        .where((AcquireDailyFeedItemDto item) => !beforeIds.contains(item.id))
        .length;
    if (newCount <= 0 && feed.length <= before) {
      return;
    }
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    final String day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final Box<String> box = Hive.box<String>('prefs');
    if (box.get('daily_feed_notified_day_v1') == day) {
      return;
    }
    await box.put('daily_feed_notified_day_v1', day);
    final int n = newCount > 0 ? newCount : feed.length;
    if (n <= 0 || !mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('每日推荐更新了 $n 条 B站视频')),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
