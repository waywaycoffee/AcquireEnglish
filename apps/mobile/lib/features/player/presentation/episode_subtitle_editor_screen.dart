import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/presentation/library_mock_data.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'bilingual_subtitle_helpers.dart';
import 'manual_subtitle_persist.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';
import 'subtitle_file_persist.dart';
import 'subtitle_sentence_merge.dart';

class EpisodeSubtitleEditorScreen extends StatefulWidget {
  const EpisodeSubtitleEditorScreen({
    required this.episodeId,
    required this.title,
    this.initialLines = const <PlayerSubtitleLine>[],
    this.englishPath,
    this.chinesePath,
    this.sourceKey,
    this.onSaved,
    super.key,
  });

  final String episodeId;
  final String title;
  final List<PlayerSubtitleLine> initialLines;
  final String? englishPath;
  final String? chinesePath;
  final String? sourceKey;
  final FutureOr<void> Function(List<PlayerSubtitleLine> lines)? onSaved;

  static Future<List<PlayerSubtitleLine>?> open(
    BuildContext context, {
    required String episodeId,
    required String title,
    List<PlayerSubtitleLine> initialLines = const <PlayerSubtitleLine>[],
    String? englishPath,
    String? chinesePath,
    String? sourceKey,
    FutureOr<void> Function(List<PlayerSubtitleLine> lines)? onSaved,
  }) {
    return Navigator.of(context).push<List<PlayerSubtitleLine>>(
      MaterialPageRoute<List<PlayerSubtitleLine>>(
        builder: (_) => EpisodeSubtitleEditorScreen(
          episodeId: episodeId,
          title: title,
          initialLines: initialLines,
          englishPath: englishPath,
          chinesePath: chinesePath,
          sourceKey: sourceKey,
          onSaved: onSaved,
        ),
      ),
    );
  }

  /// Convenience from a library episode (loads disk / ASR bundle).
  static Future<List<PlayerSubtitleLine>?> openForEpisode(
    BuildContext context, {
    required LibraryCourseData course,
    required LibraryEpisodeItem episode,
    FutureOr<void> Function(List<PlayerSubtitleLine> lines)? onSaved,
  }) {
    return open(
      context,
      episodeId: episode.id,
      title: episode.title,
      englishPath: episode.enSubtitleAsset,
      chinesePath: episode.cnSubtitleAsset,
      sourceKey: episode.sourceUrl,
      onSaved: onSaved,
    );
  }

  @override
  State<EpisodeSubtitleEditorScreen> createState() =>
      _EpisodeSubtitleEditorScreenState();
}

class _EpisodeSubtitleEditorRow {
  _EpisodeSubtitleEditorRow({
    required this.startMs,
    required this.endMs,
    required String english,
    required String chinese,
  }) : english = TextEditingController(text: english),
       chinese = TextEditingController(text: chinese);

  final int startMs;
  final int endMs;
  final TextEditingController english;
  final TextEditingController chinese;

  void dispose() {
    english.dispose();
    chinese.dispose();
  }

  PlayerSubtitleLine toLine() {
    return PlayerSubtitleLine(
      startTime: _clock(startMs),
      english: english.text.trim(),
      chinese: chinese.text.trim(),
      startMs: startMs,
      endMs: endMs,
    );
  }
}

class _EpisodeSubtitleEditorScreenState
    extends State<EpisodeSubtitleEditorScreen> {
  final List<_EpisodeSubtitleEditorRow> _rows = <_EpisodeSubtitleEditorRow>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    for (final _EpisodeSubtitleEditorRow row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      List<PlayerSubtitleLine> lines = widget.initialLines;
      if (lines.isEmpty) {
        final MergedSubtitleBundle? bundle = await loadAsrSentenceSubtitles(
          episodeId: widget.episodeId,
          sourceKey: widget.sourceKey,
        );
        if (bundle != null && bundle.sentences.isNotEmpty) {
          lines = bundle.sentenceLines;
        }
      }
      if (lines.isEmpty) {
        final String? en = widget.englishPath;
        final String? zh = widget.chinesePath;
        if (en != null && en.trim().isNotEmpty) {
          lines = await loadSubtitleLines(en);
        }
        if ((zh ?? '').trim().isNotEmpty) {
          final List<PlayerSubtitleLine> zhLines = await loadSubtitleLines(zh!);
          if (lines.isEmpty) {
            lines = zhLines;
          } else {
            lines = mergeSubtitleLines(
              englishLines: lines,
              chineseLines: zhLines,
            );
          }
        }
      }
      final Map<int, String> enLocks = await loadManualEnglishLocks(
        episodeId: widget.episodeId,
      );
      final Map<int, String> zhLocks = await loadManualChineseLocks(
        episodeId: widget.episodeId,
      );
      lines = keepManualEnglish(
        lines: lines,
        manualEnglishByStartMs: enLocks,
      );
      lines = keepManualChinese(
        lines: lines,
        manualChineseByStartMs: zhLocks,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _replaceRows(lines);
        _loading = false;
        if (_rows.isEmpty) {
          _error = '这集还没有可编辑的字幕';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '加载字幕失败：$e';
      });
    }
  }

  void _replaceRows(List<PlayerSubtitleLine> lines) {
    for (final _EpisodeSubtitleEditorRow row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(
        lines.map(
          (PlayerSubtitleLine line) => _EpisodeSubtitleEditorRow(
            startMs: line.startMs,
            endMs: line.endMs,
            english: line.english,
            chinese: line.chinese,
          ),
        ),
      );
  }

  List<PlayerSubtitleLine> _collectLines() {
    return _rows.map((_EpisodeSubtitleEditorRow row) => row.toLine()).toList(
      growable: false,
    );
  }

  Future<void> _remergeSentences() async {
    final List<PlayerSubtitleLine> remorphed = remergeEnglishSentences(
      _collectLines(),
    );
    setState(() {
      _replaceRows(remorphed);
      _error = null;
    });
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已尽量拼成完整英文句子（${remorphed.length} 句）')),
    );
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final List<PlayerSubtitleLine> lines = _collectLines();
      final PersistedBilingualSubtitleFiles? files =
          await persistManualSubtitleEdits(
            episodeId: widget.episodeId,
            lines: lines,
            sourceKey: widget.sourceKey,
          );
      if (files == null) {
        throw StateError('没有可保存的字幕内容');
      }
      await widget.onSaved?.call(lines);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(lines);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.softWhite,
        foregroundColor: AppDesignTokens.textPrimary,
        title: const Text('手工改字幕'),
        actions: <Widget>[
          TextButton(
            onPressed: _loading || _rows.isEmpty ? null : _remergeSentences,
            child: const Text('拼成完整句子'),
          ),
          TextButton(
            onPressed: _loading || _saving || _rows.isEmpty ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Text(
                    '点进某一行改正英文/中文。保存后自动校对不会再覆盖你改过的句子。可用「拼成完整句子」把碎句合并。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFBA1A1A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final _EpisodeSubtitleEditorRow row = _rows[index];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${index + 1}. ${_clock(row.startMs)} → ${_clock(row.endMs)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppDesignTokens.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: row.english,
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: '英文',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: row.chinese,
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: '中文',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

String _clock(int milliseconds) {
  final int clamped = milliseconds < 0 ? 0 : milliseconds;
  final int totalSeconds = clamped ~/ 1000;
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
