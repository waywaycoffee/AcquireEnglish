import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';

/// Preview + merge/split/delete/edit target words for a private material course.
class MaterialCourseEditScreen extends ConsumerStatefulWidget {
  const MaterialCourseEditScreen({super.key, required this.courseId});

  final String courseId;

  @override
  ConsumerState<MaterialCourseEditScreen> createState() =>
      _MaterialCourseEditScreenState();
}

class _MaterialCourseEditScreenState
    extends ConsumerState<MaterialCourseEditScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _course;
  List<Map<String, dynamic>> _lessons = <Map<String, dynamic>>[];
  final Set<int> _selected = <int>{};

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
    final Map<String, dynamic>? detail = await ref
        .read(acquireApiClientProvider)
        .getMyFingerprintCourse(widget.courseId);
    if (!mounted) return;
    if (detail == null) {
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
      return;
    }
    final Object? lessonsRaw = detail['lessons'];
    setState(() {
      _course = detail;
      _lessons = <Map<String, dynamic>>[
        if (lessonsRaw is List)
          for (final Object? item in lessonsRaw)
            if (item is Map) Map<String, dynamic>.from(item),
      ];
      _selected.clear();
      _loading = false;
    });
  }

  Future<void> _apply(String action, {int? splitAt}) async {
    final Map<String, dynamic>? updated = await ref
        .read(acquireApiClientProvider)
        .patchMyFingerprintCourseLessons(
          courseId: widget.courseId,
          action: action,
          lessonNos: _selected.toList()..sort(),
          splitAtChar: splitAt,
        );
    if (!mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败')),
      );
      return;
    }
    final Object? lessonsRaw = updated['lessons'];
    setState(() {
      _course = updated;
      _lessons = <Map<String, dynamic>>[
        if (lessonsRaw is List)
          for (final Object? item in lessonsRaw)
            if (item is Map) Map<String, dynamic>.from(item),
      ];
      _selected.clear();
    });
  }

  Future<void> _editVocab(Map<String, dynamic> lesson) async {
    final int no = (lesson['lesson_no'] as num?)?.toInt() ?? 0;
    final List<dynamic> raw = lesson['target_words'] is List
        ? List<dynamic>.from(lesson['target_words'] as List)
        : <dynamic>[];
    final TextEditingController ctrl = TextEditingController(
      text: raw
          .map((dynamic e) {
            if (e is Map) return '${e['word'] ?? ''}';
            return '$e';
          })
          .where((String s) => s.trim().isNotEmpty)
          .join(', '),
    );
    final String? next = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('编辑第 $no 课目标词'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: '用逗号分隔，3–8 个词',
            ),
            maxLines: 3,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (next == null) return;
    final List<Map<String, dynamic>> words = next
        .split(RegExp(r'[,，\s]+'))
        .map((String s) => s.trim().toLowerCase())
        .where((String s) => s.length >= 2)
        .take(8)
        .map((String w) => <String, dynamic>{'word': w})
        .toList();
    if (words.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少保留 3 个目标词')),
      );
      return;
    }
    final Map<String, dynamic>? updated = await ref
        .read(acquireApiClientProvider)
        .patchMyFingerprintCourseLessons(
          courseId: widget.courseId,
          action: 'edit',
          lessonNos: <int>[no],
          lesson: <String, dynamic>{'target_words': words},
        );
    if (updated != null) {
      await _reload();
    }
  }

  Future<void> _finalize() async {
    final Map<String, dynamic>? done = await ref
        .read(acquireApiClientProvider)
        .finalizeMyFingerprintCourse(courseId: widget.courseId);
    if (!mounted) return;
    if (done == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('确认失败')),
      );
      return;
    }
    setState(() => _course = done);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存到我的教材课（私人）')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title = '${_course?['asset_title'] ?? '教材课'}';
    final String status = '${_course?['status'] ?? ''}';
    return PadScaffold(
      currentDestination: AppNavDestination.reading,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: title,
        description: '切课预览 · $status · 私人',
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          TextButton(
            onPressed: _loading ? null : () => unawaited(_finalize()),
            child: const Text('确认入库'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: _selected.length >= 2
                                ? () => unawaited(_apply('merge'))
                                : null,
                            child: const Text('合并所选'),
                          ),
                          OutlinedButton(
                            onPressed: _selected.length == 1
                                ? () => unawaited(_apply('split'))
                                : null,
                            child: const Text('拆分所选'),
                          ),
                          OutlinedButton(
                            onPressed: _selected.isNotEmpty
                                ? () => unawaited(_apply('delete'))
                                : null,
                            child: const Text('删除所选'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _lessons.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> lesson = _lessons[index];
                          final int no =
                              (lesson['lesson_no'] as num?)?.toInt() ??
                                  (index + 1);
                          final String lessonTitle =
                              '${lesson['title'] ?? 'Lesson $no'}';
                          final String cefr = '${lesson['cefr'] ?? ''}';
                          final String goal = '${lesson['goal'] ?? ''}';
                          final Object? tw = lesson['target_words'];
                          final String words = tw is List
                              ? tw
                                  .map((dynamic e) {
                                    if (e is Map) return '${e['word'] ?? ''}';
                                    return '$e';
                                  })
                                  .where((String s) => s.isNotEmpty)
                                  .join(', ')
                              : '';
                          final String body =
                              '${lesson['text_content'] ?? ''}'.trim();
                          final bool checked = _selected.contains(no);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ExpansionTile(
                              leading: Checkbox(
                                value: checked,
                                onChanged: (bool? v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(no);
                                    } else {
                                      _selected.remove(no);
                                    }
                                  });
                                },
                              ),
                              title: Text('$no. $lessonTitle'),
                              subtitle: Text(
                                [
                                  if (cefr.isNotEmpty) cefr,
                                  if (words.isNotEmpty) '词: $words',
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              children: <Widget>[
                                if (goal.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      8,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('目标：$goal'),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      body.length > 600
                                          ? '${body.substring(0, 600)}…'
                                          : body,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        unawaited(_editVocab(lesson)),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('改目标词'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
