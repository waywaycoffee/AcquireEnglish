import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../authentication/presentation/auth_session.dart';
import '../player/data/pronunciation_providers.dart';
import '../shared/presentation/pad/app_design_tokens.dart';
import '../sync/data/acquire_api_client.dart';

/// Formats 0–100 scores for display (integer when whole, else 1 decimal).
String formatOralScore100(Object? value) {
  final double? n = _asFinite(value);
  if (n == null) return '未返回';
  final double clamped = n.clamp(0, 100);
  final double one = (clamped * 10).roundToDouble() / 10;
  if ((one - one.roundToDouble()).abs() < 0.05) return '${one.round()}';
  return one.toStringAsFixed(1);
}

/// Formats fluency/completeness (0–1 or 0–100) as a percent with ≤1 decimal.
String formatOralRatioPercent(Object? value) {
  final double? n = _asFinite(value);
  if (n == null) return '未返回';
  final double pct = (n <= 1.000001 ? n * 100 : n).clamp(0, 100);
  final double one = (pct * 10).roundToDouble() / 10;
  if ((one - one.roundToDouble()).abs() < 0.05) return '${one.round()}%';
  return '${one.toStringAsFixed(1)}%';
}

double? _asFinite(Object? value) {
  if (value is! num) return null;
  final double n = value.toDouble();
  return n.isFinite ? n : null;
}

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
      setState(() => error = '请先登录后再跟读评测');
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
      if (status['configured'] != true) {
        throw StateError('跟读评测尚未配置，请联系管理员');
      }
      mic ??= ref.read(pronunciationMicrophoneFactoryProvider)();
      if (!await mic!.requestPermission()) {
        throw StateError('没有麦克风权限，可在系统设置中开启');
      }
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
      if (mounted && epoch == generation) {
        setState(
          () => error = e is StateError ? '${e.message}' : '评测服务暂不可用，请重试',
        );
      }
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
      if (mounted && epoch == generation) {
        setState(
          () => error = e is StateError
              ? '${e.message}'
              : e is DioException && e.response?.data is Map
              ? _learnerFacingDetail((e.response!.data as Map)['detail'])
              : '评测失败，请重录或稍后重试',
        );
      }
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  static String _learnerFacingDetail(Object? detail) {
    final String raw = '$detail'.trim();
    if (raw.isEmpty) return '评测失败，请重录或稍后重试';
    if (raw.contains('腾讯云')) {
      if (raw.contains('尚未配置')) return '跟读评测尚未配置，请联系管理员';
      if (raw.contains('暂时不可用') || raw.contains('未成功')) {
        return '评测暂时不可用，请稍后重试';
      }
      return '评测失败，请重录或稍后重试';
    }
    return raw;
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
    final theme = Theme.of(context);
    final Color border = AppDesignTokens.borderGray.withValues(alpha: 0.85);
    final Color surface = AppDesignTokens.appWhite;
    final Color muted = AppDesignTokens.textSecondary;
    final Color primary = AppDesignTokens.textPrimary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '跟读评测',
              style: theme.textTheme.titleMedium?.copyWith(
                color: primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '朗读「${widget.reference}」',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : recording
                    ? finish
                    : start,
                icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(
                  busy
                      ? '处理中…'
                      : recording
                      ? '结束并评分'
                      : '开始录音',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              _ScoreSummary(result: result!),
              const SizedBox(height: 8),
              for (final w in (result!['words'] as List<dynamic>? ?? []))
                _WordScoreTile(word: w is Map ? w : const <String, dynamic>{}),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreSummary extends StatelessWidget {
  const _ScoreSummary({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String total = formatOralScore100(result['score']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              total,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '/ 100',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppDesignTokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricChip(
              label: '准确度',
              value: formatOralScore100(result['accuracy']),
            ),
            _MetricChip(
              label: '流利度',
              value: formatOralRatioPercent(result['fluency']),
            ),
            _MetricChip(
              label: '完整度',
              value: formatOralRatioPercent(result['completion']),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppDesignTokens.softGray.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WordScoreTile extends StatelessWidget {
  const _WordScoreTile({required this.word});
  final Map<dynamic, dynamic> word;

  @override
  Widget build(BuildContext context) {
    final String label = '${word['word'] ?? ''}';
    final String score = formatOralScore100(word['accuracy']);
    final List<dynamic> phones = word['phones'] as List<dynamic>? ?? const [];
    if (phones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          '$label · $score',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppDesignTokens.textPrimary,
          ),
        ),
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: Text(
          '$label · $score',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        children: [
          for (final p in phones)
            if (p is Map)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(
                  '${p['reference_phone']?.toString().isNotEmpty == true ? p['reference_phone'] : p['phone'] ?? ''}',
                  style: TextStyle(color: AppDesignTokens.textPrimary),
                ),
                trailing: Text(
                  formatOralScore100(p['accuracy']),
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
