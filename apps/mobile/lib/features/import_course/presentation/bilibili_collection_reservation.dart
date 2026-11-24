import 'dart:async';

import 'package:dio/dio.dart';
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
import '../../subtitle_completion/shared_bilibili_subtitle_sync.dart';
import '../data/bilibili_collection_download.dart';
import '../data/bilibili_multipage.dart';
import '../data/bilibili_import_service.dart';
import '../data/bilibili_open_or_import.dart';
import '../domain/bilibili_import.dart';

String _reservationKey(String email, String courseId) =>
    'bilibili-reservation:$email:$courseId';

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
  bool _waitingForCapacity = false;

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
      (_) => unawaited(_waitingForCapacity ? _reserve(retry: true) : _check()),
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
    final ids = (Hive.box<String>('prefs').get(key) ?? '')
        .split(',')
        .where((id) => id.isNotEmpty);
    if (Hive.box<String>('prefs').get('$key:ready') == '1' && ids.isEmpty) {
      if (mounted && !_ready) setState(() => _ready = true);
      return;
    }
    if (ids.isEmpty || Hive.box<String>('prefs').containsKey('$key:next')) {
      return;
    }
    _checking = true;
    try {
      final jobs = await Future.wait(
        ids.map(ref.read(acquireApiClientProvider).getSharedSubtitleJob),
      );
      if (!mounted || key != _key(_course)) return;
      final hasRejectedEpisodes = Hive.box<String>(
        'prefs',
      ).containsKey('$key:rejected');
      final ready =
          !hasRejectedEpisodes &&
          jobs.every((job) => job?.state == 'completed');
      if (ready) {
        await Hive.box<String>('prefs').put('$key:ready', '1');
      }
      if (!mounted || key != _key(_course)) return;
      setState(() {
        _ready = ready;
        _requested =
            !hasRejectedEpisodes &&
            !jobs.any((job) => job?.isTerminalFailure ?? false);
      });
    } finally {
      _checking = false;
    }
  }

  Future<void> _reserve({bool retry = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!ref.read(authSessionProvider).isLoggedIn) {
        _message('请先登录再预约字幕');
        return;
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
      if (course == null || key == null) {
        _message('合集资料尚未加载，请稍后重试');
        return;
      }
      if (!isMultiEpisodeBilibiliCourse(course)) {
        _message('这是单集视频，可直接在线播放');
        return;
      }

      final api = ref.read(acquireApiClientProvider);
      final service = BilibiliImportService.withCookie(
        ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
      );
      final prefs = Hive.box<String>('prefs');
      final next = int.tryParse(prefs.get('$key:next') ?? '') ?? 0;
      final ids = <String>{...prefs.get(key)?.split(',') ?? const <String>[]}
        ..remove('');
      final rejected = <String>{
        ...prefs.get('$key:rejected')?.split(',') ?? const <String>[],
      }..remove('');
      if (next == 0) {
        rejected.clear();
        await prefs.delete('$key:rejected');
        ids.clear();
        await prefs.delete(key);
        await prefs.delete('$key:ready');
        await prefs.put('$key:next', '0');
      }
      for (var index = next; index < course.episodes.length; index++) {
        if (!mounted || key != _key(_course)) return;
        final episode = course.episodes[index];
        try {
          final source = bilibiliSourceForEpisode(
            course: course,
            episode: episode,
            videoAsset: episode.videoAsset,
          );
          if (source == null)
            throw FormatException('第 ${episode.numberStr} 集缺少链接');
          final identity = resolveBilibiliSharedSubtitleIds(
            course: course,
            episode: episode,
            sourceUrl: source,
          );
          final bvid =
              identity?.bvid ?? (await service.resolveIds(source))?['bvid'];
          if (bvid == null)
            throw FormatException('第 ${episode.numberStr} 集链接无法识别');
          final page =
              identity?.page ?? BilibiliImport.extractPage(source) ?? 1;
          final pack = await api.getSharedBilibiliSubtitle(
            bvid: bvid,
            page: page,
          );
          final String english = pack?.subtitleEnSrt.trim() ?? '';
          if (english.isEmpty || (pack?.subtitleZhSrt ?? '').trim().isEmpty) {
            if (!mounted || key != _key(_course)) return;
            final job = english.isEmpty
                ? await api.enqueueSharedSubtitleJob(
                    bvid: bvid,
                    page: page,
                    reportErrors: true,
                  )
                : await api.enqueueSharedSubtitleTranslateJob(
                    bvid: bvid,
                    page: page,
                    subtitleEnSrt: english,
                    title: episode.title,
                    durationSec: pack?.durationSec,
                    reportErrors: true,
                  );
            if (job == null || job.id.isEmpty || job.isTerminalFailure) {
              throw FormatException('第 ${episode.numberStr} 集字幕预约未提交，请重试');
            }
            ids.add(job.id);
            await prefs.put(key, ids.join(','));
          }
        } on FormatException {
          rejected.add(episode.numberStr);
        } on DioException catch (error) {
          final response = error.response;
          final detail = response?.data;
          final message = detail is Map ? detail['detail'] : null;
          if (response?.statusCode != 422 ||
              (message is String && message.startsWith('bvid_page_cap:'))) {
            rethrow;
          }
          rejected.add(episode.numberStr);
        }
        if (rejected.isNotEmpty) {
          await prefs.put('$key:rejected', rejected.join(','));
        }
        await prefs.put('$key:next', '${index + 1}');
      }
      await prefs.delete('$key:next');
      if (ids.isEmpty && rejected.isEmpty) {
        await prefs.put('$key:ready', '1');
      }
      if (!mounted || key != _key(_course)) return;
      setState(() {
        _waitingForCapacity = false;
        _requested = rejected.isEmpty;
        _ready = ids.isEmpty && rejected.isEmpty;
      });
      if (rejected.isNotEmpty) {
        _message('第 ${rejected.join('、')} 集字幕预约未提交，其他集可照常学习');
      } else {
        _message(ids.isEmpty ? '公共字幕已齐，可以进入合集' : '已预约，工作站正在准备缺失的字幕');
      }
    } on DioException catch (error) {
      if (!mounted) return;
      final Object? response = error.response?.data;
      final Object? detail = response is Map ? response['detail'] : null;
      final bool atCapacity =
          error.response?.statusCode == 429 ||
          (detail is String && detail.startsWith('bvid_page_cap:'));
      setState(() => _waitingForCapacity = atCapacity);
      if (!atCapacity || !retry) {
        _message(
          atCapacity
              ? '已保留预约进度，队列有空位后会继续提交'
              : error.response?.statusCode == 401
              ? '登录已失效，请重新登录后继续预约'
              : '字幕服务暂时不可用，请稍后继续预约',
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _waitingForCapacity = false);
        _message(error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _waitingForCapacity = false);
        _message('预约暂时无法完成，请稍后重试');
      }
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
            : _waitingForCapacity
            ? '等待字幕队列空位'
            : _requested
            ? '已预约 · 字幕准备中'
            : '预约明日看此视频',
      ),
    );
  }
}
