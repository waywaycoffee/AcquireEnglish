import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../daily_review/presentation/syllabus_overlap_dialog.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../words/domain/syllabus_book.dart';
import '../../../words/presentation/syllabus_book_browse_screen.dart';
import '../../../words/presentation/syllabus_books_provider.dart';

/// English-level vocab modules: two book covers outside「今日学习」.
class LevelVocabBookModules extends ConsumerWidget {
  const LevelVocabBookModules({super.key});

  Future<void> _startVocabulary(BuildContext context, WidgetRef ref) async {
    SyllabusBooksState books = ref.read(syllabusBooksProvider);
    SyllabusBook? book = books.activeBook;
    if (book == null || books.isComplete(book)) {
      final String? selected = await context.push<String>(
        '/words/syllabus?selectForStudy=1',
      );
      if (selected == null || !context.mounted) return;
      books = ref.read(syllabusBooksProvider);
      book = books.activeBook;
    }
    if (book != null) await startSyllabusBookSession(ref, context, book);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyllabusBooksState books = ref.watch(syllabusBooksProvider);
    final SyllabusBook? scene = books.bookById(kSceneMemoryBookId);
    final SyllabusBook? active = books.activeBook;
    final int sceneCount = scene?.wordCount ?? 0;
    final int activeCount = active?.wordCount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('home-start-vocabulary'),
            onPressed: books.ready
                ? () => _startVocabulary(context, ref)
                : null,
            icon: const Icon(Icons.school_outlined),
            label: const Text('开始背单词'),
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignTokens.brandGreen,
              foregroundColor: AppDesignTokens.onAccent,
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '我的词书',
          style: TextStyle(
            color: AppDesignTokens.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _BookModule(
                key: const Key('home-scene-memory-book'),
                title: kSceneMemoryBookTitle,
                subtitle: sceneCount == 0
                    ? '0 个单词 · 收藏词会出现在这里'
                    : '$sceneCount 个单词',
                spineColor: const Color(0xFF3D8B7A),
                coverColor: AppDesignTokens.isDark
                    ? const Color(0xFF1F3A34)
                    : const Color(0xFFD8EFE8),
                onTap: () {
                  if (scene == null) {
                    context.push('/words?favorites=1');
                    return;
                  }
                  context.push(syllabusBookBrowseRoute(kSceneMemoryBookId));
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _BookModule(
                key: const Key('home-active-vocabulary-book'),
                title: '当前词书',
                subtitle: active == null
                    ? (books.ready ? '尚未选择 · 0 个单词' : '正在读取词书…')
                    : '${active.title} · $activeCount 个单词',
                spineColor: const Color(0xFF6B5B95),
                coverColor: AppDesignTokens.isDark
                    ? const Color(0xFF2A2438)
                    : const Color(0xFFE8E0F5),
                onTap: () {
                  if (active == null) {
                    context.push('/words/syllabus?selectForStudy=1');
                    return;
                  }
                  context.push(syllabusBookBrowseRoute(active.id));
                },
                onLongPress: () =>
                    context.push('/words/syllabus?selectForStudy=1'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BookModule extends StatelessWidget {
  const _BookModule({
    required this.title,
    required this.subtitle,
    required this.spineColor,
    required this.coverColor,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final String title;
  final String subtitle;
  final Color spineColor;
  final Color coverColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: <Widget>[
              AspectRatio(
                aspectRatio: 3 / 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: coverColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: AppDesignTokens.toyCardShadow,
                    border: Border.all(
                      color: AppDesignTokens.borderGray.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Container(
                        width: 10,
                        decoration: BoxDecoration(
                          color: spineColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            bottomLeft: Radius.circular(10),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                Icons.menu_book_rounded,
                                color: spineColor,
                                size: 22,
                              ),
                              const Spacer(),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppDesignTokens.textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
