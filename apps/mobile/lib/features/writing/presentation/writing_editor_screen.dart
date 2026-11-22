import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../community/presentation/community_provider.dart';
import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/memory_item.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../exam/presentation/exam_profile_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/writing_draft_store.dart';
import '../domain/writing_models.dart';
import '../domain/writing_tracks.dart';

class WritingEditorScreen extends ConsumerStatefulWidget {
  const WritingEditorScreen({
    super.key,
    required this.essayId,
    this.initialPrompt,
    this.initialRubric,
    this.initialTitle,
    this.initialTrack,
  });

  final String essayId;
  final String? initialPrompt;
  final String? initialRubric;
  final String? initialTitle;
  final String? initialTrack;

  @override
  ConsumerState<WritingEditorScreen> createState() =>
      _WritingEditorScreenState();
}

class _WritingEditorScreenState extends ConsumerState<WritingEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late final TextEditingController _body;
  late String _rubric;
  WritingGradeResult? _grade;
  bool _busy = false;
  Timer? _autosave;

  @override
  void initState() {
    super.initState();
    final WritingDraft? existing =
        ref.read(writingDraftsProvider.notifier).byId(widget.essayId);
    _title = TextEditingController(
      text: existing?.title.isNotEmpty == true
          ? existing!.title
          : (widget.initialTitle ?? '我的作文'),
    );
    _prompt = TextEditingController(
      text: existing?.prompt.isNotEmpty == true
          ? existing!.prompt
          : (widget.initialPrompt ?? ''),
    );
    _body = TextEditingController(text: existing?.body ?? '');
    final WritingTrackId? track = writingTrackFromRaw(widget.initialTrack);
    _rubric = resolveWritingRubric(
      requested: widget.initialRubric ?? 'generic',
      track: track,
    );
    _title.addListener(_scheduleSave);
    _prompt.addListener(_scheduleSave);
    _body.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _title.dispose();
    _prompt.dispose();
    _body.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 600), () {
      unawaited(_save());
    });
    setState(() {});
  }

  Future<void> _save() async {
    final WritingDraft draft = WritingDraft(
      id: widget.essayId,
      title: _title.text.trim(),
      prompt: _prompt.text.trim(),
      body: _body.text,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(writingDraftsProvider.notifier).upsert(draft);
  }

  Future<void> _gradeEssay() async {
    if (_busy || _body.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await _save();
    final String familyId = ref.read(examProfileProvider).familyId ?? '';
    final WritingTrackId? track = writingTrackFromRaw(widget.initialTrack);
    final String rubric = resolveWritingRubric(
      requested: _rubric,
      familyId: familyId,
      track: track,
    );
    WritingGradeResult result;
    try {
      result = await ref.read(acquireApiClientProvider).gradeWriting(
            text: _body.text.trim(),
            prompt: _prompt.text.trim(),
            title: _title.text.trim(),
            rubric: rubric,
            familyId: familyId,
          );
    } catch (_) {
      result = gradeWritingLocally(
        _body.text,
        prompt: _prompt.text,
      );
    }
    if (!mounted) return;
    setState(() {
      _grade = result;
      _busy = false;
    });
  }

  Future<void> _addIssueToFsrs(WritingIssue issue) async {
    final String familyId = ref.read(examProfileProvider).familyId ?? '';
    final String answer =
        issue.rewrite.isNotEmpty ? issue.rewrite : issue.suggestion;
    await ref.read(dailyReviewProvider.notifier).ingestMemoryItem(
          MemoryItem(
            key:
                'writing:${widget.essayId}:${issue.excerpt.hashCode}:${issue.type}',
            kind: ReviewKind.sentence,
            question: issue.excerpt.isEmpty ? issue.suggestion : issue.excerpt,
            answer: answer,
            english: answer,
            chinese: issue.suggestion,
            sourceLabel: familyId.isEmpty ? 'writing' : 'exam:$familyId',
            origin: 'writing',
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入 FSRS')),
      );
    }
  }

  Future<void> _shareCommunity() async {
    await _save();
    try {
      await ref.read(communityFeedProvider.notifier).createPost(
            kind: 'learning_result',
            title: _title.text.trim().isEmpty ? '作文练习' : _title.text.trim(),
            body: _body.text.trim().length > 500
                ? '${_body.text.trim().substring(0, 500)}…'
                : _body.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已分享到社区练习')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败：$e')),
        );
      }
    }
  }

  String get _trackLabel {
    switch (_rubric) {
      case 'zhongkao':
        return '中考轨';
      case 'gaokao':
        return '高考应用文';
      case 'gaokao_continuation':
        return '高考读后续写';
      case 'ielts_task2':
        return '雅思 Task 2';
      case 'ielts_task1':
        return '雅思 Task 1';
      default:
        return _rubric;
    }
  }

  int get _targetWords {
    switch (_rubric) {
      case 'zhongkao':
        return 80;
      case 'gaokao':
        return 100;
      case 'gaokao_continuation':
        return 150;
      case 'ielts_task1':
        return 150;
      case 'ielts_task2':
        return 250;
      default:
        return 100;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int words = RegExp(r"[A-Za-z']+").allMatches(_body.text).length +
        RegExp(r'[\u4e00-\u9fff]').allMatches(_body.text).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('写作编辑'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : () => unawaited(_shareCommunity()),
            child: const Text('分享'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: Text('$_trackLabel · 目标约 $_targetWords 词')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _prompt,
            decoration: const InputDecoration(
              labelText: '题目（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            minLines: 12,
            maxLines: 24,
            decoration: const InputDecoration(
              labelText: '正文',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$words / ~$_targetWords 词 · 自动保存',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: words < _targetWords * 0.8
                  ? Colors.orange.shade800
                  : AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => unawaited(_gradeEssay()),
            icon: const Icon(Icons.rate_review_outlined),
            label: Text(_busy ? '批改中…' : '开始批改'),
          ),
          if (_grade != null) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              '批改结果（${_grade!.source} · ${_grade!.rubric}）',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _grade!.summary,
              style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
            ),
            if (_grade!.scores.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _grade!.scores.entries
                    .map((MapEntry<String, dynamic> e) => '${e.key}: ${e.value}')
                    .join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 12),
            for (final WritingIssue issue in _grade!.issues) ...<Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        issue.type,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (issue.excerpt.isNotEmpty) Text(issue.excerpt),
                      Text(issue.suggestion),
                      if (issue.rewrite.isNotEmpty)
                        Text(
                          '改写：${issue.rewrite}',
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => unawaited(_addIssueToFsrs(issue)),
                          child: const Text('加入 FSRS'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_grade!.rewriteFull.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                '全文改写建议',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(_grade!.rewriteFull),
            ],
            TextButton(
              onPressed: () => context.push('/exam'),
              child: const Text('返回考试备考'),
            ),
          ],
        ],
      ),
    );
  }
}
