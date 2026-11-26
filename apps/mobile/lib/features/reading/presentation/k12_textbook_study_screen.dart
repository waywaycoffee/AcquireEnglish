import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/k12_textbook_audio_cache.dart';
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
  int? _playingSeq;
  bool _playing = false;
  late final Player _player;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _player.stream.playing.listen((bool value) {
      if (!mounted) return;
      setState(() => _playing = value);
    });
    _player.stream.completed.listen((bool done) {
      if (!mounted || !done) return;
      setState(() {
        _playing = false;
        _playingSeq = null;
      });
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
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
      setState(() {
        _book = K12TextbookMedia.fromJson(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _play(K12TextbookLesson lesson) async {
    setState(() {
      _playingSeq = lesson.seq;
      _caching = true;
      _error = null;
    });
    try {
      final File cached = await ensureK12TextbookAudioCached(
        client: ref.read(acquireApiClientProvider),
        bookId: widget.mediaBookId,
        seq: lesson.seq,
        fallbackAudioUrl: lesson.audioUrl,
      );
      if (!mounted) return;
      setState(() => _caching = false);
      await _player.open(Media(cached.uri.toString()));
      await _player.play();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _caching = false;
        _playingSeq = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('音频下载失败，请重试：$error')),
      );
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

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.softWhite,
        title: Text(title),
        actions: <Widget>[
          if (book != null && book.lessons.isNotEmpty)
            TextButton(
              onPressed: _showAudioSheet,
              child: Text(
                '课次音频',
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
          : PdfViewer.uri(
              pdfUri,
              params: PdfViewerParams(
                backgroundColor: AppDesignTokens.softWhite,
                loadingBannerBuilder:
                    (
                      BuildContext context,
                      int bytesDownloaded,
                      int? totalBytes,
                    ) {
                      final double? progress = totalBytes == null || totalBytes <= 0
                          ? null
                          : bytesDownloaded / totalBytes;
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            SizedBox(
                              width: 160,
                              child: LinearProgressIndicator(value: progress),
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
      floatingActionButton: book != null && book.lessons.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _showAudioSheet,
              backgroundColor: AppDesignTokens.brandGreen,
              foregroundColor: AppDesignTokens.onAccent,
              icon: Icon(
                _playing ? Icons.pause_rounded : Icons.headphones_rounded,
              ),
              label: Text(_playing ? '播放中' : '听课'),
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
          '点课程会下载配套 MP3 到本机后再播放。',
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
