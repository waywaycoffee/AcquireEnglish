import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../exam/domain/exam_profile.dart';
import '../../exam/domain/exam_registry.dart';
import '../../exam/presentation/exam_profile_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/hub_ui.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/community_models.dart';

class ExamAssetsTab extends ConsumerStatefulWidget {
  const ExamAssetsTab({super.key});

  @override
  ConsumerState<ExamAssetsTab> createState() => _ExamAssetsTabState();
}

class _ExamAssetsTabState extends ConsumerState<ExamAssetsTab> {
  List<ExamAssetDto> _items = const <ExamAssetDto>[];
  bool _loading = true;
  String? _error;
  String? _filterFamily;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ExamProfile profile = ref.read(examProfileProvider);
      _filterFamily = profile.familyId;
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<ExamAssetDto> items = await ref
          .read(acquireApiClientProvider)
          .listExamAssets(familyId: _filterFamily);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _upload() async {
    final ExamProfile profile = ref.read(examProfileProvider);
    String familyId = _filterFamily ?? profile.familyId ?? '';
    if (familyId.isEmpty) {
      familyId = await _pickFamily() ?? '';
      if (familyId.isEmpty) return;
    }
    final String? kind = await _pickKind();
    if (kind == null || !mounted) return;

    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'exam',
          extensions: <String>[
            'mp3',
            'm4a',
            'wav',
            'mp4',
            'webm',
            'txt',
            'srt',
            'vtt',
            'json',
            'csv',
            'md',
            'pdf',
          ],
        ),
      ],
    );
    if (file == null || !mounted) return;

    final TextEditingController title = TextEditingController(
      text: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
    );
    final bool? ack = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('上传考试资料'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 12),
            const Text(
              '上传即确认：仅供个人学习，或已获权利人授权 / 合理使用。违规内容可被举报下架。',
              style: TextStyle(height: 1.4),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认上传'),
          ),
        ],
      ),
    );
    if (ack != true || !mounted) return;

    final List<int> bytes = await file.readAsBytes();
    try {
      await ref.read(acquireApiClientProvider).uploadExamAsset(
            bytes: bytes,
            filename: file.name,
            familyId: familyId,
            title: title.text.trim().isEmpty ? file.name : title.text.trim(),
            kind: kind,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已上传到云端，其他同学可下载')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$e')),
      );
    } finally {
      title.dispose();
    }
  }

  Future<String?> _pickFamily() async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: ListView(
            children: <Widget>[
              const ListTile(title: Text('选择考试族')),
              for (final ExamFamily f in kExamFamilies)
                ListTile(
                  title: Text(f.label),
                  onTap: () => Navigator.pop(context, f.id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pickKind() async {
    const List<(String, String)> kinds = <(String, String)>[
      ('audio', '听力音频'),
      ('transcript', '字幕 / 脚本'),
      ('answers', '解析与答案'),
      ('vocab', '词表'),
      ('notes', '笔记'),
      ('writing', '写作范文'),
      ('speaking', '口语素材'),
      ('other', '其他'),
    ];
    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (String id, String label) in kinds)
              ListTile(
                title: Text(label),
                onTap: () => Navigator.pop(context, id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDownload(ExamAssetDto item) async {
    final Uri? uri = Uri.tryParse(item.downloadUrl);
    if (uri == null) return;
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开：${item.downloadUrl}')),
      );
    }
  }

  Future<void> _report(ExamAssetDto item) async {
    final TextEditingController reason = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('举报资料'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: '原因'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (ok != true || reason.text.trim().length < 2) {
      reason.dispose();
      return;
    }
    try {
      await ref
          .read(acquireApiClientProvider)
          .reportExamAsset(item.id, reason: reason.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已提交举报')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('举报失败：$e')),
        );
      }
    } finally {
      reason.dispose();
    }
  }

  String _familyLabel(String id) =>
      examFamilyById(id)?.label ?? id;

  String _kindLabel(String kind) {
    switch (kind) {
      case 'audio':
        return '听力';
      case 'transcript':
        return '脚本';
      case 'answers':
        return '解析';
      case 'vocab':
        return '词表';
      case 'notes':
        return '笔记';
      case 'writing':
        return '写作';
      case 'speaking':
        return '口语';
      default:
        return '资料';
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          HubSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '考试真题资料库',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '上传听力、脚本、解析与词表到云端（ECS exam 命名空间），其他同学可下载学习。',
                  style: TextStyle(
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _upload,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('上传资料'),
                    ),
                    OutlinedButton(
                      onPressed: () => context.push('/exam'),
                      child: const Text('考试备考'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final String? id = await _pickFamily();
                        if (id == null) return;
                        setState(() => _filterFamily = id);
                        await _refresh();
                      },
                      child: Text(
                        _filterFamily == null
                            ? '筛选考试族'
                            : '筛选 · ${_familyLabel(_filterFamily!)}',
                      ),
                    ),
                    if (_filterFamily != null)
                      TextButton(
                        onPressed: () async {
                          setState(() => _filterFamily = null);
                          await _refresh();
                        },
                        child: const Text('清除筛选'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            HubSurface(
              child: Text(
                '加载失败：$_error',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else if (_items.isEmpty)
            HubSurface(
              child: Text(
                '还没有资料。成为第一个上传者，帮助同考试族的同学。',
                style: TextStyle(
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            )
          else
            for (final ExamAssetDto item in _items) ...<Widget>[
              HubSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_familyLabel(item.familyId)} · ${_kindLabel(item.kind)}'
                      ' · ${item.uploaderName}'
                      ' · ${(item.sizeBytes / 1024).toStringAsFixed(0)} KB',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        FilledButton.tonal(
                          onPressed: () => unawaited(_openDownload(item)),
                          child: const Text('下载'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => unawaited(_report(item)),
                          child: const Text('举报'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}
