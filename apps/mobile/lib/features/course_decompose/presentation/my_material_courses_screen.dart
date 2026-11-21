import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../reading/data/reading_fingerprint.dart';
import '../../reading/data/reading_ingest.dart';
import '../../reading/data/reading_pdf_import.dart';
import '../../reading/domain/reading_doc.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import 'material_course_edit_screen.dart';

/// 「我的教材课」— private fingerprint UserCourseAsset list + upload entry.
class MyMaterialCoursesScreen extends ConsumerStatefulWidget {
  const MyMaterialCoursesScreen({super.key});

  @override
  ConsumerState<MyMaterialCoursesScreen> createState() =>
      _MyMaterialCoursesScreenState();
}

class _MyMaterialCoursesScreenState
    extends ConsumerState<MyMaterialCoursesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '请先登录后查看私人教材课';
        _items = <Map<String, dynamic>>[];
      });
      return;
    }
    final List<Map<String, dynamic>> items =
        await ref.read(acquireApiClientProvider).listMyFingerprintCourses();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _uploadPrivate() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final bool? ack = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('版权声明'),
          content: const Text(
            '请确认：上传素材仅供个人学习，或你已获得相应授权。'
            '平台不会自动公开发布；社区分享为后续版本能力。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('我已确认'),
            ),
          ],
        );
      },
    );
    if (ack != true || !mounted) return;

    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'material',
          extensions: <String>['pdf', 'epub', 'txt', 'md'],
        ),
      ],
      confirmButtonText: '上传教材',
    );
    if (file == null || !mounted) return;

    final ValueNotifier<String> progress = ValueNotifier<String>('正在解析…');
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              content: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (_, String message, __) {
                  return Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Text(message)),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );

    try {
      final Uint8List bytes = await file.readAsBytes();
      final String lower = file.name.toLowerCase();
      final String text;
      if (lower.endsWith('.pdf')) {
        final ReadingPdfImportResult pdf = await importPdfForReading(
          bytes: bytes,
          filename: file.name,
          api: ref.read(acquireApiClientProvider),
          isLoggedIn: true,
          shareOcr: false,
          onProgress: (int page, int total, String message) {
            progress.value = message;
          },
        );
        text = pdf.text;
      } else {
        text = await parseReadingImport(bytes, filename: file.name);
      }
      if (text.trim().length < 80) {
        throw StateError('正文过短，无法解构');
      }

      progress.value = '正在提交私人解构…';
      final String sourceType = lower.endsWith('.epub') ? 'epub' : 'pdf_text';
      final FingerprintCacheSearchResult? fp = await ref
          .read(acquireApiClientProvider)
          .searchFingerprintCache(
            cleanedText: text,
            sourceType: sourceType,
            fileName: file.name,
            fileType: lower.contains('.') ? lower.split('.').last : 'pdf',
            privateOnly: true,
            licenseAck: true,
          );
      if (fp == null) {
        throw StateError('提交失败，请稍后重试');
      }

      String? courseId = fp.userCourseAssetId;
      if (!fp.hit && fp.uploadTaskId.isNotEmpty) {
        progress.value = '私人解构排队中…';
        final FingerprintUploadTaskStatus? status = await ref
            .read(acquireApiClientProvider)
            .pollFingerprintUploadTask(
              fp.uploadTaskId,
              timeout: const Duration(seconds: 120),
            );
        if (status == null || !status.isReady) {
          throw StateError(
            status?.failReason.isNotEmpty == true
                ? status!.failReason
                : '解构超时或失败',
          );
        }
        courseId = status.userCourseAssetId;
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _reload();
      if (courseId != null && courseId.isNotEmpty && mounted) {
        await context.push('/material-courses/${Uri.encodeComponent(courseId)}');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(fp.message.isNotEmpty ? fp.message : '已处理')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败：$e')),
        );
      }
    } finally {
      progress.dispose();
    }
  }

  Future<void> _openInReading(Map<String, dynamic> course) async {
    final String id = '${course['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    final Map<String, dynamic>? detail =
        await ref.read(acquireApiClientProvider).getMyFingerprintCourse(id);
    if (detail == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法加载课程详情')),
      );
      return;
    }
    final Object? lessonsRaw = detail['lessons'];
    final List<Map<String, dynamic>> lessons = <Map<String, dynamic>>[
      if (lessonsRaw is List)
        for (final Object? item in lessonsRaw)
          if (item is Map) Map<String, dynamic>.from(item),
    ];
    final FingerprintCacheSearchResult fake = FingerprintCacheSearchResult(
      hit: true,
      message: '私人教材课',
      userCourseAssetId: id,
      assetName: '${detail['asset_title'] ?? ''}',
      asset: <String, dynamic>{
        'cefr_level': detail['cefr_level'] ?? '',
        'asset_name': detail['asset_title'] ?? '',
      },
      lessons: lessons,
    );
    final List<ReadingDoc> docs = readingDocsFromFingerprintAsset(
      result: fake,
      fallbackText: '',
      fileName: '${detail['asset_title'] ?? 'course'}.txt',
    );
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('课程暂无正文')),
      );
      return;
    }
    final List<ReadingDoc> saved =
        await ref.read(readingLibraryProvider.notifier).addDocs(docs);
    if (!mounted) return;
    final ReadingDoc open = saved.isNotEmpty ? saved.first : docs.first;
    unawaited(context.push('/reading/${Uri.encodeComponent(open.id)}'));
  }

  @override
  Widget build(BuildContext context) {
    return PadScaffold(
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '我的教材课',
        description: '私人解构 · 不自动发布',
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => unawaited(_reload()),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '上传教材',
            onPressed: () => unawaited(_uploadPrivate()),
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: () => unawaited(_uploadPrivate()),
                        icon: const Icon(Icons.auto_stories_outlined),
                        label: const Text('上传 EPUB / PDF 并智能切课'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '默认仅私人课库。命中公共缓存时可复用结构；未命中不会写入公共指纹池。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(child: Text('还没有教材课，先上传一本吧')),
                        ),
                      for (final Map<String, dynamic> item in _items)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(
                              '${item['asset_title'] ?? '未命名教材'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (item['private_only'] == true) '私人',
                                '${item['status'] ?? ''}',
                                if (item['cefr_level'] != null)
                                  '${item['cefr_level']}',
                                if (item['lesson_count'] != null)
                                  '${item['lesson_count']} 课',
                              ].where((String s) => s.trim().isNotEmpty).join(' · '),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (String value) {
                                final String id = '${item['id'] ?? ''}';
                                if (value == 'edit') {
                                  unawaited(
                                    context.push(
                                      '/material-courses/${Uri.encodeComponent(id)}',
                                    ),
                                  );
                                } else if (value == 'read') {
                                  unawaited(_openInReading(item));
                                }
                              },
                              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('预览 / 编辑切课'),
                                ),
                                PopupMenuItem<String>(
                                  value: 'read',
                                  child: Text('加入书架阅读'),
                                ),
                              ],
                            ),
                            onTap: () => unawaited(
                              context.push(
                                '/material-courses/${Uri.encodeComponent('${item['id'] ?? ''}')}',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
