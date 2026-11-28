import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../constants/assets.dart';
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
              backgroundColor: AppDesignTokens.navAccent,
              foregroundColor: AppDesignTokens.onAccent,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '我的词书',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
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
                coverAsset: Assets.wordBookSceneMemory,
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
                coverAsset: Assets.wordBookCurrent,
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
    required this.coverAsset,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final String title;
  final String subtitle;
  final String coverAsset;
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
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppDesignTokens.toyCardShadow,
                    border: Border.all(
                      color: AppDesignTokens.borderGray.withValues(alpha: 0.45),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      coverAsset,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      filterQuality: FilterQuality.medium,
                      semanticLabel: title,
                      errorBuilder:
                          (BuildContext context, Object error, StackTrace? st) {
                        return ColoredBox(
                          color: AppDesignTokens.appWhite,
                          child: Center(
                            child: Icon(
                              Icons.menu_book_rounded,
                              color: AppDesignTokens.textSecondary,
                              size: 28,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
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
