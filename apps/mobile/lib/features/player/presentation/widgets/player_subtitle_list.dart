import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../../../shared/domain/subtitle_letter_case.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../player_mock_state.dart';
import 'study_shell_tokens.dart';
import 'subtitle_vocabulary_highlight.dart';
import 'subtitle_word_highlight_style.dart';

const double _activeEnglishFontSize = 22;
const double _inactiveEnglishFontSize = 19;
const double _activeChineseFontSize = 13.5;
const double _inactiveChineseFontSize = 12.5;

class PlayerSubtitleList extends StatefulWidget {
  const PlayerSubtitleList({
    required this.lines,
    required this.activeIndex,
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    this.showCurrentOnly = false,
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    this.subtitleWordHighlightStyle = '绿色填充',
    this.subtitleWordHighlightBorderWidth = 2.5,
    this.savedVocabularyWords = const <String>{},
    this.keyVocabularyWords = const <String>{},
    required this.onTapLine,
    required this.onCollectWord,
    this.onCollectWordAtTime,
    this.onFavoriteWord,
    required this.onBookmarkLine,
    required this.onLoopFromLine,
    required this.onDictationLine,
    required this.onAiExplain,
    this.loopingLineIndex,
    this.isPlaying = false,
    this.onTogglePlaying,
    this.episodeId,
    this.onPronounce,
    this.onAssessLine,
    this.pronunciationUnavailableReasonForLine,
    this.showAiGenerateSubtitles = false,
    this.generatingAiSubtitles = false,
    this.aiSubtitleProgressValue,
    this.aiSubtitleProgressText,
    this.aiSubtitlePreviewText,
    this.aiSubtitleErrorText,
    this.onGenerateAiSubtitles,
    this.onRegenerateAiSubtitles,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
    this.bilingualPipelineLabel,
    this.showAiCompleteButton = false,
    this.onAiComplete,
    this.onCancelBilingualPipeline,
    this.studyDarkStyle = false,
    this.blindListening = false,
    this.onDictionaryOpened,
    this.onDictionaryClosed,
    super.key,
  });

  final List<PlayerSubtitleLine> lines;
  final int activeIndex;
  final String subtitleMode;
  final String subtitleLetterCase;
  final bool showCurrentOnly;
  final int currentWordIndex;
  final double fontScale;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final Set<String> savedVocabularyWords;
  final Set<String> keyVocabularyWords;
  final ValueChanged<int> onTapLine;
  final ValueChanged<String> onCollectWord;
  final void Function(String word, String time)? onCollectWordAtTime;
  final ValueChanged<String>? onFavoriteWord;
  final ValueChanged<int> onBookmarkLine;
  final ValueChanged<int> onLoopFromLine;
  final ValueChanged<int> onDictationLine;
  final ValueChanged<int> onAiExplain;
  final int? loopingLineIndex;
  final bool isPlaying;
  final VoidCallback? onTogglePlaying;
  final String? episodeId;
  final VoidCallback? onPronounce;
  final ValueChanged<int>? onAssessLine;
  final String? Function(int index)? pronunciationUnavailableReasonForLine;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? aiSubtitleProgressValue;
  final String? aiSubtitleProgressText;
  final String? aiSubtitlePreviewText;
  final String? aiSubtitleErrorText;
  final VoidCallback? onGenerateAiSubtitles;
  final VoidCallback? onRegenerateAiSubtitles;
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;
  final String? bilingualPipelineLabel;
  final bool showAiCompleteButton;
  final VoidCallback? onAiComplete;
  final VoidCallback? onCancelBilingualPipeline;
  final bool studyDarkStyle;
  final bool blindListening;
  final VoidCallback? onDictionaryOpened;
  final VoidCallback? onDictionaryClosed;

  @override
  State<PlayerSubtitleList> createState() => _PlayerSubtitleListState();
}

