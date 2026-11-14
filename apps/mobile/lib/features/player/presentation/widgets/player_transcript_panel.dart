import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../player_mock_state.dart';
import 'player_subtitle_list.dart';

class PlayerTranscriptPanel extends StatefulWidget {
  const PlayerTranscriptPanel({
    required this.lines,
    required this.activeIndex,
    this.timelineFollowEpoch = 0,
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    required this.subtitleWordHighlightStyle,
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
    required this.isPlaying,
    required this.onTogglePlaying,
    this.episodeId,
    this.onPronounce,
    this.onAssessLine,
    this.pronunciationUnavailableReasonForLine,
    this.onRegenerateAiSubtitles,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
    this.onEditEnglishLine,
    this.onEditSubtitleLine,
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
  final String subtitleMode;
  final String subtitleLetterCase;
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
  final void Function(String word, [String? definitionCn])? onFavoriteWord;
  final ValueChanged<int> onBookmarkLine;
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
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;
  final Future<void> Function(int index, String english)? onEditEnglishLine;
  final Future<void> Function(int index, String english, String chinese)?
  onEditSubtitleLine;
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

  @override
  Widget build(BuildContext context) {
    final Widget list = PlayerSubtitleList(
      lines: widget.lines,
      episodeId: widget.episodeId,
      activeIndex: widget.activeIndex,
      timelineFollowEpoch: widget.timelineFollowEpoch,
      subtitleMode: widget.subtitleMode,
      subtitleLetterCase: widget.subtitleLetterCase,
      showCurrentOnly: !widget.studyDarkStyle && _showCurrentOnly,
      currentWordIndex: widget.currentWordIndex,
      fontScale: widget.fontScale,
      highlightWords: widget.highlightWords,
      subtitleWordHighlightStyle: widget.subtitleWordHighlightStyle,
      subtitleWordHighlightBorderWidth: widget.subtitleWordHighlightBorderWidth,
      savedVocabularyWords: widget.savedVocabularyWords,
      keyVocabularyWords: widget.keyVocabularyWords,
      onCollectWord: widget.onCollectWord,
      onCollectWordAtTime: widget.onCollectWordAtTime,
      onFavoriteWord: widget.onFavoriteWord,
      onTapLine: widget.onTapLine,
      onBookmarkLine: widget.onBookmarkLine,
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
      onDeleteAiSubtitles: widget.onDeleteAiSubtitles,
      onRegenerateAiLine: widget.onRegenerateAiLine,
      onEditEnglishLine: widget.onEditEnglishLine,
      onEditSubtitleLine: widget.onEditSubtitleLine,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCCFBF1)),
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
                    color: AppDesignTokens.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '点句子定位播放，点单词查看释义',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
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
    return SegmentedButton<bool>(
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(value: true, label: Text('单句')),
        ButtonSegment<bool>(value: false, label: Text('完整')),
      ],
      selected: <bool>{showCurrentOnly},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      onSelectionChanged: (Set<bool> selected) {
        onChanged(selected.single);
      },
    );
  }
}
