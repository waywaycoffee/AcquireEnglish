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
    if (ready) return '当前音色 AI 朗读已就绪';
    if (state == 'missing') return '等待云端 AI 配音…';
    if (pagesTotal > 0) {
      return 'AI 配音 $percent%（$pagesReady/$pagesTotal 节）';
    }
    return 'AI 配音 $percent%';
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

  // Prefer a cheap status GET first. Re-POSTing the full novel on every shelf
  // watch used to time out and make ready Oz look "missing".
  Map<String, dynamic>? latest =
      await api.readingBookPregenStatus(docId: doc.id, voice: voice);
  final bool alreadyReady = latest != null && latest['ready'] == true;
  if (!alreadyReady) {
    latest = await api.enqueueReadingBookPregen(
          docId: doc.id,
          text: doc.plainText,
          voice: voice,
          // Queue only — CosyVoice runs on the 5060 Ti worker, not ECS drain.
          processOnEcs: false,
        ) ??
        latest;
  }
  int lastPercent = -1;
  int lastPagesReady = -1;

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
    }

    // No ECS DashScope fallback — keep tts_worker.py running on the 5060 Ti.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!ref.mounted) return;
    latest = await api.readingBookPregenStatus(docId: doc.id, voice: voice);
  }
});
