import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../daily_path/domain/official_bilibili_softsub_series.dart';
import '../../library/domain/episode_local_ready.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../subtitle_completion/shared_bilibili_subtitle_sync.dart';
import '../data/bilibili_collection_download.dart';
import '../data/bilibili_episode_prepare.dart';
import '../data/bilibili_multipage.dart';
import '../data/bilibili_import_service.dart';
import '../data/bilibili_open_or_import.dart';
import '../domain/bilibili_import.dart';
import '../domain/youtube_import.dart';

String _reservationKey(String email, String courseId) =>
    'bilibili-reservation:$email:$courseId';

String _sourceReservationKey(String email, String sourceId) =>
    'bilibili-reservation:$email:src:$sourceId';

/// Compact CTA that reserves shared EN/ZH subtitles for a video or collection.
///
/// Works for single episodes (browse cards, 全英可逛) and multi-episode courses.
class BilibiliCollectionReservation extends ConsumerStatefulWidget {
  const BilibiliCollectionReservation({
    required this.source,
    this.courseId,
    super.key,
  });

  final String source;
  final String? courseId;

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

  LibraryCourseData? get _course {
    final courses = ref.read(libraryCatalogProvider);
    final courseId = widget.courseId;
    if (courseId != null) {
      return courses.where((course) => course.id == courseId).firstOrNull;
    }
    return findLibraryEpisodeForBilibiliInput(courses, widget.source)?.course;
  }

  bool _isMulti(LibraryCourseData? course) {
    if (course == null || course.episodes.length < 2) return false;
    final youtube = course.id.startsWith('youtube-');
    return youtube || isMultiEpisodeBilibiliCourse(course);
  }

  String? _sourceId() {
    final String raw = widget.source.trim();
    if (raw.isEmpty) return null;
    final String? yt = YoutubeImport.extractVideoId(raw);
    if (yt != null && yt.isNotEmpty) return 'yt:$yt';
    // Youtube browse items often pass bare video ids.
    if (RegExp(r'^[\w-]{6,}$').hasMatch(raw) && !raw.toUpperCase().startsWith('BV')) {
      return 'yt:$raw';
    }
    final Map<String, String>? ids = BilibiliImport.extractIds(raw);
    final String bvid = (ids?['bvid'] ?? '').trim().toUpperCase();
    if (bvid.isEmpty) return null;
    final int page = BilibiliImport.extractPage(raw) ?? 1;
    return 'bv:$bvid:p$page';
  }

