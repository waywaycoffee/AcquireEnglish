import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/word_root_models.dart';
import '../data/word_root_catalog.dart';
import 'word_book_provider.dart';
import 'word_root_provider.dart';

/// Browse roots, reverse-look up by root text, and open word parses.
class WordRootExplorerScreen extends ConsumerStatefulWidget {
  const WordRootExplorerScreen({
    super.key,
    this.initialQuery = '',
    this.mode = WordRootExplorerMode.browse,
  });

  final String initialQuery;
  final WordRootExplorerMode mode;

  @override
  ConsumerState<WordRootExplorerScreen> createState() =>
      _WordRootExplorerScreenState();
}

enum WordRootExplorerMode { browse, word, root }

class _WordRootExplorerScreenState
    extends ConsumerState<WordRootExplorerScreen> {
  late final TextEditingController _controller;
  late WordRootExplorerMode _mode;
  String? _levelFilter;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _mode = widget.mode;
    if (widget.initialQuery.trim().isNotEmpty &&
        widget.mode == WordRootExplorerMode.browse) {
      _mode = WordRootExplorerMode.word;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSearch() {
    final String q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() => _mode = WordRootExplorerMode.browse);
      return;
    }
    setState(() {
      // Latin letters → word query; otherwise treat as root form.
      _mode = RegExp(r"^[A-Za-z']+$").hasMatch(q)
          ? WordRootExplorerMode.word
          : WordRootExplorerMode.root;
    });
  }

  Future<void> _enrollWord(String word) async {
    final bool ok = ref.read(wordBookProvider.notifier).addFavoriteWord(
          rawWord: word,
          episodeId: 'wordroot:$word',
          course: '词根词缀',
          episode: '情景记忆',
          time: '',
          lineKey: 'wordroot:$word',
          sentence: word,
          chinese: '',
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已加入《情景记忆》并进入背词计划' : '无法收藏「$word」'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<WordRootCatalog> async = ref.watch(wordRootCatalogProvider);
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.appWhite,
        foregroundColor: AppDesignTokens.textPrimary,
        title: const Text('词根词缀'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '词根库加载失败：$e',
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
          ),
        ),
        data: (WordRootCatalog catalog) => _buildBody(catalog),
      ),
    );
  }

  Widget _buildBody(WordRootCatalog catalog) {
    final String q = _controller.text.trim();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _controller,
                style: TextStyle(color: AppDesignTokens.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppDesignTokens.appWhite,
                  hintText: '查单词 transport，或查词根 port',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search_rounded),
                    onPressed: _runSearch,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('浏览词根'),
                    selected: _mode == WordRootExplorerMode.browse,
                    onSelected: (_) => setState(
                      () => _mode = WordRootExplorerMode.browse,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('查单词'),
                    selected: _mode == WordRootExplorerMode.word,
                    onSelected: (_) => setState(
                      () => _mode = WordRootExplorerMode.word,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('查词根'),
                    selected: _mode == WordRootExplorerMode.root,
                    onSelected: (_) => setState(
                      () => _mode = WordRootExplorerMode.root,
                    ),
                  ),
                  if (_mode == WordRootExplorerMode.browse ||
                      _mode == WordRootExplorerMode.root)
                    ChoiceChip(
                      label: Text(_levelFilter ?? '全部难度'),
                      selected: _levelFilter != null,
                      onSelected: (_) {
                        setState(() {
                          if (_levelFilter == null) {
                            _levelFilter = '高频';
                          } else if (_levelFilter == '高频') {
                            _levelFilter = '进阶';
                          } else {
                            _levelFilter = null;
                          }
                        });
                      },
                    ),
                ],
              ),
              Text(
                '库内 ${catalog.meta['root_count'] ?? catalog.roots.length} 词根 · '
                '${catalog.meta['word_count'] ?? catalog.words.length} 例词',
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_mode) {
            WordRootExplorerMode.browse => _browseList(catalog),
            WordRootExplorerMode.word => _wordResult(catalog, q),
            WordRootExplorerMode.root => _rootResult(catalog, q),
          },
        ),
      ],
    );
  }

  Widget _browseList(WordRootCatalog catalog) {
    final List<WordRootEntry> roots =
        catalog.topRoots(limit: 80, level: _levelFilter);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: roots.length,
      separatorBuilder: (_, __) => Divider(color: AppDesignTokens.borderGray),
      itemBuilder: (BuildContext context, int index) {
        final WordRootEntry root = roots[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            root.root,
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          subtitle: Text(
            '${root.typeCn.isNotEmpty ? root.typeCn : root.type} · '
            '${root.cn}'
            '${root.level.isEmpty ? '' : ' · ${root.level}'}'
            ' · ${root.exampleCount} 例',
            style: TextStyle(color: AppDesignTokens.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            _controller.text = root.root.replaceAll(RegExp(r'^-|-$'), '');
            setState(() => _mode = WordRootExplorerMode.root);
          },
        );
      },
    );
  }

  Widget _wordResult(WordRootCatalog catalog, String q) {
    if (q.isEmpty) {
      return _hint('输入英文单词，例如 transport / claustrophobia');
    }
    final WordRootDetail? detail = catalog.queryWordDetail(q);
    if (detail == null) {
      final List<WordRootSpellCandidate> tips = catalog.spellSuggest(q);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            '词库里没有「$q」',
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (tips.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '你是不是要找：',
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
            for (final WordRootSpellCandidate c in tips)
              ListTile(
                title: Text(c.word),
                subtitle: Text(c.gloss),
                onTap: () {
                  _controller.text = c.word;
                  setState(() {});
                },
              ),
          ],
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: <Widget>[
        Text(
          detail.word,
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 28,
          ),
        ),
        if (detail.gloss.isNotEmpty)
          Text(
            detail.gloss,
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 16,
            ),
          ),
        if (detail.parseFormula.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              detail.parseFormula,
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _enrollWord(detail.word),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('加入背词'),
          ),
        ),
        if (detail.sameRootWords.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Text(
            '同根词 ${detail.sameRootWords.length}',
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          for (final WordRootWord w in detail.sameRootWords.take(40))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                w.word,
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                <String>[
                  if (w.gloss.isNotEmpty) w.gloss,
                  if (w.level.isNotEmpty) w.level,
                ].join(' · '),
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
              trailing: IconButton(
                tooltip: '加入背词',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _enrollWord(w.word),
              ),
              onTap: () {
                _controller.text = w.word;
                setState(() => _mode = WordRootExplorerMode.word);
              },
            ),
        ],
      ],
    );
  }

  Widget _rootResult(WordRootCatalog catalog, String q) {
    if (q.isEmpty) {
      return _hint('输入词根，例如 port / chron / fid');
    }
    final List<WordRootEntry> roots = catalog.findRoots(q);
    final List<WordRootWord> words = catalog.queryRootWords(
      q,
      level: _levelFilter,
    );
    if (roots.isEmpty && words.isEmpty) {
      return _hint('没有匹配「$q」的词根');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: <Widget>[
        for (final WordRootEntry root in roots)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppDesignTokens.appWhite,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    root.root,
                    style: TextStyle(
                      color: AppDesignTokens.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    '${root.typeCn} · ${root.cn}'
                    '${root.etym.isEmpty ? '' : '\n${root.etym}'}',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Text(
          '关联单词 ${words.length}',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        for (final WordRootWord w in words)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              w.word,
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              <String>[
                if (w.gloss.isNotEmpty) w.gloss,
                if (w.level.isNotEmpty) w.level,
              ].join(' · '),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _enrollWord(w.word),
            ),
            onTap: () {
              _controller.text = w.word;
              setState(() => _mode = WordRootExplorerMode.word);
            },
          ),
      ],
    );
  }

  Widget _hint(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            style: TextStyle(color: AppDesignTokens.textSecondary),
          ),
        ),
      );
}

String wordRootExplorerRoute({String query = '', String mode = ''}) {
  final Map<String, String> params = <String, String>{};
  if (query.trim().isNotEmpty) params['q'] = query.trim();
  if (mode.trim().isNotEmpty) params['mode'] = mode.trim();
  if (params.isEmpty) return '/words/roots';
  return Uri(path: '/words/roots', queryParameters: params).toString();
}

/// Open explorer focused on one word (from detail cards).
void openWordRootExplorer(
  BuildContext context, {
  String query = '',
  WordRootExplorerMode mode = WordRootExplorerMode.word,
}) {
  context.push(
    wordRootExplorerRoute(
      query: query,
      mode: mode.name,
    ),
  );
}
