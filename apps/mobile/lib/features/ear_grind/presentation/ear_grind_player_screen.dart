import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/ear_grind_controller.dart';

class EarGrindPlayerScreen extends ConsumerStatefulWidget {
  const EarGrindPlayerScreen({super.key});

  @override
  ConsumerState<EarGrindPlayerScreen> createState() =>
      _EarGrindPlayerScreenState();
}

class _EarGrindPlayerScreenState extends ConsumerState<EarGrindPlayerScreen>
    with WidgetsBindingObserver {
  VideoController? _video;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = ref.read(earGrindProvider.notifier).player;
      if (player != null) {
        setState(() => _video = VideoController(player));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final EarGrindController c = ref.read(earGrindProvider.notifier);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Keep playing; switch to audio-only so video decode stops under lock.
      unawaited(c.onAppLifecycle(AppLifecycleHint.background));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(c.onAppLifecycle(AppLifecycleHint.foreground));
      final player = c.player;
      if (player != null && _video == null) {
        setState(() => _video = VideoController(player));
      }
    }
  }

  String _fmt(Duration d) {
    final int m = d.inMinutes;
    final int s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final EarGrindState st = ref.watch(earGrindProvider);
    final EarGrindSession? session = st.session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('磨耳朵')),
        body: const Center(child: Text('尚未选择媒体')),
      );
    }

    final bool showVideo = session.isVideo && !st.audioOnly && _video != null;
    final double maxMs =
        st.duration.inMilliseconds <= 0 ? 1 : st.duration.inMilliseconds.toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: <Widget>[
          IconButton(
            tooltip: '结束',
            onPressed: () async {
              await ref.read(earGrindProvider.notifier).stopAndClose();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black),
              child: showVideo
                  ? Video(controller: _video!)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.headphones,
                            size: 64,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            st.audioOnly
                                ? '仅声音模式 · 息屏可继续听'
                                : '音频播放中',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          if (st.error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(st.error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 16),
          Slider(
            value: st.position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
            max: maxMs,
            onChanged: (double v) {
              unawaited(
                ref
                    .read(earGrindProvider.notifier)
                    .seek(Duration(milliseconds: v.round())),
              );
            },
          ),
          Row(
            children: <Widget>[
              Text(_fmt(st.position)),
              const Spacer(),
              Text(_fmt(st.duration)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton.filled(
                iconSize: 42,
                onPressed: () =>
                    unawaited(ref.read(earGrindProvider.notifier).togglePlay()),
                icon: Icon(st.playing ? Icons.pause : Icons.play_arrow),
              ),
            ],
          ),
          SwitchListTile(
            title: const Text('循环播放'),
            value: st.loop,
            onChanged: (bool v) =>
                unawaited(ref.read(earGrindProvider.notifier).setLoop(v)),
          ),
          SwitchListTile(
            title: const Text('仅声音（省电 / 锁屏推荐）'),
            subtitle: const Text('关闭画面解码，息屏后仍继续播'),
            value: st.audioOnly,
            onChanged: (bool v) =>
                unawaited(ref.read(earGrindProvider.notifier).setAudioOnly(v)),
          ),
          const Text('语速', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 8,
            children: <double>[0.75, 1.0, 1.25, 1.5].map((double s) {
              final bool on = (st.speed - s).abs() < 0.01;
              return ChoiceChip(
                label: Text('${s}x'),
                selected: on,
                onSelected: (_) =>
                    unawaited(ref.read(earGrindProvider.notifier).setSpeed(s)),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            '提示：把手机锁屏或切到后台后，声音会继续；视频画面会自动关掉只留声音。',
            style: TextStyle(color: Theme.of(context).hintColor, height: 1.4),
          ),
        ],
      ),
    );
  }
}
