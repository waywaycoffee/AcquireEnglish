import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../community/data/english_browse_actions.dart';
import '../../reading/data/reading_iplus1.dart';
import '../../reading/domain/reading_doc.dart';
import '../../reading/presentation/reading_iplus1_provider.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../../words/presentation/syllabus_books_provider.dart';

/// Prompt to pick a syllabus book when 今日学习 needs vocab but none is active.
Future<bool> ensureTodayVocabBook(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(syllabusBooksProvider).activeBook != null) return true;
  if (!context.mounted) return false;
  final bool? go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppDesignTokens.appWhite,
    showDragHandle: true,
    builder: (BuildContext context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '先选一本词书',
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '今日学习要背新词时，需要一本当前词书。选好后再回来继续。',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                height: 1.45,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.brandGreen,
                  foregroundColor: AppDesignTokens.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  '去词书架挑选',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                '稍后再说',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (go != true || !context.mounted) return false;
  await context.push('/words/syllabus');
  if (!context.mounted) return false;
  return ref.read(syllabusBooksProvider).activeBook != null;
}

/// Video recommend sheet; 「没有感兴趣的」opens 全英可逛.
Future<bool> ensureTodayVideoSource(
  BuildContext context,
  WidgetRef ref, {
  required bool Function() hasVideoTarget,
}) async {
  if (hasVideoTarget()) return true;
  if (!context.mounted) return false;

  final bool? settled = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppDesignTokens.appWhite,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      final List<AcquireDailyFeedItemDto> feed = ref.read(dailyFeedProvider);
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '选一个今天要看的视频',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '先从推荐里挑；没有感兴趣的，去「全英可逛」找合集。',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: feed.isEmpty
                      ? Center(
                          child: Text(
                            '暂无推荐，去全英可逛挑一个合集吧。',
                            style: TextStyle(
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: feed.length.clamp(0, 12),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (BuildContext context, int index) {
                            final AcquireDailyFeedItemDto item = feed[index];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: AppDesignTokens.borderGray,
                                ),
                              ),
                              tileColor: AppDesignTokens.softWhite,
                              title: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppDesignTokens.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                item.author.isEmpty
                                    ? '点开试看'
                                    : '${item.author} · 点开试看',
                                style: TextStyle(
                                  color: AppDesignTokens.textSecondary,
                                ),
                              ),
                              trailing: Icon(
                                Icons.play_circle_outline,
                                color: AppDesignTokens.brandGreen,
                              ),
                              onTap: () async {
                                await openEnglishBrowsePreview(
                                  context,
                                  ref,
                                  item: item,
                                );
                                if (sheetContext.mounted) {
                                  Navigator.pop(
                                    sheetContext,
                                    hasVideoTarget(),
                                  );
                                }
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      await context.push('/library?tab=english');
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, hasVideoTarget());
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppDesignTokens.textPrimary,
                      side: BorderSide(color: AppDesignTokens.borderGray),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '没有感兴趣的 · 去全英可逛',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: Text(
                    '稍后再说',
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  if (settled ?? false) return true;
  return hasVideoTarget();
}

/// Difficulty-aware reading picker when no continue book exists.
Future<bool> ensureTodayReadingBook(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(readingLibraryProvider).continueDoc != null) return true;
  if (!context.mounted) return false;

  List<ReadingIPlus1Match> matches = const <ReadingIPlus1Match>[];
  try {
    matches = await ref.read(readingIPlus1MatchesProvider.future);
  } catch (_) {}
  if (matches.isEmpty) {
    final List<ReadingDoc> fallback = ref.read(readingLibraryProvider).all;
    matches = <ReadingIPlus1Match>[
      for (final ReadingDoc doc in fallback.take(8))
        ReadingIPlus1Match(
          doc: doc,
          unknownRate: 0.05,
          fitness: 0.8,
          band: ReadingIPlus1Band.ideal,
        ),
    ];
  } else {
    matches = matches.take(10).toList(growable: false);
  }

  if (!context.mounted) return false;
  final ReadingDoc? picked = await showModalBottomSheet<ReadingDoc>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppDesignTokens.appWhite,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '选一本适合你的书',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '按你的词汇量排了难度。选一本作为今天的阅读目标。',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: matches.isEmpty
                      ? Center(
                          child: TextButton(
                            onPressed: () async {
                              await context.push('/reading');
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            child: const Text('打开阅读书库'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: matches.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (BuildContext context, int index) {
                            final ReadingIPlus1Match match = matches[index];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: AppDesignTokens.borderGray,
                                ),
                              ),
                              tileColor: AppDesignTokens.softWhite,
                              title: Text(
                                match.doc.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppDesignTokens.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${match.band.labelCn} · ${match.rateLabel} · ${match.doc.wordCount} 词',
                                style: TextStyle(
                                  color: AppDesignTokens.textSecondary,
                                ),
                              ),
                              trailing: Icon(
                                Icons.auto_stories_outlined,
                                color: AppDesignTokens.brandGreen,
                              ),
                              onTap: () =>
                                  Navigator.pop(sheetContext, match.doc),
                            );
                          },
                        ),
                ),
                TextButton(
                  onPressed: () async {
                    await context.push('/reading');
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: Text(
                    '去书库自己挑',
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  if (picked != null) {
    await ref.read(readingLibraryProvider.notifier).touchOpened(picked.id);
    return true;
  }
  return ref.read(readingLibraryProvider).continueDoc != null;
}

/// Oral intro: camera-translate nearby words, then optional digital-human chat.
Future<void> offerTodayOralIntro(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function() markDone,
  required bool alreadyDone,
}) async {
  if (alreadyDone || !context.mounted) return;

  final String? action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppDesignTokens.appWhite,
    showDragHandle: true,
    builder: (BuildContext context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '口语引子 · 拍周围学单词',
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '用拍照翻译认认身边的英文，背几个再决定要不要跟数字人聊聊。',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                height: 1.45,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, 'camera'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.brandGreen,
                  foregroundColor: AppDesignTokens.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  '拍照翻译周围单词',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, 'skip'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppDesignTokens.textPrimary,
                  side: BorderSide(color: AppDesignTokens.borderGray),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('今天先跳过口语'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (action == null) return;
  await markDone();
  if (action != 'camera' || !context.mounted) return;

  await context.push('/digital-human?sceneMenu=1');
  if (!context.mounted) return;

  final bool? chat = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: AppDesignTokens.appWhite,
      title: Text(
        '要跟数字人再聊聊吗？',
        style: TextStyle(
          color: AppDesignTokens.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        '可以用刚才拍到的词练几句口语；不想聊就继续今日学习。',
        style: TextStyle(color: AppDesignTokens.textSecondary),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            '不用了',
            style: TextStyle(color: AppDesignTokens.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppDesignTokens.brandGreen,
            foregroundColor: AppDesignTokens.onAccent,
          ),
          child: const Text('去聊聊'),
        ),
      ],
    ),
  );
  if ((chat ?? false) && context.mounted) {
    await context.push('/digital-human');
  }
}
