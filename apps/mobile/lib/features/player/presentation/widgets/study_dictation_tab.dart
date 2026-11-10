import 'package:flutter/material.dart';

import '../../data/dictation_queue_provider.dart';
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

  @override
  State<StudyDictationTab> createState() => _StudyDictationTabState();
}

class _StudyDictationTabState extends State<StudyDictationTab> {
  final TextEditingController _controller = TextEditingController();
  bool _hintShown = false;
  bool? _correct;

  @override
  void didUpdateWidget(covariant StudyDictationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.english != widget.line.english ||
        oldWidget.queueIndex != widget.queueIndex) {
      _controller.clear();
      _hintShown = false;
      _correct = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String expected = _normalize(widget.line.english);
    final String actual = _normalize(_controller.text);
    setState(() => _correct = expected == actual);
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

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
        if (_correct != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _correct! ? '正确！' : '再听一遍，对照原文修正。',
            style: TextStyle(
              color: _correct! ? shell.highlight : Colors.orangeAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!_correct!) ...<Widget>[
            const SizedBox(height: 6),
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
