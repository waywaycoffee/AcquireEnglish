import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../domain/exam_pack.dart';

const String _kImportedClozeKey = 'exam_imported_cloze_v1';

/// P2: paste a cloze passage + blank MCQs (simple local store).
class ExamClozeImportScreen extends ConsumerStatefulWidget {
  const ExamClozeImportScreen({super.key});

  @override
  ConsumerState<ExamClozeImportScreen> createState() =>
      _ExamClozeImportScreenState();
}

class _ExamClozeImportScreenState extends ConsumerState<ExamClozeImportScreen> {
  final TextEditingController _title = TextEditingController(text: '导入完形');
  final TextEditingController _passage = TextEditingController();
  final TextEditingController _q = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _passage.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String passage = _passage.text.trim();
    if (passage.length < 40) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请粘贴更完整的带空格短文')),
      );
      return;
    }
    // Minimal: one blank demo from pasted options lines "1. ...\nA. .."
    final List<ExamMcq> qs = <ExamMcq>[];
    final RegExp blank = RegExp(
      r'(\d+)[\.\)、]\s*(.+?)\n\s*A[\.\)]\s*(.+?)\n\s*B[\.\)]\s*(.+?)\n\s*C[\.\)]\s*(.+?)\n\s*D[\.\)]\s*(.+?)(?:\n|$)',
      multiLine: true,
      dotAll: true,
    );
    for (final Match m in blank.allMatches(_q.text)) {
      final List<String> opts = <String>[
        m.group(3)!.trim(),
        m.group(4)!.trim(),
        m.group(5)!.trim(),
        m.group(6)!.trim(),
      ];
      qs.add(
        ExamMcq(
          id: 'imp_c_${m.group(1)}',
          prompt: 'Blank #${m.group(1)} · ${m.group(2)!.trim()}',
          options: opts,
          answer: opts.first,
          explain: '导入题请在练习后人工核对答案',
        ),
      );
    }
    if (qs.isEmpty) {
      qs.add(
        ExamMcq(
          id: 'imp_c_1',
          prompt: 'Blank #1',
          options: const <String>['option A', 'option B', 'option C', 'option D'],
          answer: 'option A',
          explain: '请在题目区按 1.题干 / A.B.C.D 格式粘贴以自动识别',
        ),
      );
    }
    if (!Hive.isBoxOpen('prefs')) return;
    final String key = studyStorageKey(
      _kImportedClozeKey,
      ref.read(studyAccountProvider),
    );
    await Hive.box<String>('prefs').put(
          key,
          '${_title.text}\n---\n$passage\n---\n${qs.length}',
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存本地完形草稿（${qs.length} 空），请用技巧模式练习官方包或稍后扩展播放')),
    );
    context.push('/exam/cloze?tips=1');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入完形')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passage,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: '短文（空格用 ____）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: '题目（1.题干 + A/B/C/D）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存并去完形练习')),
        ],
      ),
    );
  }
}
