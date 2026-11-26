import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
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
          _error = '服务器上还没有这本教材的音频包';
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
    final String url = lesson.audioUrl.trim();
    if (url.isEmpty) return;
    setState(() => _playingSeq = lesson.seq);
    await _player.open(Media(url));
    await _player.play();
  }

  Future<void> _toggle(K12TextbookLesson lesson) async {
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

  Future<void> _openPdf() async {
    final String url = _book?.pdfUrl.trim() ?? '';
    if (url.isEmpty) return;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开课本 PDF')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final K12TextbookMedia? book = _book;
    final String title = book?.displayTitle.isNotEmpty == true
        ? book!.displayTitle
        : (widget.catalogTitle.isEmpty ? '英语教材' : widget.catalogTitle);

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.softWhite,
        title: Text(title),
        actions: <Widget>[
          if (book != null && book.pdfUrl.isNotEmpty)
            TextButton(onPressed: _openPdf, child: const Text('打开 PDF')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppDesignTokens.textPrimary),
                ),
              ),
            )
          : _buildBody(book!),
    );
  }

  Widget _buildBody(K12TextbookMedia book) {
    final Map<String, List<K12TextbookLesson>> grouped =
        <String, List<K12TextbookLesson>>{};
    for (final K12TextbookLesson lesson in book.lessons) {
      final String key = lesson.unitLabel.isEmpty ? '其他' : lesson.unitLabel;
      grouped.putIfAbsent(key, () => <K12TextbookLesson>[]).add(lesson);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        Text(
          '${book.edition} · ${book.volume} · ${book.lessons.length} 课音频',
          style: TextStyle(color: AppDesignTokens.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          '点课程即可播放配套 MP3。点读（OCR→翻译→朗读）下一阶段接入。',
          style: TextStyle(color: AppDesignTokens.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 16),
        for (final MapEntry<String, List<K12TextbookLesson>> entry
            in grouped.entries) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              entry.key,
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontSize: 16,
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
                  _playingSeq == lesson.seq && _playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: AppDesignTokens.brandGreen,
                  size: 32,
                ),
                onTap: () => unawaited(_toggle(lesson)),
              ),
            ),
        ],
      ],
    );
  }
}
