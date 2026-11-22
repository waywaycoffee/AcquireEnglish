import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/data/acquire_api_client.dart';
import '../data/reading_tts.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

/// Long novels must finish cloud AI (TTS packs on 5060 Ti / ECS) before open.
const int kReadingLongNovelMinWords = 12000;

bool readingDocNeedsCloudPrep(ReadingDoc doc) =>
    doc.wordCount >= kReadingLongNovelMinWords &&
    doc.plainText.trim().length >= 20000;

class ReadingBookPrepStatus {
  const ReadingBookPrepStatus({
    required this.docId,
    required this.ready,
    required this.percent,
    required this.state,
    required this.pagesReady,
    required this.pagesTotal,
    this.message = '',
    this.error,
  });

  final String docId;
  final bool ready;
  final int percent;
  final String state;
  final int pagesReady;
  final int pagesTotal;
  final String message;
  final String? error;

  factory ReadingBookPrepStatus.fromJson(
    String docId,
    Map<String, dynamic> json,
  ) {
    final bool skipped = json['state'] == 'skipped' || json['long_novel'] == false;
    return ReadingBookPrepStatus(
      docId: docId,
      ready: skipped || json['ready'] == true,
      percent: skipped
          ? 100
          : ((json['percent'] as num?)?.round() ?? 0).clamp(0, 100),
      state: '${json['state'] ?? 'missing'}',
      pagesReady: (json['pages_ready'] as num?)?.round() ?? 0,
      pagesTotal: (json['pages_total'] as num?)?.round() ?? 0,
      message: '${json['message'] ?? ''}',
      error: json['error']?.toString(),
    );
  }

  String get progressLabel {
    if (ready) return 'AI 已就绪';
    if (state == 'missing') return '等待云端 AI 处理…';
    if (pagesTotal > 0) {
      return '云端 AI 处理中 $percent%（$pagesReady/$pagesTotal 节）';
    }
    return '云端 AI 处理中 $percent%';
  }
}

final readingBookPrepProvider = StreamProvider.autoDispose
    .family<ReadingBookPrepStatus, String>((Ref ref, String docId) async* {
  final ReadingDoc? doc = ref.watch(readingLibraryProvider).docById(docId);
  if (doc == null) {
    yield ReadingBookPrepStatus(
      docId: docId,
      ready: false,
      percent: 0,
      state: 'missing',
      pagesReady: 0,
      pagesTotal: 0,
      message: 'doc_missing',
    );
    return;
  }
  if (!readingDocNeedsCloudPrep(doc)) {
    yield ReadingBookPrepStatus(
      docId: docId,
      ready: true,
      percent: 100,
      state: 'skipped',
      pagesReady: 0,
      pagesTotal: 0,
      message: 'short_article',
    );
    return;
  }

  final AcquireApiClient api = ref.read(acquireApiClientProvider);
  final String voice = loadReadingTtsGender().aliyunVoiceId;

  // Kick cloud queue once (5060 Ti preferred; no phone-side synth storm).
  Map<String, dynamic>? latest = await api.enqueueReadingBookPregen(
    docId: doc.id,
    text: doc.plainText,
    voice: voice,
    processOnEcs: false,
  );
  DateTime progressAnchor = DateTime.now();
  int lastPercent = -1;
  int lastPagesReady = -1;
  bool fallbackTried = false;

  while (true) {
    latest ??= await api.readingBookPregenStatus(docId: doc.id, voice: voice);
    final ReadingBookPrepStatus status = latest == null
        ? ReadingBookPrepStatus(
            docId: doc.id,
            ready: false,
            percent: 0,
            state: 'missing',
            pagesReady: 0,
            pagesTotal: 0,
            message: 'network',
          )
        : ReadingBookPrepStatus.fromJson(doc.id, latest);
    yield status;
    if (status.ready) return;

    if (status.percent != lastPercent || status.pagesReady != lastPagesReady) {
      lastPercent = status.percent;
      lastPagesReady = status.pagesReady;
      progressAnchor = DateTime.now();
    }

    // GPU worker offline / stalled (~90s without progress) → ECS filler once.
    final bool stalled =
        DateTime.now().difference(progressAnchor) > const Duration(seconds: 90);
    if (!fallbackTried && stalled) {
      fallbackTried = true;
      latest = await api.readingBookPregenFallback(
        docId: doc.id,
        text: doc.plainText,
        voice: voice,
      );
      progressAnchor = DateTime.now();
      continue;
    }

    await Future<void>.delayed(const Duration(seconds: 3));
    if (!ref.mounted) return;
    latest = await api.readingBookPregenStatus(docId: doc.id, voice: voice);
  }
});
