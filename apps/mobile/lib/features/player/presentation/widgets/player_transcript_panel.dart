import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../player_mock_state.dart';
import 'player_subtitle_list.dart';
import 'subtitle_chunk_highlight.dart';

class PlayerTranscriptPanel extends StatefulWidget {
  const PlayerTranscriptPanel({
    required this.lines,
    required this.activeIndex,
    this.timelineFollowEpoch = 0,
    this.locateEpoch = 0,
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    required this.subtitleWordHighlightStyle,
    this.subtitleWordHighlightBorderWidth = 2.5,
    this.savedVocabularyWords = const <String>{},
    this.learnedVocabularyWords = const <String>{},
    this.keyVocabularyWords = const <String>{},
    this.chunkHighlighter,
    required this.onTapLine,
    required this.onCollectWord,
    this.onCollectWordAtTime,
    this.onFavoriteWord,
    required this.onBookmarkLine,
    this.isLineBookmarked,
    required this.onLoopFromLine,
    required this.onDictationLine,
    required this.onAiExplain,
    this.loopingLineIndex,
    required this.isPlaying,
    required this.onTogglePlaying,
    this.episodeId,
    this.onPronounce,
    this.onAssessLine,
    this.pronunciationUnavailableReasonForLine,
    this.onRegenerateAiSubtitles,
    this.onResetEpisodeSubtitles,
    this.onRerecognizeEnglish,
    this.onRerecognizeChinese,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
    this.onEditEnglishLine,
    this.onEditSubtitleLine,
    this.onResegment,
    this.onOpenSubtitleEditor,
    this.onEditLineNote,
    this.lineNotesByStartMs = const <int, String>{},
    this.studyDarkStyle = false,
    this.blindListening = false,
    this.showAiGenerateSubtitles = false,
    this.generatingAiSubtitles = false,
    this.aiSubtitleProgressValue,
    this.aiSubtitleProgressText,
    this.aiSubtitlePreviewText,
    this.aiSubtitleErrorText,
    this.onGenerateAiSubtitles,
    this.bilingualPipelineLabel,
    this.bilingualPipelineProgressValue,
    this.showAiCompleteButton = false,
    this.onAiComplete,
    this.onCancelBilingualPipeline,
    this.onDictionaryOpened,
    this.onDictionaryClosed,
    this.fragmentsBySentenceStartMs = const <int, List<PlayerSubtitleLine>>{},
    super.key,
  });

  final List<PlayerSubtitleLine> lines;
  final Map<int, List<PlayerSubtitleLine>> fragmentsBySentenceStartMs;
  final int activeIndex;
  final int timelineFollowEpoch;

  /// Bumped by bottom「定位当前」to scroll the active cue into view.
  final int locateEpoch;
  final String subtitleMode;
  final String subtitleLetterCase;
  final int currentWordIndex;
  final double fontScale;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final Set<String> savedVocabularyWords;
  final Set<String> learnedVocabularyWords;
  final Set<String> keyVocabularyWords;
  final SubtitleChunkHighlighter? chunkHighlighter;
  final ValueChanged<int> onTapLine;
  final ValueChanged<String> onCollectWord;
  final void Function(String word, String time)? onCollectWordAtTime;
  final void Function(String word, [String? definitionCn])? onFavoriteWord;
  final ValueChanged<int> onBookmarkLine;
  final bool Function(int index)? isLineBookmarked;
  final ValueChanged<int> onLoopFromLine;
  final ValueChanged<int> onDictationLine;
  final ValueChanged<int> onAiExplain;
  final int? loopingLineIndex;
  final bool isPlaying;
  final VoidCallback onTogglePlaying;
  final String? episodeId;
  final VoidCallback? onPronounce;
  final ValueChanged<int>? onAssessLine;
  final String? Function(int index)? pronunciationUnavailableReasonForLine;
  final VoidCallback? onRegenerateAiSubtitles;
  final VoidCallback? onResetEpisodeSubtitles;
  final VoidCallback? onRerecognizeEnglish;
  final VoidCallback? onRerecognizeChinese;
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;
  final Future<void> Function(int index, String english)? onEditEnglishLine;
  final Future<void> Function(int index, String english, String chinese)?
  onEditSubtitleLine;
  final Future<void> Function(int index, int count)? onResegment;
  final VoidCallback? onOpenSubtitleEditor;
  final Future<void> Function(int index, String note)? onEditLineNote;
  final Map<int, String> lineNotesByStartMs;
  final bool studyDarkStyle;
  final bool blindListening;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? aiSubtitleProgressValue;
  final String? aiSubtitleProgressText;
  final String? aiSubtitlePreviewText;
  final String? aiSubtitleErrorText;
  final VoidCallback? onGenerateAiSubtitles;
  final String? bilingualPipelineLabel;
  final double? bilingualPipelineProgressValue;
  final bool showAiCompleteButton;
  final VoidCallback? onAiComplete;
  final VoidCallback? onCancelBilingualPipeline;
  final VoidCallback? onDictionaryOpened;
  final VoidCallback? onDictionaryClosed;

