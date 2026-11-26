import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/k12_textbook_audio_cache.dart';
import '../domain/k12_pdf_audio_sync.dart';
import '../domain/k12_textbook_media.dart';

class K12TextbookStudyScreen extends ConsumerStatefulWidget {
  const K12TextbookStudyScreen({
    required this.mediaBookId,
    this.catalogTitle = '',
    super.key,
  });

  final String mediaBookId;
  final String catalogTitle;

  @override
  ConsumerState<K12TextbookStudyScreen> createState() =>
      _K12TextbookStudyScreenState();
}

class _K12TextbookStudyScreenState
    extends ConsumerState<K12TextbookStudyScreen> {
  K12TextbookMedia? _book;
  String? _error;
  bool _loading = true;
  bool _caching = false;
  bool _aligning = false;
  bool _followPages = true;
  int? _playingSeq;
  bool _playing = false;
  int _pageNumber = 1;
  K12PdfAudioSyncMap _sync = const K12PdfAudioSyncMap(
    pageToSeq: <int, int>{},
    seqToStartPage: <int, int>{},
  );
  late final Player _player;
  late final PdfViewerController _pdfController;
  StreamSubscription<bool>? _completedSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onPdfChanged);
    _player.stream.playing.listen((bool value) {
      if (!mounted) return;
      setState(() => _playing = value);
    });
    _completedSub = _player.stream.completed.listen((bool done) {
      if (!done || !mounted) return;
      unawaited(_onTrackCompleted());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _pdfController.removeListener(_onPdfChanged);
    unawaited(_completedSub?.cancel() ?? Future<void>.value());
    unawaited(_player.dispose());
    super.dispose();
  }

  void _onPdfChanged() {
    final int? page = _pdfController.pageNumber;
    if (page == null || page == _pageNumber) return;
    _pageNumber = page;
    if (!_followPages || _sync.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    final int? seq = _sync.seqForPage(page);
    if (seq == null) {
      if (mounted) setState(() {});
      return;
    }
    if (seq == _playingSeq) {
      if (mounted) setState(() {});
      return;
    }
    final K12TextbookLesson? lesson = _lessonBySeq(seq);
    if (lesson == null) return;
    unawaited(_play(lesson, fromPageSync: true));
  }

  K12TextbookLesson? _lessonBySeq(int seq) {
    final K12TextbookMedia? book = _book;
    if (book == null) return null;
    for (final K12TextbookLesson lesson in book.lessons) {
      if (lesson.seq == seq) return lesson;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? raw = await ref
          .read(acquireApiClientProvider)
          .getReadingTextbook(widget.mediaBookId);
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _loading = false;
          _error = '服务器上还没有这本教材的 PDF / 音频包';
        });
        return;
      }
      final K12TextbookMedia book = K12TextbookMedia.fromJson(raw);
      setState(() {
        _book = book;
        _loading = false;
      });
      unawaited(_alignAudioToPdf(book));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _alignAudioToPdf(K12TextbookMedia book) async {
    final String pdfUrl = book.pdfUrl.trim();
    final Uri? uri = Uri.tryParse(pdfUrl);
    if (uri == null || book.lessons.isEmpty) return;
    if (mounted) setState(() => _aligning = true);
    try {
      final PdfDocument doc = await PdfDocument.openUri(uri);
      try {
        final List<String> texts = <String>[];
        for (final PdfPage page in doc.pages) {
          final PdfPageRawText? raw = await page.loadText();
          texts.add(raw?.fullText ?? '');
        }
        final K12PdfAudioSyncMap sync = buildK12PdfAudioSyncMap(
          lessons: book.lessons,
          pageTexts: texts,
        );
        if (!mounted) return;
        setState(() {
          _sync = sync;
          _aligning = false;
        });
        if (_followPages && !sync.isEmpty) {
          final int page = _pdfController.pageNumber ?? 1;
          final int? seq = sync.seqForPage(page);
          final K12TextbookLesson? lesson =
              seq == null ? null : _lessonBySeq(seq);
          if (lesson != null) {
            unawaited(_play(lesson, fromPageSync: true));
          }
        }
      } finally {
        unawaited(doc.dispose());
      }
    } catch (_) {
      if (mounted) setState(() => _aligning = false);
    }
  }

  Future<void> _play(
    K12TextbookLesson lesson, {
    bool fromPageSync = false,
  }) async {
    if (_caching && fromPageSync) return;
    setState(() {
      _playingSeq = lesson.seq;
      _caching = true;
    });
    try {
      final File cached = await ensureK12TextbookAudioCached(
        client: ref.read(acquireApiClientProvider),
        bookId: widget.mediaBookId,
        seq: lesson.seq,
        fallbackAudioUrl: lesson.audioUrl,
      );
      if (!mounted) return;
      // Another page flip may have requested a newer track.
      if (_playingSeq != lesson.seq) {
        setState(() => _caching = false);
        return;
      }
      setState(() => _caching = false);
      await _player.open(Media(cached.uri.toString()));
      await _player.play();
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _caching = false;
        if (_playingSeq == lesson.seq) _playingSeq = null;
      });
      if (!fromPageSync) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音频下载失败，请重试：$error')),
        );
      }
    }
  }

  Future<void> _toggle(K12TextbookLesson lesson) async {
    if (_caching) return;
    if (_playingSeq == lesson.seq && _playing) {
      await _player.pause();
      return;
    }
    if (_playingSeq == lesson.seq && !_playing) {
      await _player.play();
      return;
    }
    await _play(lesson);
  }

  Future<void> _onTrackCompleted() async {
    setState(() {
      _playing = false;
    });
    if (!_followPages || _sync.isEmpty) {
      setState(() => _playingSeq = null);
      return;
    }
    final int page = _pageNumber;
    final List<int> onPage = _sync.seqsStartingOnPage(page);
    final int? current = _playingSeq;
    if (current == null) return;
    final int idx = onPage.indexOf(current);
    if (idx >= 0 && idx + 1 < onPage.length) {
      final K12TextbookLesson? next = _lessonBySeq(onPage[idx + 1]);
      if (next != null) {
        await _play(next, fromPageSync: true);
        return;
      }
    }
    setState(() => _playingSeq = null);
  }

  Future<void> _showAudioSheet() async {
    final K12TextbookMedia? book = _book;
    if (book == null || book.lessons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这本教材还没有课次音频')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppDesignTokens.appWhite,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: _AudioLessonList(
              book: book,
              caching: _caching,
              playingSeq: _playingSeq,
              playing: _playing,
              onToggle: _toggle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final K12TextbookMedia? book = _book;
    final String title = (book?.displayTitle.isNotEmpty ?? false)
        ? book!.displayTitle
        : (widget.catalogTitle.isEmpty ? '英语教材' : widget.catalogTitle);
    final String pdfUrl = book?.pdfUrl.trim() ?? '';
    final Uri? pdfUri = pdfUrl.isEmpty ? null : Uri.tryParse(pdfUrl);
    final K12TextbookLesson? current =
        _playingSeq == null ? null : _lessonBySeq(_playingSeq!);

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.softWhite,
        title: Text(title),
        actions: <Widget>[
          if (book != null && book.lessons.isNotEmpty)
            IconButton(
              tooltip: _followPages ? '翻页跟读：开' : '翻页跟读：关',
              onPressed: () {
                setState(() => _followPages = !_followPages);
                if (_followPages) {
                  final int? seq = _sync.seqForPage(_pageNumber);
                  final K12TextbookLesson? lesson =
                      seq == null ? null : _lessonBySeq(seq);
                  if (lesson != null) unawaited(_play(lesson, fromPageSync: true));
                }
              },
              icon: Icon(
                _followPages
                    ? Icons.sync_rounded
                    : Icons.sync_disabled_rounded,
                color: _followPages
                    ? AppDesignTokens.brandGreen
                    : AppDesignTokens.textSecondary,
              ),
            ),
          if (book != null && book.lessons.isNotEmpty)
            TextButton(
              onPressed: _showAudioSheet,
              child: Text(
                '课次',
                style: TextStyle(color: AppDesignTokens.textPrimary),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppDesignTokens.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : pdfUri == null
          ? Center(
              child: Text(
                '这本教材还没有 PDF',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
            )
          : Column(
              children: <Widget>[
                if (_aligning || _caching || current != null)
                  Material(
                    color: AppDesignTokens.appWhite,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: <Widget>[
                          if (_aligning || _caching)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (_aligning || _caching) const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _aligning
                                  ? '正在对齐课次音频与页码…'
                                  : _caching
                                  ? '正在下载本页音频…'
                                  : '第 $_pageNumber 页 · ${current?.displayTitle ?? ''}',
                              style: TextStyle(
                                color: AppDesignTokens.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (_playing)
                            IconButton(
                              onPressed: () => unawaited(_player.pause()),
                              icon: Icon(
                                Icons.pause_circle_filled,
                                color: AppDesignTokens.brandGreen,
                              ),
                            )
                          else if (current != null)
                            IconButton(
                              onPressed: () => unawaited(_player.play()),
                              icon: Icon(
                                Icons.play_circle_fill,
                                color: AppDesignTokens.brandGreen,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: PdfViewer.uri(
                    pdfUri,
                    controller: _pdfController,
                    params: PdfViewerParams(
                      backgroundColor: AppDesignTokens.softWhite,
                      loadingBannerBuilder:
                          (
                            BuildContext context,
                            int bytesDownloaded,
                            int? totalBytes,
                          ) {
                            final double? progress =
                                totalBytes == null || totalBytes <= 0
                                ? null
                                : bytesDownloaded / totalBytes;
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  SizedBox(
                                    width: 160,
                                    child: LinearProgressIndicator(
                                      value: progress,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '正在加载课本 PDF…',
                                    style: TextStyle(
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                      errorBannerBuilder:
                          (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                            PdfDocumentRef documentRef,
                          ) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'PDF 打开失败：$error',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ),
                            );
                          },
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: book != null && book.lessons.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _showAudioSheet,
              backgroundColor: AppDesignTokens.brandGreen,
              foregroundColor: AppDesignTokens.onAccent,
              icon: Icon(
                _playing ? Icons.pause_rounded : Icons.headphones_rounded,
              ),
              label: Text(_followPages ? '跟读中' : '听课'),
            )
          : null,
    );
  }
}

class _AudioLessonList extends StatelessWidget {
  const _AudioLessonList({
    required this.book,
    required this.caching,
    required this.playingSeq,
    required this.playing,
    required this.onToggle,
  });

  final K12TextbookMedia book;
  final bool caching;
  final int? playingSeq;
  final bool playing;
  final Future<void> Function(K12TextbookLesson lesson) onToggle;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<K12TextbookLesson>> grouped =
        <String, List<K12TextbookLesson>>{};
    for (final K12TextbookLesson lesson in book.lessons) {
      final String key = lesson.unitLabel.isEmpty ? '其他' : lesson.unitLabel;
      grouped.putIfAbsent(key, () => <K12TextbookLesson>[]).add(lesson);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: <Widget>[
        Text(
          '${book.edition} · ${book.volume} · ${book.lessons.length} 课音频',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '翻页会自动播放本页课次；也可在这里手动点选。',
          style: TextStyle(color: AppDesignTokens.textSecondary, height: 1.35),
        ),
        if (caching) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 4),
          Text(
            '正在下载到手机…',
            style: TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        for (final MapEntry<String, List<K12TextbookLesson>> entry
            in grouped.entries) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              entry.key,
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final K12TextbookLesson lesson in entry.value)
            Card(
              color: AppDesignTokens.appWhite,
              child: ListTile(
                title: Text(
                  lesson.displayTitle,
                  style: TextStyle(color: AppDesignTokens.textPrimary),
                ),
                subtitle: Text(
                  lesson.kind,
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
                trailing: Icon(
                  playingSeq == lesson.seq && playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: AppDesignTokens.brandGreen,
                  size: 32,
                ),
                onTap: () => unawaited(onToggle(lesson)),
              ),
            ),
        ],
      ],
    );
  }
}
