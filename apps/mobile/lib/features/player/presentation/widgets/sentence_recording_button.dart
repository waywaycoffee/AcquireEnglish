import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/dub_session_store.dart';
import '../../data/pronunciation_providers.dart';
import '../player_mock_state.dart';

class SentenceRecordingButton extends ConsumerStatefulWidget {
  const SentenceRecordingButton({
    super.key,
    required this.episodeId,
    required this.line,
    required this.pauseVideo,
  });
  final String episodeId;
  final PlayerSubtitleLine line;
  final VoidCallback pauseVideo;
  @override
  ConsumerState<SentenceRecordingButton> createState() => _RecordingState();
}

class _RecordingState extends ConsumerState<SentenceRecordingButton> {
  PronunciationPreviewPlayer? _player;
  @override
  void dispose() {
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: DubSessionStore.instance.revision,
    builder: (BuildContext context, int revision, Widget? child) =>
        FutureBuilder<List<DubTake>>(
          future: DubSessionStore.instance.loadTakes(
            widget.episodeId,
            history: true,
          ),
          builder: (BuildContext context, AsyncSnapshot<List<DubTake>> snapshot) {
            DubTake? take;
            for (final DubTake item in snapshot.data ?? <DubTake>[]) {
              if (item.startMs == widget.line.startMs &&
                  item.endMs == widget.line.endMs &&
                  item.english == widget.line.english) {
                take = item;
              }
            }
            if (take == null) return const SizedBox.shrink();
            final DubTake recording = take;
            final List<DubTake> versions = (snapshot.data ?? <DubTake>[])
                .where(
                  (DubTake item) =>
                      item.startMs == widget.line.startMs &&
                      item.endMs == widget.line.endMs &&
                      item.english == widget.line.english,
                )
                .toList();
            return Wrap(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.graphic_eq, size: 18),
                  tooltip: '播放我的录音',
                  onPressed: () async {
                    widget.pauseVideo();
                    _player ??= ref.read(
                      pronunciationPreviewPlayerFactoryProvider,
                    )();
                    try {
                      await _player!.stop();
                      await _player!.playLocalFile(recording.userWavPath);
                    } catch (_) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('录音播放失败，请重试')),
                        );
                    }
                  },
                ),
                if (versions.length > 1)
                  PopupMenuButton<DubTake>(
                    tooltip: '选择配音版本',
                    icon: const Icon(Icons.history),
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<DubTake>>[
                          for (int i = 0; i < versions.length; i++)
                            PopupMenuItem<DubTake>(
                              value: versions[i],
                              child: Text(
                                '第${i + 1}遍 · ${versions[i].scorePercent ?? "未评分"}',
                              ),
                            ),
                        ],
                    onSelected: (DubTake value) async {
                      await _player?.stop();
                      await DubSessionStore.instance.saveTake(value);
                    },
                  ),
              ],
            );
          },
        ),
  );
}
