import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../reading/data/reading_pdf_import.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/exam_reading_paper_parser.dart';
import '../data/exam_reading_paper_store.dart';
import '../domain/exam_reading_paper.dart';
import '../domain/exam_reading_strategy.dart';

class ExamReadingImportScreen extends ConsumerStatefulWidget {
  const ExamReadingImportScreen({this.editId, super.key});

  final String? editId;

  @override
  ConsumerState<ExamReadingImportScreen> createState() =>
      _ExamReadingImportScreenState();
}

class _ExamReadingImportScreenState
    extends ConsumerState<ExamReadingImportScreen> {
  final TextEditingController _title = TextEditingController(text: '导入试卷');
  final TextEditingController _raw = TextEditingController();
  final TextEditingController _passage = TextEditingController();
  ExamRcPaper? _draft;
  bool _busy = false;
  String? _error;
  bool _review = false;

  @override
  void initState() {
    super.initState();
    final String? editId = widget.editId;
    if (editId != null && editId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ExamRcPaper? p =
            ref.read(examReadingPaperProvider.notifier).byId(editId);
        if (p == null) return;
        setState(() {
          _draft = p;
          _title.text = p.title;
          _passage.text = p.passage;
          _review = true;
        });
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _raw.dispose();
    _passage.dispose();
    super.dispose();
  }

  Future<void> _parse({required bool useAi}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String text = _raw.text.trim().isNotEmpty
          ? _raw.text.trim()
          : _passage.text.trim();
      if (text.length < 40) {
        setState(() => _error = '请粘贴或导入更完整的试卷文本');
        return;
      }
      ExamRcPaper? paper;
      if (useAi && ref.read(authSessionProvider).isLoggedIn) {
        try {
          final Map<String, dynamic> raw = await ref
              .read(acquireApiClientProvider)
              .parseExamReadingPaper(text: text, title: _title.text.trim());
          if (raw.isNotEmpty) {
            paper = ExamRcPaper.fromJson(<String, dynamic>{
              ...raw,
              'id': 'import_${DateTime.now().millisecondsSinceEpoch}',
              'source': 'import',
              'createdAtMs': DateTime.now().millisecondsSinceEpoch,
            });
          }
        } catch (_) {}
      }
      paper ??= parseExamReadingPaperText(text, title: _title.text.trim());
      if (paper == null || paper.passage.trim().isEmpty) {
        setState(() => _error = '无法解析出文章，请检查格式或改用 AI 解析（需登录）');
        return;
      }
      String? warn;
      if (paper.questions.isEmpty) {
        warn = '未识别到 ABCD 题目，请在校对页检查或重新粘贴';
      }
      setState(() {
        _draft = paper;
        _passage.text = paper!.passage;
        _title.text = paper.title;
        _review = true;
        _error = warn;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPdfOrTxt() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        const XTypeGroup(
          label: 'papers',
          extensions: <String>['pdf', 'txt', 'md'],
        ),
      ],
    );
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String name = file.name.toLowerCase();
      if (name.endsWith('.pdf')) {
        final ReadingPdfImportResult result = await importPdfForReading(
          bytes: await file.readAsBytes(),
          filename: file.name,
          api: ref.read(acquireApiClientProvider),
          isLoggedIn: ref.read(authSessionProvider).isLoggedIn,
        );
        _raw.text = result.text;
        _title.text = file.name.replaceAll(
          RegExp(r'\.pdf$', caseSensitive: false),
          '',
        );
      } else {
        _raw.text = await File(file.path).readAsString();
        _title.text = file.name;
      }
      setState(() {});
    } catch (e) {
      setState(() => _error = '读取文件失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final XFile? shot = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (shot == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Uint8List bytes = await shot.readAsBytes();
      final ReadingPdfImportResult result = await importPdfForReading(
        bytes: bytes,
        filename: '${shot.name}.pdf',
        api: ref.read(acquireApiClientProvider),
        isLoggedIn: ref.read(authSessionProvider).isLoggedIn,
        shareOcr: false,
      );
      if (result.text.trim().length < 40) {
        setState(() => _error = '图片识别文字过少，请改用 PDF/TXT 或粘贴文本后 AI 解析');
        return;
      }
      _raw.text = result.text;
      setState(() {});
    } catch (e) {
      setState(() => _error = '图片导入失败，请改用 PDF/TXT 或粘贴文本：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final ExamRcPaper? draft = _draft;
    if (draft == null) return;
    final ExamRcPaper saved = draft.copyWith(
      title: _title.text.trim().isEmpty ? draft.title : _title.text.trim(),
      passage:
          _passage.text.trim().isEmpty ? draft.passage : _passage.text.trim(),
    );
    if (saved.questions.isEmpty) {
      setState(() => _error = '至少需要 1 道含 A/B/C/D 的题目');
      return;
    }
    await ref.read(examReadingPaperProvider.notifier).upsert(saved);
    if (!mounted) return;
    context.go('/exam/reading/paper?paperId=${Uri.encodeComponent(saved.id)}');
  }

  @override
  Widget build(BuildContext context) {
    if (_review && _draft != null) {
      return _buildReview(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('导入试卷')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '试卷标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _raw,
            minLines: 12,
            maxLines: 18,
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              labelText: '粘贴试卷文本（文章 + 题干 + A/B/C/D）',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickPdfOrTxt,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF/TXT'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickPhoto,
                icon: const Icon(Icons.photo_outlined),
                label: const Text('相册'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => _parse(useAi: false),
            child: Text(_busy ? '解析中…' : '本地解析'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _parse(useAi: true),
            child: const Text('AI 解析（登录）'),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(BuildContext context) {
    final ExamRcPaper draft = _draft!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('校对试卷'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _review = false),
        ),
      ),
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
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '文章',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '题目（${draft.questions.length}）',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < draft.questions.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Q${i + 1}. ${draft.questions[i].stem}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        DropdownButton<ExamRcQuestionType>(
                          value: draft.questions[i].resolvedType ==
                                  ExamRcQuestionType.unknown
                              ? ExamRcQuestionType.detail
                              : draft.questions[i].resolvedType,
                          items: ExamRcQuestionType.values
                              .where(
                                (ExamRcQuestionType t) =>
                                    t != ExamRcQuestionType.unknown,
                              )
                              .map(
                                (ExamRcQuestionType t) =>
                                    DropdownMenuItem<ExamRcQuestionType>(
                                  value: t,
                                  child: Text(t.labelCn),
                                ),
                              )
                              .toList(),
                          onChanged: (ExamRcQuestionType? t) {
                            if (t == null) return;
                            final List<ExamRcQuestion> qs =
                                List<ExamRcQuestion>.from(draft.questions);
                            qs[i] = qs[i].copyWith(type: t);
                            setState(
                              () => _draft = draft.copyWith(questions: qs),
                            );
                          },
                        ),
                      ],
                    ),
                    for (int o = 0; o < draft.questions[i].options.length; o++)
                      RadioListTile<int>(
                        dense: true,
                        value: o,
                        groupValue: draft.questions[i].answerIndex,
                        title: Text(
                          '${'ABCD'[o]}. ${draft.questions[i].options[o]}',
                        ),
                        onChanged: (int? v) {
                          if (v == null) return;
                          final List<ExamRcQuestion> qs =
                              List<ExamRcQuestion>.from(draft.questions);
                          qs[i] = qs[i].copyWith(answer: qs[i].options[v]);
                          setState(
                            () => _draft = draft.copyWith(questions: qs),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('保存并开始练习'),
          ),
        ],
      ),
    );
  }
}