  @override
  State<PlayerTranscriptPanel> createState() => _PlayerTranscriptPanelState();
}

class _PlayerTranscriptPanelState extends State<PlayerTranscriptPanel> {
  bool _showCurrentOnly = false;

  /// Which chunk/phrase/vocab marks stay highlighted in the transcript list.
  Set<SubtitleChunkKind> _enabledChunkKinds = Set<SubtitleChunkKind>.of(
    SubtitleChunkKind.values,
  );

  void _toggleChunkKind(SubtitleChunkKind kind) {
    setState(() {
      if (_enabledChunkKinds.contains(kind)) {
        _enabledChunkKinds = Set<SubtitleChunkKind>.of(_enabledChunkKinds)
          ..remove(kind);
      } else {
        _enabledChunkKinds = Set<SubtitleChunkKind>.of(_enabledChunkKinds)
          ..add(kind);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget list = PlayerSubtitleList(
      lines: widget.lines,
      episodeId: widget.episodeId,
      activeIndex: widget.activeIndex,
      timelineFollowEpoch: widget.timelineFollowEpoch,
      locateEpoch: widget.locateEpoch,
      subtitleMode: widget.subtitleMode,
      subtitleLetterCase: widget.subtitleLetterCase,
      showCurrentOnly: !widget.studyDarkStyle && _showCurrentOnly,
      currentWordIndex: widget.currentWordIndex,
      fontScale: widget.fontScale,
      highlightWords: widget.highlightWords,
      subtitleWordHighlightStyle: widget.subtitleWordHighlightStyle,
      subtitleWordHighlightBorderWidth: widget.subtitleWordHighlightBorderWidth,
      savedVocabularyWords: widget.savedVocabularyWords,
      learnedVocabularyWords: widget.learnedVocabularyWords,
      keyVocabularyWords: widget.keyVocabularyWords,
      chunkHighlighter: widget.chunkHighlighter,
      enabledChunkKinds: _enabledChunkKinds,
      onToggleChunkKind: _toggleChunkKind,
      // Toolbar actions live on StudyBottomControls; keep mid-row empty.
      showInlineToolbarActions: false,
      onCollectWord: widget.onCollectWord,
      onCollectWordAtTime: widget.onCollectWordAtTime,
      onFavoriteWord: widget.onFavoriteWord,
      onTapLine: widget.onTapLine,
      onBookmarkLine: widget.onBookmarkLine,
      isLineBookmarked: widget.isLineBookmarked,
      onLoopFromLine: widget.onLoopFromLine,
      onDictationLine: widget.onDictationLine,
      onAiExplain: widget.onAiExplain,
      loopingLineIndex: widget.loopingLineIndex,
      isPlaying: widget.isPlaying,
      onTogglePlaying: widget.onTogglePlaying,
      onPronounce: widget.onPronounce,
      onAssessLine: widget.onAssessLine,
      pronunciationUnavailableReasonForLine:
          widget.pronunciationUnavailableReasonForLine,
      onRegenerateAiSubtitles: widget.onRegenerateAiSubtitles,
      onResetEpisodeSubtitles: widget.onResetEpisodeSubtitles,
      onRerecognizeEnglish: widget.onRerecognizeEnglish,
      onRerecognizeChinese: widget.onRerecognizeChinese,
      onDeleteAiSubtitles: widget.onDeleteAiSubtitles,
      onRegenerateAiLine: widget.onRegenerateAiLine,
      onEditEnglishLine: widget.onEditEnglishLine,
      onEditSubtitleLine: widget.onEditSubtitleLine,
      onResegment: widget.onResegment,
      onOpenSubtitleEditor: widget.onOpenSubtitleEditor,
      onEditLineNote: widget.onEditLineNote,
      lineNotesByStartMs: widget.lineNotesByStartMs,
      studyDarkStyle: widget.studyDarkStyle,
      blindListening: widget.blindListening,
      showAiGenerateSubtitles: widget.showAiGenerateSubtitles,
      generatingAiSubtitles: widget.generatingAiSubtitles,
      aiSubtitleProgressValue: widget.aiSubtitleProgressValue,
      aiSubtitleProgressText: widget.aiSubtitleProgressText,
      aiSubtitlePreviewText: widget.aiSubtitlePreviewText,
      aiSubtitleErrorText: widget.aiSubtitleErrorText,
      onGenerateAiSubtitles: widget.onGenerateAiSubtitles,
      bilingualPipelineLabel: widget.bilingualPipelineLabel,
      bilingualPipelineProgressValue: widget.bilingualPipelineProgressValue,
      showAiCompleteButton: widget.showAiCompleteButton,
      onAiComplete: widget.onAiComplete,
      onCancelBilingualPipeline: widget.onCancelBilingualPipeline,
      onDictionaryOpened: widget.onDictionaryOpened,
      onDictionaryClosed: widget.onDictionaryClosed,
      fragmentsBySentenceStartMs: widget.fragmentsBySentenceStartMs,
    );

    if (widget.studyDarkStyle) {
      return list;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PanelHeader(
          showCurrentOnly: _showCurrentOnly,
          onViewChanged: (bool showCurrentOnly) {
            setState(() {
              _showCurrentOnly = showCurrentOnly;
            });
          },
        ),
        const SizedBox(height: 12),
        Expanded(child: list),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.showCurrentOnly,
    required this.onViewChanged,
  });

  final bool showCurrentOnly;
  final ValueChanged<bool> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final bool dark = AppDesignTokens.isDark;
    final Color titleInk =
        dark ? AppDesignTokens.textPrimary : const Color(0xFF143528);
    final Color bodyInk =
        dark ? AppDesignTokens.textSecondary : const Color(0xFF3F5B4C);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: dark
            ? AppDesignTokens.selectedSurface
            : const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark ? AppDesignTokens.borderGray : const Color(0xFFCCFBF1),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '逐句精听',
                  style: TextStyle(
                    color: titleInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点句子定位播放，点单词查看释义',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bodyInk,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TranscriptViewSwitch(
            showCurrentOnly: showCurrentOnly,
            onChanged: onViewChanged,
          ),
        ],
      ),
    );
  }
}

class _TranscriptViewSwitch extends StatelessWidget {
  const _TranscriptViewSwitch({
    required this.showCurrentOnly,
    required this.onChanged,
  });

  final bool showCurrentOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: SegmentedButton<bool>(
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(value: true, label: Text('单句')),
          ButtonSegment<bool>(value: false, label: Text('完整')),
        ],
        selected: <bool>{showCurrentOnly},
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: const WidgetStatePropertyAll<Color>(
            Color(0xFF143528),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle>(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
        onSelectionChanged: (Set<bool> selected) {
          onChanged(selected.single);
        },
      ),
    );
  }
}