class _PlayerSubtitleListState extends State<PlayerSubtitleList> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};
  final Set<int> _blindRevealed = <int>{};
  String? _activeDictionaryTokenId;
  OverlayEntry? _dictionaryOverlayEntry;
  bool _autoFollowCurrentLine = true;
  int? _regeneratingAiLineIndex;

  bool get _showCurrentOnly => widget.showCurrentOnly;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_dismissDictionary);
    // Always bring the resume / active cue into view on first layout.
    _scheduleScrollToActiveLine();
  }

  @override
  void didUpdateWidget(covariant PlayerSubtitleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blindListening != widget.blindListening) {
      _blindRevealed.clear();
    }
    // Resume auto-follow whenever playback starts again.
    if (!oldWidget.isPlaying && widget.isPlaying) {
      _autoFollowCurrentLine = true;
    }
    final bool listStateChanged =
        oldWidget.activeIndex != widget.activeIndex ||
        oldWidget.lines.length != widget.lines.length ||
        oldWidget.subtitleMode != widget.subtitleMode ||
        oldWidget.showCurrentOnly != widget.showCurrentOnly;
    final bool shouldFollowCurrentLine =
        _autoFollowCurrentLine &&
        (oldWidget.activeIndex != widget.activeIndex ||
            oldWidget.isPlaying != widget.isPlaying ||
            oldWidget.lines.length != widget.lines.length ||
            oldWidget.showCurrentOnly != widget.showCurrentOnly);

    if (!listStateChanged && !shouldFollowCurrentLine) {
      return;
    }

    final bool activeLineChanged = oldWidget.activeIndex != widget.activeIndex;
    final bool listStructureChanged =
        oldWidget.lines.length != widget.lines.length ||
        oldWidget.subtitleMode != widget.subtitleMode ||
        oldWidget.showCurrentOnly != widget.showCurrentOnly;

    if (listStructureChanged) {
      _dismissDictionary();
    }

    if (activeLineChanged && _dictionaryOverlayEntry != null) {
      _scheduleScrollToActiveLine();
      return;
    }

    if (shouldFollowCurrentLine || listStructureChanged) {
      _scheduleScrollToActiveLine();
    }
  }

  @override
  void dispose() {
    _removeDictionaryOverlay(notify: false);
    _scrollController
      ..removeListener(_dismissDictionary)
      ..dispose();
    super.dispose();
  }

  GlobalKey _rowKeyFor(int index) {
    return _rowKeys[index] ??= GlobalKey(debugLabel: 'subtitle-line-$index');
  }

  void _scrollToActiveLine() {
    if (_showCurrentOnly || !_scrollController.hasClients) {
      return;
    }
    if (widget.activeIndex < 0 || widget.activeIndex >= widget.lines.length) {
      return;
    }

    final BuildContext? activeContext =
        _rowKeys[widget.activeIndex]?.currentContext;
    if (activeContext == null) {
      final double estimatedExtent = widget.studyDarkStyle ? 118.0 : 132.0;
      final double targetOffset = (widget.activeIndex * estimatedExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(targetOffset);
      return;
    }

    Scrollable.ensureVisible(
      activeContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
  }

  void _scheduleScrollToActiveLine({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_autoFollowCurrentLine) {
        return;
      }
      if (!_scrollController.hasClients) {
        if (attempt < 10) {
          _scheduleScrollToActiveLine(attempt: attempt + 1);
        }
        return;
      }
      _scrollToActiveLine();
      // Second pass once the jumped-to row has been built.
      if (attempt < 2 &&
          _rowKeys[widget.activeIndex]?.currentContext == null) {
        _scheduleScrollToActiveLine(attempt: attempt + 1);
      } else if (attempt < 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoFollowCurrentLine) {
            _scrollToActiveLine();
          }
        });
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _autoFollowCurrentLine = false;
    }
    return false;
  }

  void _dismissDictionary() {
    if (_activeDictionaryTokenId == null && _dictionaryOverlayEntry == null) {
      return;
    }
    _removeDictionaryOverlay();
  }

  void _removeDictionaryOverlay({
    bool notify = true,
    bool emitClosed = true,
  }) {
    final bool hadOverlay = _dictionaryOverlayEntry != null ||
        _activeDictionaryTokenId != null;
    _dictionaryOverlayEntry?.remove();
    _dictionaryOverlayEntry = null;
    if (hadOverlay && emitClosed) {
      widget.onDictionaryClosed?.call();
    }
    if (!notify || !mounted || _activeDictionaryTokenId == null) {
      _activeDictionaryTokenId = null;
      return;
    }
    setState(() {
      _activeDictionaryTokenId = null;
    });
  }

  void _toggleDictionaryOverlay(
    BuildContext anchorContext,
    String rawWord,
    String contextSentence,
    String tokenId,
    String contextTime,
  ) {
    if (_activeDictionaryTokenId == tokenId) {
      _removeDictionaryOverlay();
      return;
    }

    _removeDictionaryOverlay(notify: false, emitClosed: false);
    widget.onDictionaryOpened?.call();

    final OverlayState overlayState = Overlay.of(context, rootOverlay: true);
    final RenderBox overlayBox =
        overlayState.context.findRenderObject()! as RenderBox;
    final RenderBox anchorBox = anchorContext.findRenderObject()! as RenderBox;
    final Offset anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final Size anchorSize = anchorBox.size;
    final Size overlaySize = overlayBox.size;
    const double preferredPopupHeight = 520;
    const double viewportPadding = 16;
    final double popupWidth = (overlaySize.width - viewportPadding * 2).clamp(
      0.0,
      WordLookupPopupCard.preferredWidth,
    );
    const double popupGap = 8;
    final double popupHeight = (overlaySize.height - (viewportPadding * 2))
        .clamp(120.0, preferredPopupHeight);

    final double availableRight =
        overlaySize.width - (anchorTopLeft.dx + anchorSize.width);
    final double availableLeft = anchorTopLeft.dx;
    final double availableBelow =
        overlaySize.height - (anchorTopLeft.dy + anchorSize.height);
    final bool canShowRight = availableRight >= popupWidth + popupGap;
    final bool canShowLeft = availableLeft >= popupWidth + popupGap;
    final bool showRight = canShowRight || !canShowLeft;
    final bool showSide = canShowRight || canShowLeft;
    final bool showAbove =
        !showSide &&
        availableBelow < popupHeight + viewportPadding &&
        anchorTopLeft.dy > availableBelow;

    final double left;
    final double top;
    if (showSide) {
      left = showRight
          ? (anchorTopLeft.dx + anchorSize.width + popupGap).clamp(
              viewportPadding,
              overlaySize.width - popupWidth - viewportPadding,
            )
          : (anchorTopLeft.dx - popupWidth - popupGap).clamp(
              viewportPadding,
              overlaySize.width - popupWidth - viewportPadding,
            );
      top = (anchorTopLeft.dy + (anchorSize.height / 2) - (popupHeight / 2))
          .clamp(
            viewportPadding,
            overlaySize.height - popupHeight - viewportPadding,
          );
    } else {
      final double unclampedLeft =
          anchorTopLeft.dx + (anchorSize.width / 2) - (popupWidth / 2);
      left = unclampedLeft.clamp(
        viewportPadding,
        overlaySize.width - popupWidth - viewportPadding,
      );
      top = showAbove
          ? (anchorTopLeft.dy - popupHeight - popupGap).clamp(
              viewportPadding,
              overlaySize.height - popupHeight - viewportPadding,
            )
          : (anchorTopLeft.dy + anchorSize.height + popupGap).clamp(
              viewportPadding,
              overlaySize.height - popupHeight - viewportPadding,
            );
    }

    _dictionaryOverlayEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissDictionary,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              child: Material(
                color: Colors.transparent,
                child: WordLookupPopupCard(
                  rawWord: rawWord,
                  episodeId: widget.episodeId,
                  contextTime: contextTime,
                  contextSentence: contextSentence,
                  showAbove: showAbove,
                  showSide: showSide,
                  showRight: showRight,
                  maxHeight: popupHeight,
                  onPronounce: widget.onPronounce,
                  onClose: _dismissDictionary,
                  onCollect: () {
                    final void Function(String, String)? collect =
                        widget.onCollectWordAtTime;
                    if (collect != null) {
                      collect(rawWord, contextTime);
                    } else {
                      widget.onCollectWord(rawWord);
                    }
                  },
                  onFavorite: widget.onFavoriteWord == null
                      ? null
                      : () => widget.onFavoriteWord!(rawWord),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlayState.insert(_dictionaryOverlayEntry!);
    setState(() {
      _activeDictionaryTokenId = tokenId;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subtitleMode == '隐藏') {
      return _SubtitlePlaceholder(
        icon: Icons.closed_caption_disabled_outlined,
        title: '字幕已隐藏',
        body: '在底栏打开「双语」或切换字幕模式后可恢复列表。',
        showAiGenerateSubtitles: widget.showAiGenerateSubtitles,
        generatingAiSubtitles: widget.generatingAiSubtitles,
        progressValue: widget.aiSubtitleProgressValue,
        progressText: widget.aiSubtitleProgressText,
        previewText: widget.aiSubtitlePreviewText,
        errorText: widget.aiSubtitleErrorText,
        onGenerateAiSubtitles: widget.onGenerateAiSubtitles,
        studyDarkStyle: widget.studyDarkStyle,
      );
    }

    final int totalLineCount = widget.lines.length;
    if (totalLineCount == 0 && widget.showAiGenerateSubtitles) {
      return _SubtitlePlaceholder(
        icon: Icons.mic_none_rounded,
        title: '当前视频没有字幕',
        body: '点击下方按钮，用语音识别自动生成可跟读的词级同步字幕。',
        showAiGenerateSubtitles: widget.showAiGenerateSubtitles,
        generatingAiSubtitles: widget.generatingAiSubtitles,
        progressValue: widget.aiSubtitleProgressValue,
        progressText: widget.aiSubtitleProgressText,
        previewText: widget.aiSubtitlePreviewText,
        errorText: widget.aiSubtitleErrorText,
        onGenerateAiSubtitles: widget.onGenerateAiSubtitles,
        studyDarkStyle: widget.studyDarkStyle,
      );
    }

    final int itemCount = _showCurrentOnly ? 1 : totalLineCount;

    final Widget list = SelectionArea(
      key: const ValueKey<String>('subtitle-list-selection-area'),
      onSelectionChanged: (SelectedContent? selection) {
        if (selection?.plainText.trim().isNotEmpty ?? false) {
          _autoFollowCurrentLine = false;
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.all(2),
          itemCount: itemCount,
          itemBuilder: (BuildContext context, int itemIndex) {
            final int originalIndex = _showCurrentOnly
                ? widget.activeIndex
                : itemIndex;
            if (originalIndex < 0 || originalIndex >= totalLineCount) {
              return const SizedBox.shrink();
            }

            final PlayerSubtitleLine line = widget.lines[originalIndex];
            final bool active = originalIndex == widget.activeIndex;
            final bool isLooping = originalIndex == widget.loopingLineIndex;
            final bool isPast = originalIndex < widget.activeIndex;
            final String? pronunciationUnavailableReason = widget
                .pronunciationUnavailableReasonForLine
                ?.call(originalIndex);
            final bool dark = widget.studyDarkStyle;
            final StudyShellColors shell = StudyShellColors.of(context);
            final bool blindHidden = widget.blindListening &&
                !_blindRevealed.contains(originalIndex);
            final double textOpacity = active ? 1 : (isPast ? 0.84 : 0.60);
            final double chineseOnlyFontSize =
                (active ? 18.0 : 16.0) * widget.fontScale;
            final double chineseFontSize =
                (active ? _activeChineseFontSize : _inactiveChineseFontSize) *
                widget.fontScale;
            final Color inactiveStartTimeColor = dark
                ? shell.textMuted
                : const Color(0xFFADB7B0);
            final Color inactiveZhTextColor = dark
                ? shell.textSecondary
                : const Color(0xFFB7C2BA);

            return InkWell(
              key: _rowKeyFor(originalIndex),
              onTap: () {
                if (blindHidden) {
                  setState(() => _blindRevealed.add(originalIndex));
                }
                widget.onTapLine(originalIndex);
              },
              onLongPress: () => _openActions(context, line, originalIndex),
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                padding: EdgeInsets.all(dark ? 14 : 12),
                decoration: BoxDecoration(
                  color: dark
                      ? (active ? shell.cardActive : shell.card)
                      : (active ? const Color(0xFFEFFFF5) : Colors.white),
                  borderRadius: BorderRadius.circular(dark ? 18 : 24),
                  border: Border.all(
                    color: dark
                        ? (active ? shell.borderActive : shell.border)
                        : (active
                              ? AppDesignTokens.brandGreen
                              : const Color(0xFFE1E7E1)),
                    width: active ? (dark ? 2 : 2.5) : 1,
                  ),
                  boxShadow: dark
                      ? (active
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: shell.glowAccent,
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : const <BoxShadow>[])
                      : const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                ),
                child: Stack(
                  children: <Widget>[
                    if (active && !dark)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7D6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '正在学习',
                            style: TextStyle(
                              color: AppDesignTokens.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (dark) ...<Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.lock_open_rounded,
                                size: 16,
                                color: active
                                    ? shell.textSecondary
                                    : shell.textMuted.withValues(
                                        alpha: textOpacity,
                                      ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                line.startTime,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? shell.textSecondary
                                      : inactiveStartTimeColor.withValues(
                                          alpha: textOpacity,
                                        ),
                                ),
                              ),
                              Expanded(
                                child: active && widget.onTogglePlaying != null
                                    ? Center(
                                        child: IconButton(
                                          onPressed: widget.onTogglePlaying,
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          icon: Icon(
                                            widget.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: shell.textPrimary,
                                            size: 26,
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              IconButton(
                                onPressed: () =>
                                    widget.onBookmarkLine(originalIndex),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                icon: Icon(
                                  Icons.favorite_border_rounded,
                                  color: shell.textSecondary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ] else
                          Row(
                            children: <Widget>[
                              FilledButton.tonal(
                                onPressed: active
                                    ? widget.onTogglePlaying
                                    : () => widget.onTapLine(originalIndex),
                                style: FilledButton.styleFrom(
                                  backgroundColor: active
                                      ? const Color(0xFFDFF8C8)
                                      : AppDesignTokens.softWhite,
                                  foregroundColor: active
                                      ? AppDesignTokens.brandGreenDark
                                      : AppDesignTokens.primaryBlueDark,
                                  minimumSize: const Size(44, 44),
                                  fixedSize: const Size(44, 44),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Icon(
                                  active && widget.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  line.startTime,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: active
                                        ? const Color(0xFF7E8A82)
                                        : inactiveStartTimeColor.withValues(
                                            alpha: textOpacity,
                                          ),
                                  ),
                                ),
                              ),
                              if (widget.onAssessLine != null) ...<Widget>[
                                IconButton.filledTonal(
                                  key: ValueKey<String>(
                                    'subtitle-line-assess-$originalIndex',
                                  ),
                                  tooltip:
                                      pronunciationUnavailableReason ?? '跟读录音',
                                  onPressed:
                                      pronunciationUnavailableReason == null
                                      ? () =>
                                            widget.onAssessLine!(originalIndex)
                                      : null,
                                  icon: const Icon(Icons.mic_rounded, size: 20),
                                  style: IconButton.styleFrom(
                                    foregroundColor:
                                        AppDesignTokens.primaryBlueDark,
                                    backgroundColor: AppDesignTokens.softWhite,
                                    minimumSize: const Size(44, 44),
                                    fixedSize: const Size(44, 44),
                                    padding: EdgeInsets.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              FilledButton.tonal(
                                key: ValueKey<String>(
                                  'subtitle-line-loop-$originalIndex',
                                ),
                                onPressed: () =>
                                    widget.onLoopFromLine(originalIndex),
                                style: FilledButton.styleFrom(
                                  backgroundColor: isLooping
                                      ? const Color(0xFFDFF8C8)
                                      : AppDesignTokens.softWhite,
                                  foregroundColor: isLooping
                                      ? AppDesignTokens.brandGreenDark
                                      : AppDesignTokens.textSecondary,
                                  minimumSize: const Size(44, 44),
                                  fixedSize: const Size(44, 44),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Icon(Icons.repeat_one_rounded),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.tonal(
                                onPressed: () =>
                                    widget.onBookmarkLine(originalIndex),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFF7D6),
                                  foregroundColor: const Color(0xFFB58600),
                                  minimumSize: const Size(44, 44),
                                  fixedSize: const Size(44, 44),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Icon(Icons.star_rounded),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.tonal(
                                onPressed: () =>
                                    _openActions(context, line, originalIndex),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppDesignTokens.softWhite,
                                  foregroundColor:
                                      AppDesignTokens.textSecondary,
                                  minimumSize: const Size(44, 44),
                                  fixedSize: const Size(44, 44),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Icon(Icons.more_horiz_rounded),
                              ),
                            ],
                          ),
                        SizedBox(height: dark ? 4 : 8),
                        if (blindHidden) ...<Widget>[
                          Container(
                            height: 14,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: shell.chipIdle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          Container(
                            height: 12,
                            width: 180,
                            decoration: BoxDecoration(
                              color: shell.chipIdle.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '点击显示',
                            style: TextStyle(
                              color: shell.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else if (widget.subtitleMode == '单中')
                          Text(
                            line.chinese,
                            style: TextStyle(
                              fontSize: chineseOnlyFontSize,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: active
                                  ? (dark
                                        ? shell.textPrimary
                                        : const Color(0xFF191C1E))
                                  : inactiveZhTextColor.withValues(
                                      alpha: textOpacity,
                                    ),
                              height: 1.35,
                            ),
                          )
                        else
                          _buildWordLine(
                            formatSubtitleLetterCase(
                              line.english,
                              widget.subtitleLetterCase,
                            ),
                            active && line.words.isNotEmpty
                                ? widget.currentWordIndex
                                : null,
                            active,
                            line.startTime,
                            shellColors: dark ? shell : null,
                          ),
                        if (!blindHidden && widget.subtitleMode != '单英') ...<Widget>[
                          const _SelectableLineBreak(),
                          const SizedBox(height: 6),
                          Text(
                            line.chinese,
                            style: TextStyle(
                              fontSize: chineseFontSize,
                              fontWeight: FontWeight.w500,
                              color: active
                                  ? (dark
                                        ? shell.textSecondary
                                        : const Color(0xFF708077))
                                  : inactiveZhTextColor.withValues(
                                      alpha: textOpacity,
                                    ),
                              height: 1.4,
                            ),
                          ),
                        ],
                        const _SelectableLineBreak(),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 4),
                Divider(
                  key: const ValueKey<String>('subtitle-list-divider'),
                  height: 1,
                  thickness: 1,
                  color: widget.studyDarkStyle
                      ? Colors.transparent
                      : const Color(0xFFE6EBE7),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
    final Color toolbarColor = widget.studyDarkStyle
        ? StudyShellColors.of(context).textSecondary
        : AppDesignTokens.textSecondary;
    final StudyShellColors shell = StudyShellColors.of(context);
    final bool showBilingualChip =
        (widget.bilingualPipelineLabel?.trim().isNotEmpty ?? false) ||
        widget.showAiCompleteButton;
    return Column(
      children: <Widget>[
        if (showBilingualChip)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.studyDarkStyle
                    ? shell.chipIdle
                    : const Color(0xFFF2F6F3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.studyDarkStyle
                      ? shell.border
                      : const Color(0xFFE1E7E1),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.subtitles_outlined,
                      size: 18,
                      color: widget.studyDarkStyle
                          ? shell.textSecondary
                          : AppDesignTokens.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.bilingualPipelineLabel?.trim().isNotEmpty ?? false
                            ? widget.bilingualPipelineLabel!.trim()
                            : '单语字幕可补全',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: widget.studyDarkStyle
                              ? shell.textPrimary
                              : AppDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                    if (widget.showAiCompleteButton &&
                        widget.onAiComplete != null) ...<Widget>[
                      const SizedBox(width: 6),
                      FilledButton(
                        key: const ValueKey<String>('bilingual-ai-complete'),
                        onPressed: widget.onAiComplete,
                        style: FilledButton.styleFrom(
                          backgroundColor: shell.accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'AI 补全',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    if (widget.onCancelBilingualPipeline != null) ...<Widget>[
                      const SizedBox(width: 4),
                      IconButton(
                        key: const ValueKey<String>('bilingual-pipeline-cancel'),
                        tooltip: '取消',
                        onPressed: widget.onCancelBilingualPipeline,
                        icon: Icon(
                          Icons.close_rounded,
                          color: widget.studyDarkStyle
                              ? shell.textMuted
                              : AppDesignTokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextButton.icon(
                onPressed: () {
                  _autoFollowCurrentLine = true;
                  _scheduleScrollToActiveLine();
                },
                icon: Icon(Icons.my_location_rounded, color: toolbarColor),
                label: Text(
                  '定位当前',
                  style: TextStyle(color: toolbarColor),
                ),
              ),
              if (widget.onRegenerateAiSubtitles != null)
                TextButton.icon(
                  onPressed: widget.onRegenerateAiSubtitles,
                  icon: Icon(Icons.refresh_rounded, color: toolbarColor),
                  label: Text(
                    widget.studyDarkStyle ? '重新识别' : '重新生成',
                    style: TextStyle(color: toolbarColor),
                  ),
                ),
              if (widget.onDeleteAiSubtitles != null)
                TextButton.icon(
                  onPressed: widget.onDeleteAiSubtitles,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: toolbarColor,
                  ),
                  label: Text(
                    '切回原始字幕',
                    style: TextStyle(color: toolbarColor),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Future<void> _openActions(
    BuildContext context,
    PlayerSubtitleLine line,
    int index,
  ) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text('收藏到短语库'),
                  onTap: () => Navigator.of(context).pop('bookmark'),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_all_rounded),
                  title: const Text('复制英文'),
                  onTap: () => Navigator.of(context).pop('copy-en'),
                ),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: const Text('复制中英双语'),
                  onTap: () => Navigator.of(context).pop('copy-bi'),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI 语法解析'),
                  subtitle: const Text('分析句子结构、语法点与表达'),
                  onTap: () => Navigator.of(context).pop('ai-explain'),
                ),
                if (widget.onRegenerateAiLine != null)
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('AI 重新生成当前句'),
                    subtitle: const Text('只替换这一句，失败时保留原句'),
                    trailing: _regeneratingAiLineIndex == index
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    enabled: _regeneratingAiLineIndex == null,
                    onTap: _regeneratingAiLineIndex == null
                        ? () => Navigator.of(context).pop('regenerate-ai-line')
                        : null,
                  ),
                ListTile(
                  leading: const Icon(Icons.repeat_one_rounded),
                  title: const Text('从这里开始循环'),
                  onTap: () => Navigator.of(context).pop('loop'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('加入听写练习'),
                  onTap: () => Navigator.of(context).pop('dictation'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null) {
      return;
    }

    switch (action) {
      case 'bookmark':
        widget.onBookmarkLine(index);
        return;
      case 'copy-en':
        await Clipboard.setData(ClipboardData(text: line.english));
        if (!context.mounted) {
          return;
        }
        _showMessage(context, '已复制英文');
        return;
      case 'copy-bi':
        await Clipboard.setData(
          ClipboardData(text: '${line.english}\n${line.chinese}'),
        );
        if (!context.mounted) {
          return;
        }
        _showMessage(context, '已复制中英双语');
        return;
      case 'loop':
        widget.onLoopFromLine(index);
        return;
      case 'dictation':
        widget.onDictationLine(index);
        return;
      case 'ai-explain':
        widget.onAiExplain(index);
        return;
      case 'regenerate-ai-line':
        final Future<void> Function(int index)? regenerate =
            widget.onRegenerateAiLine;
        if (regenerate == null || _regeneratingAiLineIndex != null) return;
        setState(() {
          _regeneratingAiLineIndex = index;
        });
        try {
          await regenerate(index);
        } finally {
          if (mounted) {
            setState(() {
              _regeneratingAiLineIndex = null;
            });
          }
        }
        return;
    }
  }

  Widget _buildWordLine(
    String text,
    int? highlightIndex,
    bool active,
    String contextTime, {
    StudyShellColors? shellColors,
  }) {
    final List<_WordToken> tokens = text
        .split(' ')
        .where((String rawWord) => rawWord.isNotEmpty)
        .map((String rawWord) => _WordToken(value: rawWord))
        .toList(growable: false);
    final StudyShellColors? shell = shellColors;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: tokens
          .asMap()
          .entries
          .map((MapEntry<int, _WordToken> entry) {
            final int index = entry.key;
            final _WordToken token = entry.value;
            final bool karaoke =
                active &&
                widget.highlightWords &&
                highlightIndex != null &&
                index == highlightIndex;
            final SubtitleVocabMark vocabMark =
                SubtitleVocabularyHighlight.resolve(
                  rawToken: token.value,
                  savedWords: widget.savedVocabularyWords,
                  keyWords: widget.keyVocabularyWords,
                );
            final String tokenId = '$text-$index';
            final Color wordColor = shell?.textPrimary ??
                AppDesignTokens.textPrimary;
            final Color vocabFill = SubtitleVocabularyHighlight.fill(
              vocabMark,
              onDarkVideo: false,
            );
            final Color karaokeFill = shell == null
                ? SubtitleWordHighlightStyle.background(
                    widget.subtitleWordHighlightStyle,
                    highlighted: karaoke,
                  )
                : (karaoke
                      ? shell.highlight.withValues(alpha: 0.22)
                      : Colors.transparent);
            final Color highlightFill =
                karaoke ? karaokeFill : vocabFill;
            final Color karaokeBorder = shell == null
                ? SubtitleWordHighlightStyle.borderColor(
                    widget.subtitleWordHighlightStyle,
                    highlighted: karaoke,
                  )
                : (karaoke ? shell.highlight : Colors.transparent);
            final Color vocabBorder = SubtitleVocabularyHighlight.border(
              vocabMark,
              onDarkVideo: false,
            );
            final Color highlightBorder =
                karaoke ? karaokeBorder : vocabBorder;
            final TextDecoration? highlightDecoration = shell == null
                ? SubtitleWordHighlightStyle.textDecoration(
                    widget.subtitleWordHighlightStyle,
                    highlighted: karaoke,
                  )
                : (karaoke ? TextDecoration.underline : null);
            final Color? highlightDecorationColor = shell == null
                ? SubtitleWordHighlightStyle.textDecorationColor(
                    widget.subtitleWordHighlightStyle,
                    highlighted: karaoke,
                  )
                : (karaoke ? shell.highlight : null);
            final double borderWidth = karaoke
                ? (shell == null
                      ? SubtitleWordHighlightStyle.borderWidth(
                          widget.subtitleWordHighlightStyle,
                          highlighted: karaoke,
                          width: widget.subtitleWordHighlightBorderWidth,
                        )
                      : 0)
                : (vocabMark == SubtitleVocabMark.none ? 0 : 1.2);

            return Builder(
              builder: (BuildContext wordContext) {
                return InkWell(
                  onTap: () => _toggleDictionaryOverlay(
                    wordContext,
                    token.value,
                    text,
                    tokenId,
                    contextTime,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: highlightFill,
                      border: Border.all(
                        color: highlightBorder,
                        width: borderWidth,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Text(
                          token.value,
                          style: TextStyle(
                            fontSize: active
                                ? _activeEnglishFontSize * widget.fontScale
                                : _inactiveEnglishFontSize * widget.fontScale,
                            fontWeight: SubtitleVocabularyHighlight.fontWeight(
                              vocabMark,
                              karaoke: karaoke,
                              activeLine: active,
                            ),
                            color: wordColor,
                            decoration: highlightDecoration,
                            decorationColor: highlightDecorationColor,
                            decorationThickness: karaoke &&
                                    (shell != null ||
                                        widget.subtitleWordHighlightStyle ==
                                            '下划线')
                                ? 2
                                : null,
                            height: 1.28,
                          ),
                        ),
                        if (index != tokens.length - 1)
                          const Positioned(
                            right: -1,
                            bottom: 0,
                            child: IgnorePointer(child: Text(' ')),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          })
          .toList(growable: false),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _WordToken {
  const _WordToken({required this.value});

  final String value;
}

class _SelectableLineBreak extends StatelessWidget {
  const _SelectableLineBreak();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: SizedBox(
        height: 0.01,
        child: Text(
          '\n',
          style: TextStyle(
            fontSize: 1,
            height: 0.01,
            color: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _SubtitlePlaceholder extends StatelessWidget {
  const _SubtitlePlaceholder({
    required this.icon,
    required this.title,
    required this.body,
    required this.showAiGenerateSubtitles,
    required this.generatingAiSubtitles,
    required this.progressValue,
    required this.progressText,
    required this.previewText,
    required this.errorText,
    required this.onGenerateAiSubtitles,
    this.studyDarkStyle = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? progressValue;
  final String? progressText;
  final String? previewText;
  final String? errorText;
  final VoidCallback? onGenerateAiSubtitles;
  final bool studyDarkStyle;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    final Color titleColor = studyDarkStyle
        ? shell.textPrimary
        : const Color(0xFF53625A);
    final Color bodyColor = studyDarkStyle
        ? shell.textSecondary
        : const Color(0xFF7E8A82);
    final Color iconColor = studyDarkStyle
        ? shell.textMuted
        : const Color(0xFF9AA69E);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 34, color: iconColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: bodyColor,
              ),
            ),
            if (showAiGenerateSubtitles) ...<Widget>[
              const SizedBox(height: 14),
              if (!generatingAiSubtitles &&
                  (errorText?.isNotEmpty ?? false)) ...<Widget>[
                SizedBox(
                  width: 320,
                  child: Text(
                    '识别失败：$errorText',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFFFF6B6B),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (generatingAiSubtitles) ...<Widget>[
                SizedBox(
                  width: 240,
                  child: LinearProgressIndicator(
                    value: progressValue,
                    color: shell.accent,
                    backgroundColor: shell.progressTrack,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  progressText ?? '正在准备音频...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 300,
                  height: 44,
                  child: Text(
                    previewText?.isNotEmpty ?? false
                        ? previewText!
                        : '等待识别文本...',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: bodyColor,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                key: const ValueKey<String>('study-asr-generate'),
                onPressed: generatingAiSubtitles ? null : onGenerateAiSubtitles,
                style: FilledButton.styleFrom(
                  backgroundColor: shell.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.mic_rounded),
                label: Text(
                  generatingAiSubtitles ? '正在语音识别生成字幕...' : '语音识别生成字幕',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
