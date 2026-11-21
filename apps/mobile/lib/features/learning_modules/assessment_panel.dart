import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../authentication/presentation/auth_session.dart';
import '../player/data/pronunciation_providers.dart';
import '../sync/data/acquire_api_client.dart';

class AssessmentPanel extends ConsumerStatefulWidget {
  const AssessmentPanel({super.key, required this.reference});
  final String reference;
  @override
  ConsumerState<AssessmentPanel> createState() => _AssessmentPanelState();
}

class _AssessmentPanelState extends ConsumerState<AssessmentPanel> {
  PronunciationMicrophone? mic;
  StreamSubscription<Uint8List>? subscription;
  final bytes = BytesBuilder();
  Timer? limit;
  bool recording = false, busy = false;
  String? error;
  Map<String, dynamic>? result;
  int generation = 0;
  @override
  void dispose() {
    generation++;
    limit?.cancel();
    unawaited(subscription?.cancel());
    unawaited(mic?.cancel());
    unawaited(mic?.dispose());
    super.dispose();
  }

  Future<void> start() async {
    if (busy || recording) return;
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() => error = '请先登录，再使用腾讯云评测');
      return;
    }
    final epoch = ++generation;
    setState(() {
      busy = true;
      error = null;
      result = null;
    });
    try {
      final status = await ref
          .read(acquireApiClientProvider)
          .assessmentStatus();
      if (!mounted || epoch != generation) return;
      if (status['configured'] != true) throw StateError('腾讯云评测尚未配置，请联系管理员');
      mic ??= ref.read(pronunciationMicrophoneFactoryProvider)();
      if (!await mic!.requestPermission())
        throw StateError('没有麦克风权限，可在系统设置中开启');
      if (!mounted || epoch != generation) return;
      bytes.clear();
      subscription = (await mic!.start()).listen(
        bytes.add,
        onError: (Object e) {
          if (mounted) setState(() => error = '录音失败，请重试');
        },
      );
      setState(() => recording = true);
      limit = Timer(const Duration(seconds: 60), finish);
    } catch (e) {
      if (mounted && epoch == generation)
        setState(
          () => error = e is StateError ? '${e.message}' : '评测服务暂不可用，请重试',
        );
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  Future<void> finish() async {
    if (!recording || busy) return;
    limit?.cancel();
    final epoch = generation;
    setState(() {
      recording = false;
      busy = true;
    });
    try {
      await mic!.stop();
      await subscription?.cancel();
      subscription = null;
      final pcm = bytes.takeBytes();
      if (pcm.length < 6400) throw StateError('录音太短，请完整朗读后重试');
      final next = await ref
          .read(acquireApiClientProvider)
          .evaluateRecording(widget.reference, base64Encode(pcm));
      if (mounted && epoch == generation) setState(() => result = next);
    } catch (e) {
      if (mounted && epoch == generation)
        setState(
          () => error = e is StateError
              ? '${e.message}'
              : e is DioException && e.response?.data is Map
              ? '${(e.response!.data as Map)['detail']}'
              : '评测失败，请重录或稍后重试',
        );
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authSessionProvider.select((s) => s.accessToken), (_, __) {
      generation++;
      limit?.cancel();
      unawaited(mic?.cancel());
      unawaited(subscription?.cancel());
      setState(() {
        recording = false;
        busy = false;
        result = null;
        error = null;
      });
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('腾讯云真实朗读评测', style: Theme.of(context).textTheme.titleMedium),
            Text('朗读：${widget.reference}'),
            const Text('点击开始即同意将本次录音经服务器发送腾讯云评测。最长60秒，结束后展示服务返回的成绩。'),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : recording
                  ? finish
                  : start,
              icon: Icon(recording ? Icons.stop : Icons.mic),
              label: Text(
                busy
                    ? '处理中…'
                    : recording
                    ? '结束录音并评测'
                    : '开始录音',
              ),
            ),
            if (error != null) Text(error!),
            if (result != null) ...[
              Text('总分：${result!['score'] ?? '未返回'} / 100'),
              Text(
                '发音准确度：${result!['accuracy'] ?? '未返回'} · 流利度：${result!['fluency'] ?? '未返回'} · 完整度：${result!['completion'] ?? '未返回'}',
              ),
              for (final w in (result!['words'] as List<dynamic>? ?? []))
                ExpansionTile(
                  title: Text('${w['word']} · ${w['accuracy'] ?? '未返回'}'),
                  children: [
                    for (final p in (w['phones'] as List<dynamic>? ?? []))
                      ListTile(
                        title: Text(
                          '${p['reference_phone']?.toString().isNotEmpty == true ? p['reference_phone'] : p['phone']}',
                        ),
                        trailing: Text('${p['accuracy'] ?? '未返回'}'),
                      ),
                  ],
                ),
              const Text('分数与音素明细来自腾讯云；未返回的指标不作推算。'),
            ],
          ],
        ),
      ),
    );
  }
}
