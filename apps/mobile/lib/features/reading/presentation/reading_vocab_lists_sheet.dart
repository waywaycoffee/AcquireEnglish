import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/reading_vocab_lists.dart';

Future<void> showReadingVocabListsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) {
      return const _ReadingVocabListsSheet();
    },
  );
}

class _ReadingVocabListsSheet extends ConsumerStatefulWidget {
  const _ReadingVocabListsSheet();

  @override
  ConsumerState<_ReadingVocabListsSheet> createState() =>
      _ReadingVocabListsSheetState();
}

class _ReadingVocabListsSheetState
    extends ConsumerState<_ReadingVocabListsSheet> {
  final TextEditingController _input = TextEditingController();
  int _tab = 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _addCurrent() async {
    final String word = normalizeWord(_input.text);
    if (word.length < 2) return;
    if (_tab == 0) {
      await ref.read(readingVocabListsProvider.notifier).markKnown(word);
    } else {
      await ref.read(readingVocabListsProvider.notifier).markFocus(word);
    }
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ReadingVocabLists lists = ref.watch(readingVocabListsProvider);
    final List<String> words = (_tab == 0 ? lists.known : lists.focus).toList()
      ..sort();
    final double bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '词汇黑白名单',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 4),
              const Text(
                '白名单=已会（不计入生词）；黑名单=强制生词（即使很常见）。'
                'i+1 还会合并你已复习过的词。',
                style: TextStyle(fontSize: 13, color: Color(0xFF626262)),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('白名单 ${lists.knownCount}'),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('黑名单 ${lists.focusCount}'),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                  ),
                ],
                selected: <int>{_tab},
                onSelectionChanged: (Set<int> next) {
                  setState(() => _tab = next.first);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: InputDecoration(
                        hintText: _tab == 0 ? '加入已会单词' : '加入强制生词',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addCurrent(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _addCurrent,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppDesignTokens.brandGreenDark,
                    ),
                    child: const Text('添加'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: words.isEmpty
                    ? Center(
                        child: Text(
                          _tab == 0 ? '白名单为空' : '黑名单为空',
                          style: const TextStyle(color: Color(0xFF8A8A8A)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: words.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final String w = words[index];
                          return ListTile(
                            dense: true,
                            title: Text(w),
                            trailing: IconButton(
                              tooltip: '移除',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                if (_tab == 0) {
                                  unawaited(
                                    ref
                                        .read(readingVocabListsProvider.notifier)
                                        .removeKnown(w),
                                  );
                                } else {
                                  unawaited(
                                    ref
                                        .read(readingVocabListsProvider.notifier)
                                        .removeFocus(w),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
