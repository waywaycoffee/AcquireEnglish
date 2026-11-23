import 'package:flutter/material.dart';

import '../../data/dictation_queue_provider.dart';
import '../../domain/dictation_diff.dart';
import '../player_mock_state.dart';
import 'study_shell_tokens.dart';

/// Shadow Talk–style dictation: input, hint/submit, sentence audio + prev/next.
class StudyDictationTab extends StatefulWidget {
  const StudyDictationTab({
    required this.line,
    required this.hasLine,
    required this.isPlaying,
    required this.onReplay,
    required this.onPrevious,
    required this.onNext,
    required this.onMarkDifficult,
    required this.onAddToQueue,
    this.queue = const <DictationQueueItem>[],
    this.queueIndex = 0,
    this.onSelectQueueIndex,
    this.onClearQueue,
    this.usingQueue = false,
    this.suggestedSpeed = '0.8×',
    this.hardsubMosaicEnabled = false,
    this.onToggleHardsubMosaic,
    this.onDictationResult,
    this.onEpisodeTest,
    super.key,
  });

  final PlayerSubtitleLine line;
  final bool hasLine;
  final bool isPlaying;
  final VoidCallback onReplay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onMarkDifficult;
  final VoidCallback onAddToQueue;
  final List<DictationQueueItem> queue;
  final int queueIndex;
  final ValueChanged<int>? onSelectQueueIndex;
  final VoidCallback? onClearQueue;
  final bool usingQueue;
  final String suggestedSpeed;
  final bool hardsubMosaicEnabled;
  final ValueChanged<bool>? onToggleHardsubMosaic;

  /// Fired after submit with word-level diff (for FSRS / word-book enqueue).
  final void Function(DictationDiffResult result)? onDictationResult;

  /// Episode-level output check: sample subtitle lines into the dictation queue.
  final VoidCallback? onEpisodeTest;

  @override
  State<StudyDictationTab> createState() => _StudyDictationTabState();
}

class _StudyDictationTabState extends State<StudyDictationTab> {
  final TextEditingController _controller = TextEditingController();
  bool _hintShown = false;
  DictationDiffResult? _diff;

  @override
  void didUpdateWidget(covariant StudyDictationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.english != widget.line.english ||
        oldWidget.queueIndex != widget.queueIndex) {
      _controller.clear();
      _hintShown = false;
      _diff = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final DictationDiffResult diff = diffDictation(
      expected: widget.line.english,
      actual: _controller.text,
    );
    setState(() => _diff = diff);
    widget.onDictationResult?.call(diff);
  }

  String _hintText() {
    final String english = widget.line.english.trim();
    if (english.isEmpty) {
      return '暂无提示';
    }
    final List<String> words = english.split(RegExp(r'\s+'));
    if (words.length <= 2) {
      return words.first;
    }
    return '${words.take(2).join(' ')} …';
  }

  Color _markColor(StudyShellColors shell, DictationTokenKind kind) {
    switch (kind) {
      case DictationTokenKind.correct:
        return shell.highlight;
      case DictationTokenKind.missing:
        return Colors.orangeAccent;
      case DictationTokenKind.extra:
        return Colors.redAccent;
      case DictationTokenKind.wrong:
        return const Color(0xFFE67E22);
    }
  }