  String? _key(LibraryCourseData? course) {
    final account = ref.read(authSessionProvider);
    if (!account.isLoggedIn) return null;
    if (course != null) {
      return _reservationKey(account.email, course.id);
    }
    final String? sid = _sourceId();
    if (sid == null) return null;
    return _sourceReservationKey(account.email, sid);
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
    final key = _key(_course) ?? _key(null);
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
      if (!mounted || key != (_key(_course) ?? _key(null))) return;
      final hasRejectedEpisodes = Hive.box<String>(
        'prefs',
      ).containsKey('$key:rejected');
      final ready =
          !hasRejectedEpisodes &&
          jobs.every((job) => job?.state == 'completed');
      if (ready) {
        await Hive.box<String>('prefs').put('$key:ready', '1');
      }
      if (!mounted || key != (_key(_course) ?? _key(null))) return;
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

      LibraryCourseData? course = _course;
      // Multi-episode collections need a library course; import first if missing.
      if (course == null && _looksLikeCollectionSource()) {
        await openBilibiliLearningOrImport(
          context,
          ref,
          watchUrl: widget.source,
          startImportImmediately: true,
          pushPlayer: false,
        );
        if (!mounted) return;
        course = _course;
      }

      if (_isMulti(course)) {
        await _reserveMulti(course!, retry: retry);
        return;
      }

      await _reserveSingle(course: course, retry: retry);
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
              ? '已保留预约字幕进度，队列有空位后会继续提交'
              : error.response?.statusCode == 401
              ? '登录已失效，请重新登录后继续预约字幕'
              : '字幕服务暂时不可用，请稍后继续预约字幕',
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
        _message('预约字幕暂时无法完成，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        unawaited(_check());
      }
    }
  }

  bool _looksLikeCollectionSource() {
    final String raw = widget.source.toLowerCase();
    return raw.contains('/lists/') ||
        raw.contains('season_id=') ||
        raw.contains('media_id=') ||
        raw.contains('collection');
  }

  Future<void> _reserveSingle({
    LibraryCourseData? course,
    bool retry = false,
  }) async {
    final String? key = _key(course) ?? _key(null);
    if (key == null) {
      _message('请先登录再预约字幕');
      return;
    }

    final api = ref.read(acquireApiClientProvider);
    final prefs = Hive.box<String>('prefs');
    if (!retry) {
      await prefs.delete(key);
      await prefs.delete('$key:ready');
      await prefs.delete('$key:rejected');
      await prefs.delete('$key:next');
    } else if (prefs.get('$key:ready') == '1') {
      if (mounted) setState(() => _ready = true);
      return;
    }

    final String source = () {
      if (course != null && course.episodes.isNotEmpty) {
        return bilibiliSourceForEpisode(
              course: course,
              episode: course.episodes.first,
              videoAsset: course.episodes.first.videoAsset,
            ) ??
            course.episodes.first.sourceUrl ??
            widget.source;
      }
      return widget.source;
    }();

    final String? yt =
        YoutubeImport.extractVideoId(source) ??
        (course != null && course.id.startsWith('youtube-')
            ? YoutubeImport.extractVideoId(course.episodes.first.sourceUrl ?? '')
            : null) ??
        (_sourceId()?.startsWith('yt:') == true
            ? _sourceId()!.substring(3)
            : null);

    if (yt != null && yt.isNotEmpty) {
      final job = await api.enqueueYoutubeSubtitleJob(yt);
      if (job.id.isEmpty || job.isTerminalFailure) {
        throw const FormatException('预约字幕未提交，请重试');
      }
      await prefs.put(key, job.id);
      if (job.state == 'completed') {
        await prefs.put('$key:ready', '1');
        if (mounted) {
          setState(() {
            _ready = true;
            _requested = true;
            _waitingForCapacity = false;
          });
        }
        _message('公共字幕已齐，可以学习');
      } else if (mounted) {
        setState(() {
          _requested = true;
          _ready = false;
          _waitingForCapacity = false;
        });
        _message('已预约字幕，工作站正在准备');
      }
      return;
    }

    final service = BilibiliImportService.withCookie(
      ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
    );
    final identity = course == null || course.episodes.isEmpty
        ? null
        : resolveBilibiliSharedSubtitleIds(
            course: course,
            episode: course.episodes.first,
            sourceUrl: source,
          );
    final String? bvid =
        identity?.bvid ??
        (BilibiliImport.extractIds(source)?['bvid']) ??
        (await service.resolveIds(source))?['bvid'];
    if (bvid == null || bvid.isEmpty) {
      throw const FormatException('视频链接无法识别，无法预约字幕');
    }
    final int page =
        identity?.page ?? BilibiliImport.extractPage(source) ?? 1;

    final pack = await api.getSharedBilibiliSubtitle(bvid: bvid, page: page);
    final String english = (pack?.subtitleEnSrt ?? '').trim();
    final String chinese = (pack?.subtitleZhSrt ?? '').trim();
    if (english.isNotEmpty && chinese.isNotEmpty) {
      await prefs.put('$key:ready', '1');
      await prefs.delete(key);
      if (mounted) {
        setState(() {
          _ready = true;
          _requested = true;
          _waitingForCapacity = false;
        });
      }
      _message('公共字幕已齐，可以学习');
      return;
    }

    final SharedSubtitleGpuJob? job = english.isEmpty
        ? await api.enqueueSharedSubtitleJob(
            bvid: bvid,
            page: page,
            reportErrors: true,
            reserve: true,
          )
        : await api.enqueueSharedSubtitleTranslateJob(
            bvid: bvid,
            page: page,
            subtitleEnSrt: english,
            title: course?.title,
            durationSec: pack?.durationSec,
            reportErrors: true,
            reserve: true,
          );
    if (job == null || job.id.isEmpty || job.isTerminalFailure) {
      throw const FormatException('预约字幕未提交，请重试');
    }
    await prefs.put(key, job.id);
    if (mounted) {
      setState(() {
        _requested = true;
        _ready = false;
        _waitingForCapacity = false;
      });
    }
    _message('已预约字幕，工作站正在准备');
  }

  Future<void> _reserveMulti(
    LibraryCourseData course, {
    bool retry = false,
  }) async {
    final key = _key(course);
    if (key == null) {
      _message('合集资料尚未加载，请稍后重试');
      return;
    }

    final youtube = course.id.startsWith('youtube-');
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
        if (youtube) {
          final id = YoutubeImport.extractVideoId(episode.sourceUrl ?? '');
          if (id == null) throw const FormatException('缺少 YouTube 视频 ID');
          final job = await api.enqueueYoutubeSubtitleJob(id);
          if (job.id.isEmpty) throw const FormatException('预约字幕未提交');
          ids.add(job.id);
          await prefs.put(key, ids.join(','));
          await prefs.put('$key:next', '${index + 1}');
          continue;
        }
        final source = bilibiliSourceForEpisode(
          course: course,
          episode: episode,
          videoAsset: episode.videoAsset,
        );
        if (source == null) {
          throw FormatException('第 ${episode.numberStr} 集缺少链接');
        }
        final identity = resolveBilibiliSharedSubtitleIds(
          course: course,
          episode: episode,
          sourceUrl: source,
        );
        final bvid =
            identity?.bvid ?? (await service.resolveIds(source))?['bvid'];
        if (bvid == null) {
          throw FormatException('第 ${episode.numberStr} 集链接无法识别');
        }
        final page =
            identity?.page ?? BilibiliImport.extractPage(source) ?? 1;
        final pack = await api.getSharedBilibiliSubtitle(
          bvid: bvid,
          page: page,
        );
        final String english = (pack?.subtitleEnSrt ?? '').trim();
        if (english.isEmpty || (pack?.subtitleZhSrt ?? '').trim().isEmpty) {
          if (!mounted || key != _key(_course)) return;
          final job = english.isEmpty
              ? await api.enqueueSharedSubtitleJob(
                  bvid: bvid,
                  page: page,
                  reportErrors: true,
                  reserve: true,
                )
              : await api.enqueueSharedSubtitleTranslateJob(
                  bvid: bvid,
                  page: page,
                  subtitleEnSrt: english,
                  title: episode.title,
                  durationSec: pack?.durationSec,
                  reportErrors: true,
                  reserve: true,
                );
          if (job == null || job.id.isEmpty || job.isTerminalFailure) {
            throw FormatException('第 ${episode.numberStr} 集预约字幕未提交，请重试');
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
      _message('第 ${rejected.join('、')} 集预约字幕未提交，其他集可照常学习');
    } else {
      _message(ids.isEmpty ? '公共字幕已齐，可以进入合集' : '已预约字幕，工作站正在准备');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _alreadyHasSubtitles(LibraryCourseData? course) {
    if (course != null) {
      if (course.id == 'oral_core_9000' || courseHasStudySubtitles(course)) {
        return true;
      }
    }
    final String source = widget.source.trim();
    if (source.isEmpty) return false;
    // Official ECS softsub series (9000句 etc.) — never show 预约字幕.
    if (sourceLooksLikeOfficialBilibiliSoftsubSeries(source)) {
      return true;
    }
    final hit = findLibraryEpisodeForBilibiliInput(
      ref.read(libraryCatalogProvider),
      source,
    );
    final LibraryEpisodeItem? episode = hit?.episode;
    if (episode == null) return false;
    return episodeHasStudySubtitles(episode) ||
        isUsableSubtitlePath(episode.enSubtitleAsset) ||
        isUsableSubtitlePath(episode.cnSubtitleAsset);
  }

  @override
  Widget build(BuildContext context) {
    final LibraryCourseData? course = _course;
    // Official / server / local softsubs already present → hide CTA entirely.
    if (_ready || _alreadyHasSubtitles(course)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: _busy || (_requested && !_ready)
          ? null
          : () => unawaited(_reserve()),
      child: Text(
        _busy
            ? '正在预约字幕…'
            : _waitingForCapacity
            ? '等待字幕队列空位'
            : _requested
            ? '已预约字幕'
            : '预约字幕',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: _requested
              ? AppDesignTokens.textSecondary
              : AppDesignTokens.brandGreen,
        ),
      ),
    );
  }
}
