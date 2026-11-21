import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../sync/data/schedule_device_cloud_sync.dart';
import '../domain/writing_models.dart';

const String kWritingDraftsKey = 'writing_drafts_v1';

class WritingDraftStore extends Notifier<List<WritingDraft>> {
  @override
  List<WritingDraft> build() => _load();

  List<WritingDraft> _load() {
    if (!Hive.isBoxOpen('prefs')) return const <WritingDraft>[];
    final String? raw = Hive.box<String>('prefs').get(kWritingDraftsKey);
    if (raw == null || raw.isEmpty) return const <WritingDraft>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((Map e) => WritingDraft.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const <WritingDraft>[];
    }
  }

  Future<void> _persist(List<WritingDraft> next) async {
    state = List<WritingDraft>.unmodifiable(next);
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
          kWritingDraftsKey,
          jsonEncode(next.map((WritingDraft e) => e.toJson()).toList()),
        );
    scheduleDeviceCloudSync(key: 'settings');
  }

  Future<WritingDraft> upsert(WritingDraft draft) async {
    final List<WritingDraft> next = List<WritingDraft>.of(state);
    final int i = next.indexWhere((WritingDraft e) => e.id == draft.id);
    if (i >= 0) {
      next[i] = draft;
    } else {
      next.insert(0, draft);
    }
    await _persist(next.take(80).toList(growable: false));
    return draft;
  }

  Future<void> remove(String id) async {
    await _persist(
      state.where((WritingDraft e) => e.id != id).toList(growable: false),
    );
  }

  WritingDraft? byId(String id) {
    for (final WritingDraft d in state) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> replaceFromCloud(List<WritingDraft> drafts) async {
    await _persist(drafts.take(80).toList(growable: false));
  }
}

final NotifierProvider<WritingDraftStore, List<WritingDraft>>
    writingDraftsProvider =
    NotifierProvider<WritingDraftStore, List<WritingDraft>>(
  WritingDraftStore.new,
);

/// Offline / fallback structured feedback when API LLM is unavailable.
WritingGradeResult gradeWritingLocally(String text, {String prompt = ''}) {
  final String body = text.trim();
  final List<WritingIssue> issues = <WritingIssue>[];
  if (body.length < 40) {
    issues.add(
      const WritingIssue(
        type: 'structure',
        excerpt: '',
        suggestion: '篇幅偏短，试着补充观点、例子与结尾。',
      ),
    );
  }
  final RegExp iAm = RegExp(r'\bi\b');
  if (iAm.hasMatch(body) && !RegExp(r'\bI\b').hasMatch(body)) {
    issues.add(
      const WritingIssue(
        type: 'grammar',
        excerpt: 'i',
        suggestion: '英语句首与人称代词 I 需大写。',
        rewrite: 'I',
      ),
    );
  }
  if (RegExp(r'\s{2,}').hasMatch(body)) {
    issues.add(
      const WritingIssue(
        type: 'clarity',
        excerpt: '多余空格',
        suggestion: '去掉多余空格，保持排版干净。',
      ),
    );
  }
  if (!RegExp(r'[.!?。！？]').hasMatch(body)) {
    issues.add(
      const WritingIssue(
        type: 'structure',
        excerpt: '',
        suggestion: '句子缺少句号等标点，请分段并正确收尾。',
      ),
    );
  }
  if (issues.isEmpty) {
    issues.add(
      const WritingIssue(
        type: 'clarity',
        excerpt: '',
        suggestion: '整体可读。可再检查连接词与段落主题句是否清晰。',
      ),
    );
  }
  return WritingGradeResult(
    summary: prompt.trim().isEmpty
        ? '已完成通用英语写作检查（本地规则）。联网后可获得更细的改写建议。'
        : '已对照题目完成通用检查（本地规则）。',
    issues: issues,
    rewriteFull: '',
    source: 'local',
  );
}