  String _markLabel(DictationTokenMark mark) {
    switch (mark.kind) {
      case DictationTokenKind.correct:
        return mark.expected;
      case DictationTokenKind.missing:
        return '[漏:${mark.expected}]';
      case DictationTokenKind.extra:
        return '[多:${mark.actual}]';
      case DictationTokenKind.wrong:
        return '[错:${mark.actual}→${mark.expected}]';
    }
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    if (!widget.hasLine) {
      return Center(
        child: Text(
          '没有可听写的句子。请先加载字幕或语音识别生成字幕。',
          textAlign: TextAlign.center,
          style: TextStyle(color: shell.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: <Widget>[
        if (widget.onEpisodeTest != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey<String>('dictation-episode-test'),
              onPressed: widget.onEpisodeTest,
              icon: const Icon(Icons.quiz_outlined, size: 16),
              label: const Text('本集测试'),
            ),
          ),
        if (widget.onToggleHardsubMosaic != null) ...<Widget>[
          SwitchListTile(
            key: const ValueKey<String>('dictation-hardsub-mosaic'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              '遮挡硬字幕',
              style: TextStyle(
                color: shell.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              '拉出马赛克框盖住视频里的字幕',
              style: TextStyle(color: shell.textSecondary, fontSize: 12),
            ),
            value: widget.hardsubMosaicEnabled,
            activeThumbColor: shell.accent,
            onChanged: widget.onToggleHardsubMosaic,
          ),
          const SizedBox(height: 8),
        ],
        if (widget.queue.isNotEmpty) ...<Widget>[
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.queue.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (BuildContext context, int index) {
                final DictationQueueItem item = widget.queue[index];
                final bool selected = index == widget.queueIndex;
                return ChoiceChip(
                  key: ValueKey<String>('dictation-queue-$index'),
                  selected: selected,
                  label: Text(
                    item.difficult ? '★ ${item.startTime}' : item.startTime,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onSelected: widget.onSelectQueueIndex == null
                      ? null
                      : (_) => widget.onSelectQueueIndex!(index),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _controller,
          scrollPadding: const EdgeInsets.all(80),
          style: TextStyle(
            color: shell.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: '点击这里输入你听到的内容...',
            hintStyle: TextStyle(color: shell.textMuted, fontSize: 16),
            border: InputBorder.none,
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: shell.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: shell.accent, width: 1.5),
            ),
          ),
        ),
        if (_hintShown) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '提示：${_hintText()}',
            style: TextStyle(
              color: shell.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_diff != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _diff!.exact ? '正确！' : '有出入：漏词 / 错词 / 多词已标出；错词会进入复习。',
            style: TextStyle(
              color: _diff!.exact ? shell.highlight : Colors.orangeAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!_diff!.exact) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final DictationTokenMark mark in _diff!.marks)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _markColor(shell, mark.kind).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _markColor(shell, mark.kind).withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      _markLabel(mark),
                      style: TextStyle(
                        color: _markColor(shell, mark.kind),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.line.english,
              style: TextStyle(
                color: shell.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
        ],
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _hintShown = true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: shell.textPrimary,
                  side: BorderSide(color: shell.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '显示提示',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: shell.highlight,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '提交',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              tooltip: '上一句',
              onPressed: widget.onPrevious,
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 32,
                color: shell.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: <Widget>[
                Material(
                  color: shell.accent,
                  shape: const CircleBorder(),
                  elevation: 4,
                  shadowColor: shell.playGlow,
                  child: InkWell(
                    key: const ValueKey<String>('dictation-play-audio'),
                    customBorder: const CircleBorder(),
                    onTap: widget.onReplay,
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(
                        widget.isPlaying
                            ? Icons.pause_rounded
                            : Icons.volume_up_rounded,
                        color: shell.accentOn,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击播放音频',
                  style: TextStyle(
                    color: shell.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '下一句',
              onPressed: widget.onNext,
              icon: Icon(
                Icons.chevron_right_rounded,
                size: 32,
                color: shell.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextButton(
              key: const ValueKey<String>('dictation-add-queue'),
              onPressed: widget.onAddToQueue,
              child: const Text('加入听写'),
            ),
            TextButton(
              key: const ValueKey<String>('dictation-mark-difficult'),
              onPressed: widget.onMarkDifficult,
              child: const Text('标记困难'),
            ),
            if (widget.onClearQueue != null)
              TextButton(
                onPressed: widget.onClearQueue,
                child: const Text('清空队列'),
              ),
          ],
        ),
      ],
    );
  }
}
