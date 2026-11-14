import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../../settings/presentation/bilibili_login_sheet.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import '../data/bilibili_collection_download.dart';
import '../data/bilibili_course_builder.dart';
import '../data/bilibili_import_service.dart';
import '../domain/bilibili_import.dart';

Future<void> showBilibiliImportSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
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
        child: const _BilibiliImportForm(),
      );
    },
  );
}

class _BilibiliImportForm extends ConsumerStatefulWidget {
  const _BilibiliImportForm();

  @override
  ConsumerState<_BilibiliImportForm> createState() => _BilibiliImportFormState();
}

class _BilibiliImportFormState extends ConsumerState<_BilibiliImportForm> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _busy = false;
  double? _progress;
  String _status = '';

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
      final BilibiliImportResult meta = await service.fetchAndDownloadLocal(
        cleaned,
        onProgress: (double? progress, String message) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = progress;
            _status = message;
          });
        },
      );
      if (meta.localVideoPath == null || meta.localVideoPath!.isEmpty) {
        throw StateError('视频未能下载到本地');
      }
      final LibraryCourseData course = buildLibraryCourseFromBilibiliImport(meta);
      final bool ok = await ref
          .read(libraryCatalogProvider.notifier)
          .importCourse(course);
      if (ok) {
        unawaited(enqueueSubtitleCompletionForCourse(course: course));
      }
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      final String hint = bilibiliImportSuccessHint(meta);
      final ProviderContainer container = ProviderScope.containerOf(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      // Keep downloading the rest of the 合集/分P in the background.
      if (ok && course.episodes.length > 1) {
        final LibraryCatalogNotifier catalog =
            container.read(libraryCatalogProvider.notifier);
        final BilibiliImportService downloadService = service;
        final String courseId = course.id;
        final BilibiliCollectionDownloadProgressNotifier progressNotifier =
            container.read(
              bilibiliCollectionDownloadProgressProvider.notifier,
            );
        unawaited(
          downloadRemainingBilibiliEpisodes(
            catalog: catalog,
            readCourses: () => container.read(libraryCatalogProvider),
            courseId: courseId,
            service: downloadService,
            progressNotifier: progressNotifier,
          ),
        );
      }
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok ? '已加入书库。$hint' : '导入未完成，请重试',
          ),
        ),
      );
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
        Text(
          hasCookie
              ? '粘贴分享文案后会先下载视频与官方字幕到本地，再加入书库。'
              : '粘贴分享文案后会先下载视频到本地。官方字幕需先登录 B 站（扫码即可）。',
          style: const TextStyle(color: StudyShellTokens.textSecondary),
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
          child: Text(_busy ? '下载中…' : '下载并加入书库'),
        ),
      ],
    );
  }
}
