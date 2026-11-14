import 'package:flutter/material.dart';

import '../../../shared/domain/subtitle_letter_case.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../player_mock_state.dart';
import '../subtitle_display_mode.dart';
import '../subtitle_language_sanitize.dart';
import 'subtitle_vocabulary_highlight.dart';

class PlayerCurrentLineCard extends StatefulWidget {
  const PlayerCurrentLineCard({
    required this.line,
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    this.savedVocabularyWords = const <String>{},
    this.keyVocabularyWords = const <String>{},
    required this.onBookmark,
    required this.onCollectWord,
    this.onCollectWordAtTime,
    this.episodeId,
    this.onPronounce,
    super.key,
  });

  final PlayerSubtitleLine line;
  final String subtitleMode;
  final String subtitleLetterCase;
  final int currentWordIndex;
  final double fontScale;
  final bool highlightWords;
  final Set<String> savedVocabularyWords;
  final Set<String> keyVocabularyWords;
  final VoidCallback onBookmark;
  final ValueChanged<String> onCollectWord;
  final void Function(String word, String time)? onCollectWordAtTime;
  final String? episodeId;
  final VoidCallback? onPronounce;

  @override
  State<PlayerCurrentLineCard> createState() => _PlayerCurrentLineCardState();
}

class _PlayerCurrentLineCardState extends State<PlayerCurrentLineCard> {
  String? selectedWord;
  List<String> _tokens = const <String>[];

  @override
  void initState() {
    super.initState();
    _tokens = _buildTokens(
      formatSubtitleLetterCase(widget.line.english, widget.subtitleLetterCase),
    );
  }

  @override
  void didUpdateWidget(covariant PlayerCurrentLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.english != widget.line.english ||
        oldWidget.subtitleLetterCase != widget.subtitleLetterCase) {
      selectedWord = null;
      _tokens = _buildTokens(
        formatSubtitleLetterCase(
          widget.line.english,
          widget.subtitleLetterCase,
        ),
      );
    }
  }

  List<String> _buildTokens(String lineText) {
    return lineText
        .split(' ')
        .where((String word) => word.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final String english = widget.line.english.trim();
    final String chinese = widget.line.chinese.trim();
    final bool hasRealEnglish =
        english.isNotEmpty && !subtitleLooksChineseOnly(english);
    final bool requireEnglishPrimary =
        SubtitleDisplayMode.requiresEnglishPrimary(widget.subtitleMode);
    final bool chineseOnlyMode =
        SubtitleDisplayMode.isChineseOnly(widget.subtitleMode);
    final bool showEnglish = requireEnglishPrimary && hasRealEnglish;
    final bool showChineseSecondary =
        !SubtitleDisplayMode.isEnglishOnly(widget.subtitleMode) &&
        !SubtitleDisplayMode.isBlind(widget.subtitleMode) &&
        chinese.isNotEmpty &&
        showEnglish;
    final bool showChineseTempPrimary =
        (requireEnglishPrimary && !hasRealEnglish && chinese.isNotEmpty) ||
        (chineseOnlyMode && chinese.isNotEmpty);
    final bool highlightEnabled = widget.highlightWords;
    // English stays the hero size; Chinese is the smaller secondary line.
    final double englishFontSize = 32 * widget.fontScale;
    final double chineseFontSize = 14.5 * widget.fontScale;
    final double chineseTempFontSize = 26 * widget.fontScale;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7D6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '当前',
                    style: TextStyle(
                      color: AppDesignTokens.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '今日句子 · 点单词可打开学习卡',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: widget.onBookmark,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.skyLight,
                    foregroundColor: AppDesignTokens.primaryBlueDark,
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Icon(Icons.bookmark_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (showEnglish)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _tokens
                    .asMap()
                    .entries
                    .map((MapEntry<int, String> wordEntry) {
                      final int index = wordEntry.key;
                      final String token = wordEntry.value;
                      final bool selectedToken = selectedWord == token;
                      final bool karaoke =
                          highlightEnabled &&
                          widget.line.words.isNotEmpty &&
                          index == widget.currentWordIndex;
                      final SubtitleVocabMark vocabMark =
                          SubtitleVocabularyHighlight.resolve(
                            rawToken: token,
                            savedWords: widget.savedVocabularyWords,
                            keyWords: widget.keyVocabularyWords,
                          );
                      final Color vocabFill = SubtitleVocabularyHighlight.fill(
                        vocabMark,
                        onDarkVideo: false,
                      );
                      final Color fill = selectedToken || karaoke
                          ? const Color(0xFFDFF8C8)
                          : vocabFill;
                      final Color borderColor = karaoke
                          ? AppDesignTokens.brandGreen
                          : SubtitleVocabularyHighlight.border(
                              vocabMark,
                              onDarkVideo: false,
                            );
                      final double borderWidth = karaoke ? 1.5 : 0;
                      final Color wordColor =
                          SubtitleVocabularyHighlight.textColor(
                        vocabMark,
                        fallback: AppDesignTokens.textPrimary,
                        onDarkVideo: false,
                      );

                      return InkWell(
                        onTap: () {
                          setState(() {
                            selectedWord = token;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: borderColor,
                              width: borderWidth,
                            ),
                          ),
                          child: Text(
                            token,
                            style: TextStyle(
                              fontSize: englishFontSize,
                              fontWeight: SubtitleVocabularyHighlight.fontWeight(
                                vocabMark,
                                karaoke: karaoke,
                                activeLine: true,
                              ),
                              height: 1.22,
                              color: wordColor,
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            if (showChineseTempPrimary)
              Text(
                chinese,
                style: TextStyle(
                  fontSize: chineseTempFontSize,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            if (showEnglish && showChineseSecondary)
              const SizedBox(height: 10),
            if (showChineseSecondary)
              Text(
                chinese,
                style: TextStyle(
                  fontSize: chineseFontSize,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            if (selectedWord != null) ...<Widget>[
              const SizedBox(height: 18),
              WordLookupPopupCard(
                rawWord: selectedWord!,
                episodeId: widget.episodeId,
                contextTime: widget.line.startTime,
                contextSentence: widget.line.english,
                onCollect: () {
                  final void Function(String, String)? collect =
                      widget.onCollectWordAtTime;
                  if (collect != null) {
                    collect(selectedWord!, widget.line.startTime);
                  } else {
                    widget.onCollectWord(selectedWord!);
                  }
                },
                onPronounce: widget.onPronounce,
                onClose: () {
                  setState(() {
                    selectedWord = null;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
