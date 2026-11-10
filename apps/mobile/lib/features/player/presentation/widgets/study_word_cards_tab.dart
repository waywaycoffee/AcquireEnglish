import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../words/data/offline_word_dictionary.dart';
import '../../domain/episode_word_cards.dart';
import 'study_shell_tokens.dart';

/// Episode vocabulary deck inspired by Shadow Talk「词卡」.
class StudyWordCardsTab extends ConsumerStatefulWidget {
  const StudyWordCardsTab({
    required this.cards,
    required this.onJumpToCard,
    this.onFavorite,
    this.onSpeak,
    super.key,
  });

  final List<EpisodeWordCard> cards;
  final ValueChanged<EpisodeWordCard> onJumpToCard;
  final ValueChanged<EpisodeWordCard>? onFavorite;
  final ValueChanged<EpisodeWordCard>? onSpeak;

  @override
  ConsumerState<StudyWordCardsTab> createState() => _StudyWordCardsTabState();
}

class _StudyWordCardsTabState extends ConsumerState<StudyWordCardsTab> {
  EpisodeCardKind? _filter;
  List<EpisodeWordCard> _enriched = const <EpisodeWordCard>[];
  String _enrichKey = '';

  @override
  void initState() {
    super.initState();
    _enriched = widget.cards;
    _scheduleEnrich();
  }

  @override
  void didUpdateWidget(covariant StudyWordCardsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameCardIds(oldWidget.cards, widget.cards)) {
      _enriched = widget.cards;
      _scheduleEnrich();
    }
  }

  bool _sameCardIds(List<EpisodeWordCard> a, List<EpisodeWordCard> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].favorited != b[i].favorited) {
        return false;
      }
    }
    return true;
  }

  void _scheduleEnrich() {
    final String key = widget.cards.map((EpisodeWordCard c) => c.id).join('|');
    _enrichKey = key;
    final String captureKey = key;
    final List<EpisodeWordCard> source = widget.cards;
    () async {
      final OfflineWordDictionary dictionary = ref.read(
        offlineWordDictionaryProvider,
      );
      final List<EpisodeWordCard> next = <EpisodeWordCard>[];
      for (final EpisodeWordCard card in source) {
        if (card.kind != EpisodeCardKind.word ||
            (card.meaningCn != null && card.meaningCn!.trim().isNotEmpty)) {
          next.add(card);
          continue;
        }
        final OfflineWordDefinition? def = await dictionary.lookup(card.text);
        if (def == null) {
          next.add(card);
          continue;
        }
        next.add(
          EpisodeWordCard(
            id: card.id,
            text: card.text,
            kind: card.kind,
            favorited: card.favorited,
            source: card.source,
            meaningCn: def.translation,
            phonetic: def.phonetic.isEmpty ? card.phonetic : def.phonetic,
            partOfSpeech: def.partOfSpeech.isEmpty
                ? card.partOfSpeech
                : def.partOfSpeech,
            exampleEn: card.exampleEn,
            exampleCn: card.exampleCn,
            time: card.time,
            startMs: card.startMs,
            endMs: card.endMs,
            tags: card.tags,
          ),
        );
      }
      if (!mounted || _enrichKey != captureKey) return;
      setState(() => _enriched = next);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    final List<EpisodeWordCard> cards = _enriched;
    final List<EpisodeWordCard> filtered = _filter == null
        ? cards
        : cards
              .where((EpisodeWordCard c) => c.kind == _filter)
              .toList(growable: false);

    final int wordCount = cards
        .where((EpisodeWordCard c) => c.kind == EpisodeCardKind.word)
        .length;
    final int phraseCount = cards
        .where((EpisodeWordCard c) => c.kind == EpisodeCardKind.phrase)
        .length;
    final int sentenceCount = cards
        .where((EpisodeWordCard c) => c.kind == EpisodeCardKind.sentence)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
          child: Row(
            children: <Widget>[
              _FilterChip(
                label: '全部 ${cards.length}',
                selected: _filter == null,
                colors: colors,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: '单词 $wordCount',
                selected: _filter == EpisodeCardKind.word,
                colors: colors,
                onTap: () => setState(() => _filter = EpisodeCardKind.word),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: '短语 $phraseCount',
                selected: _filter == EpisodeCardKind.phrase,
                colors: colors,
                onTap: () => setState(() => _filter = EpisodeCardKind.phrase),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: '短句 $sentenceCount',
                selected: _filter == EpisodeCardKind.sentence,
                colors: colors,
                onTap: () => setState(() => _filter = EpisodeCardKind.sentence),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    '本集暂无词卡\n在字幕里点词收藏后会出现在这里',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final EpisodeWordCard card = filtered[index];
                    return _WordCardTile(
                      index: index + 1,
                      card: card,
                      colors: colors,
                      onTap: () => widget.onJumpToCard(card),
                      onFavorite: widget.onFavorite == null
                          ? null
                          : () => widget.onFavorite!(card),
                      onSpeak: widget.onSpeak == null
                          ? null
                          : () => widget.onSpeak!(card),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final StudyShellColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? colors.accent : colors.chipIdle,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? colors.accent : colors.border.withValues(alpha: 0.7),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? colors.accentOn : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _WordCardTile extends StatelessWidget {
  const _WordCardTile({
    required this.index,
    required this.card,
    required this.colors,
    required this.onTap,
    this.onFavorite,
    this.onSpeak,
  });

  final int index;
  final EpisodeWordCard card;
  final StudyShellColors colors;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey<String>('episode-word-card-${card.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 28,
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            card.text,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Tag(
                          label: card.kind.label,
                          colors: colors,
                        ),
                        if (card.favorited) ...<Widget>[
                          const SizedBox(width: 6),
                          _Tag(label: '已收藏', colors: colors, accent: true),
                        ] else if (card.source == 'suggested') ...<Widget>[
                          const SizedBox(width: 6),
                          _Tag(label: '本集推荐', colors: colors),
                        ],
                      ],
                    ),
                    if (card.phonetic != null && card.phonetic!.isNotEmpty) ...<
                      Widget
                    >[
                      const SizedBox(height: 4),
                      Text(
                        card.phonetic!,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (card.meaningCn != null &&
                        card.meaningCn!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        card.meaningCn!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (card.exampleEn != null &&
                        card.exampleEn!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        card.exampleEn!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary.withValues(alpha: 0.88),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      if (card.exampleCn != null &&
                          card.exampleCn!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            card.exampleCn!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                    ],
                    if (card.time != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          card.time!,
                          style: TextStyle(
                            color: colors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (onSpeak != null)
                IconButton(
                  tooltip: '发音',
                  onPressed: onSpeak,
                  icon: Icon(
                    Icons.volume_up_rounded,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                ),
              if (onFavorite != null)
                IconButton(
                  tooltip: card.favorited ? '已收藏' : '收藏',
                  onPressed: onFavorite,
                  icon: Icon(
                    card.favorited
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: card.favorited
                        ? colors.favorite
                        : colors.textSecondary,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.colors,
    this.accent = false,
  });

  final String label;
  final StudyShellColors colors;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent
            ? colors.favorite.withValues(alpha: 0.16)
            : colors.chipIdle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: accent ? colors.favorite : colors.textMuted,
        ),
      ),
    );
  }
}
