import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/domain/module_access.dart';
import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../../settings/presentation/bilibili_login_sheet.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/personal_import_sync.dart';
import '../../sync/presentation/user_assets_provider.dart';
import '../data/bilibili_course_builder.dart';
import '../data/bilibili_import_service.dart';
import '../domain/bilibili_import.dart';

Future<String?> showBilibiliImportSheet(
  BuildContext context,
  WidgetRef ref, {
  String? initialUrl,
  bool startImmediately = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: StudyShellTokens.surface,
    builder: (BuildContext context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: _BilibiliImportForm(
          initialUrl: initialUrl,
          startImmediately: startImmediately,
        ),
      );
    },
  );
}

class _BilibiliImportForm extends ConsumerStatefulWidget {
  const _BilibiliImportForm({this.initialUrl, required this.startImmediately});

  final String? initialUrl;
  final bool startImmediately;

  @override
  ConsumerState<_BilibiliImportForm> createState() =>
      _BilibiliImportFormState();
}

class _BilibiliImportFormState extends ConsumerState<_BilibiliImportForm> {
  late final TextEditingController _controller;
  String? _error;
  bool _busy = false;
  double? _progress;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? '');
    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) unawaited(_submit());
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  BilibiliImportService _serviceForSettings() {
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    return BilibiliImportService.withCookie(
      settings.resolvedBilibiliCookieHeader,
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String cleaned = BilibiliImport.normalizeInput(_controller.text);
    if (cleaned != _controller.text) {
      _controller.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    if (!BilibiliImport.looksLikeBilibiliInput(cleaned)) {
      setState(() => _error = '识别不到 B 站链接。可粘贴完整分享文案，或 b23.tv / BV / av');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
      _status = '正在解析链接…';
    });
    try {
      final BilibiliImportService service = _serviceForSettings();
      final BilibiliImportResult meta = await service.fetch(
        cleaned, includeSubtitles: false,
      );
      if (!mounted) return;
      final LibraryCourseData course = buildLibraryCourseFromBilibiliImport(
        meta,
      );
      final LibraryEpisodeItem? importedEpisode = course.episodes.firstOrNull;
      // Refresh entitlements so Pro is recognized without visiting 会员页 first.
      try {
        await ref.read(userAssetsProvider.notifier).refresh();
      } catch (_) {}
      final bool unlimited = await resolveModuleUnlocked(ref, 'video');
      final bool ok = await ref
          .read(libraryCatalogProvider.notifier)
          .importCourse(course, unlimitedPersonalLibrary: unlimited);
      if (!mounted) return;
      if (!ok || importedEpisode == null) {
        throw StateError('视频未能加入书库，请重试');
      }
      // Auto-save to personal cloud; shared if official pack passes audit.
      final AuthSessionState auth = ref.read(authSessionProvider);
      if (auth.isLoggedIn) {
        unawaited(
          syncEpisodeSubtitlesToCloud(
            api: ref.read(acquireApiClientProvider),
            isLoggedIn: true,
            sourceKey: meta.idKey,
            sourceUrl: meta.watchUrl,
            englishPath: meta.enSubtitlePath ?? '',
            chinesePath: meta.cnSubtitlePath ?? '',
            course: course,
            episode: importedEpisode,
            durationSec: meta.durationMinutes * 60,
            sourceOrigin: 'official',
          ),
        );
        // B站资源自动共享到社区，他人可直接点开。
        unawaited(() async {
          try {
            final AcquireApiClient api = ref.read(acquireApiClientProvider);
            await api.createCommunityPost(
              kind: 'share_bilibili',
              title: importedEpisode.title.trim().isEmpty
                  ? course.title
                  : importedEpisode.title,
              body: 'B站学习资源 · 自动共享',
              linkUrl: meta.watchUrl,
              linkTitle: importedEpisode.title.trim().isEmpty
                  ? course.title
                  : importedEpisode.title,
              linkCover: importedEpisode.coverImage.isNotEmpty
                  ? importedEpisode.coverImage
                  : course.coverImage,
            );
            final String day =
                DateTime.now().toIso8601String().substring(0, 10);
            await api.reportCommunityContentEngage(
              day: day,
              contentType: 'video',
              contentKey: 'bilibili:${meta.idKey}',
              title: importedEpisode.title.trim().isEmpty
                  ? course.title
                  : importedEpisode.title,
              coverUrl: importedEpisode.coverImage.isNotEmpty
                  ? importedEpisode.coverImage
                  : course.coverImage,
              openUrl: meta.watchUrl,
              source: 'bilibili',
            );
          } catch (_) {}
        }());
      }
      final messenger = ScaffoldMessenger.of(context);
      final success = course.episodes.length > 1
          ? '在线播放第一集。预约后会在工作站准备字幕，也可手动下载合集。'
          : '在线播放。手动下载后，本地播放更流畅。';
      Navigator.of(context).pop(importedEpisode.id);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _progress = null;
        _status = '';
        _error = '导入失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool hasCookie = settings.hasBilibiliCookie;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          '导入 Bilibili 链接',
          style: TextStyle(
            color: StudyShellTokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '粘贴分享文案后可在线播放。',
          style: TextStyle(color: StudyShellTokens.textSecondary),
        ),
        if (!hasCookie) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final bool ok = await showBilibiliLoginSheet(context, ref);
                    if (!mounted || !ok) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('B 站登录成功，可继续导入')),
                    );
                  },
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('扫码登录哔哩哔哩'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          enabled: !_busy,
          style: const TextStyle(color: StudyShellTokens.textPrimary),
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '【标题-哔哩哔哩】 https://b23.tv/xxxxx',
            hintStyle: TextStyle(color: StudyShellTokens.textMuted),
          ),
        ),
        if (_busy) ...<Widget>[
          const SizedBox(height: 12),
          if (_progress != null)
            LinearProgressIndicator(value: _progress)
          else
            const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            _status.isEmpty ? '处理中…' : _status,
            style: const TextStyle(color: StudyShellTokens.textSecondary),
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFB7299),
          ),
          child: Text(
            _busy
                ? '下载中…'
                : _error != null
                ? '重试导入'
                : '下载并加入书库',
          ),
        ),
      ],
    );
  }
}
