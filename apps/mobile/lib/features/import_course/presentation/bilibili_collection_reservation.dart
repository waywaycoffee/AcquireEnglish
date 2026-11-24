import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/bilibili_collection_download.dart';
import '../data/bilibili_multipage.dart';
import '../data/bilibili_import_service.dart';
import '../data/bilibili_open_or_import.dart';
import '../domain/bilibili_import.dart';

String _reservationKey(String email, String courseId) =>
    'bilibili-reservation:$email:$courseId';

bool isBilibiliCollectionReservationReady(String email, String courseId) =>
    Hive.isBoxOpen('prefs') &&
    Hive.box<String>(
          'prefs',
        ).get('${_reservationKey(email, courseId)}:ready') ==
        '1';

class BilibiliCollectionReservation extends ConsumerStatefulWidget {
  const BilibiliCollectionReservation({required this.source, super.key});

  final String source;

  @override
  ConsumerState<BilibiliCollectionReservation> createState() =>
      _BilibiliCollectionReservationState();
}

class _BilibiliCollectionReservationState
    extends ConsumerState<BilibiliCollectionReservation> {
  Timer? _refresh;
  bool _busy = false;
  bool _ready = false;
  bool _requested = false;
  bool _checking = false;

  LibraryCourseData? get _course => findLibraryEpisodeForBilibiliInput(
    ref.read(libraryCatalogProvider),
    widget.source,
  )?.course;

  String? _key(LibraryCourseData? course) {
    final account = ref.read(authSessionProvider);
    if (!account.isLoggedIn || course == null) return null;
    return _reservationKey(account.email, course.id);
  }

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_check()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _busy || !Hive.isBoxOpen('prefs')) return;
    final key = _key(_course);
    if (key == null) return;
    final ids = Hive.box<String>('prefs').get(key)?.split(',') ?? const [];
    if (ids.isEmpty) return;
    _checking = true;
    try {
      final jobs = await Future.wait(
        ids.map(ref.read(acquireApiClientProvider).getSharedSubtitleJob),
      );
      if (!mounted || key != _key(_course)) return;
      final ready = jobs.every((job) => job?.state == 'completed');
      if (ready) {
        await Hive.box<String>('prefs').put('$key:ready', '1');
      }
      if (!mounted || key != _key(_course)) return;
      setState(() {
        _ready = ready;
        _requested = !jobs.any((job) => job?.isTerminalFailure ?? false);
      });
    } finally {
      _checking = false;
    }
  }

  Future<void> _reserve() async {
    setState(() => _busy = true);
    try {
      if (!ref.read(authSessionProvider).isLoggedIn) {
        throw StateError('请先登录再预约字幕');
      }
      if (_course == null) {
        await openBilibiliLearningOrImport(
          context,
          ref,
          watchUrl: widget.source,
          startImportImmediately: true,
          pushPlayer: false,
        );
      }
      if (!mounted) return;
      final course = _course;
      final key = _key(course);
      if (course == null || key == null) return;
      if (!isMultiEpisodeBilibiliCourse(course)) {
        throw StateError('这是单集视频，可直接在线播放');
      }

      final api = ref.read(acquireApiClientProvider);
      final service = BilibiliImportService.withCookie(
        ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
      );
      final ids = <String>{};
      for (final episode in course.episodes) {
        final source = bilibiliSourceForEpisode(
          course: course,
          episode: episode,
          videoAsset: episode.videoAsset,
        );
        if (source == null) throw StateError('第 ${episode.numberStr} 集缺少链接');
        final parsed = await service.resolveIds(source);
        final bvid = parsed?['bvid'];
        final job = bvid == null
            ? null
            : await api.enqueueSharedSubtitleJob(
                bvid: bvid,
                page: BilibiliImport.extractPage(source) ?? 1,
              );
        if (job == null || job.id.isEmpty || job.isTerminalFailure) {
          throw StateError('第 ${episode.numberStr} 集字幕预约未提交，请重试');
        }
        ids.add(job.id);
      }
      await Hive.box<String>('prefs').put(key, ids.join(','));
      if (!mounted) return;
      setState(() => _requested = true);
      _message('已预约，工作站准备好字幕后可进入合集');
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        unawaited(_check());
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final course = _course;
    return TextButton(
      onPressed: _busy || (_requested && !_ready)
          ? null
          : _ready && course != null
          ? () => context.push(
              Uri(
                path: SGRoute.library.route,
                queryParameters: {'view': 'detail', 'courseId': course.id},
              ).toString(),
            )
          : () => unawaited(_reserve()),
      child: Text(
        _ready
            ? '进入视频合集'
            : _busy
            ? '正在预约…'
            : _requested
            ? '已预约 · 字幕准备中'
            : '预约明日看此视频',
      ),
    );
  }
}
