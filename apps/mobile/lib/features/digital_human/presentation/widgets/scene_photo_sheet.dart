import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/scene_word_label.dart';

/// Live-style photo overlay with floating word chips (word / IPA / Chinese).
class ScenePhotoSheet extends StatefulWidget {
  const ScenePhotoSheet({
    required this.imagePath,
    required this.labels,
    required this.savedWords,
    required this.onAddWord,
    required this.onShareWithCoach,
    required this.onRetake,
    required this.onRefine,
    this.busy = false,
    this.refining = false,
    this.refined = false,
    this.statusHint = '',
    super.key,
  });

  final String imagePath;
  final List<SceneWordLabel> labels;
  final Set<String> savedWords;
  final Future<void> Function(SceneWordLabel label) onAddWord;
  final Future<void> Function() onShareWithCoach;
  final VoidCallback onRetake;
  final Future<void> Function() onRefine;
  final bool busy;
  final bool refining;
  final bool refined;
  final String statusHint;

  @override
  State<ScenePhotoSheet> createState() => _ScenePhotoSheetState();
}

class _ScenePhotoSheetState extends State<ScenePhotoSheet> {
  bool _showLabels = true;
  bool _showPhonetic = true;
  String? _savingWord;
  late Set<String> _saved;

  @override
  void initState() {
    super.initState();
    _saved = <String>{...widget.savedWords};
  }

  @override
  void didUpdateWidget(covariant ScenePhotoSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.savedWords != widget.savedWords) {
      _saved = <String>{...widget.savedWords};
    }
  }

  String get _footerHint {
    if (widget.statusHint.trim().isNotEmpty) return widget.statusHint;
    if (widget.refining) return '云端精修中（Qwen-VL）…';
    if (widget.refined) {
      return widget.labels.isEmpty
          ? '云端也未识别到清晰物品，可重拍或仍交给数字人描述。'
          : '已云端精修；点标注加入生词本，或点「聊这个场景」。';
    }
    return widget.labels.isEmpty
        ? '端上暂无清晰物品，可点「再识别一次」走云端，或重拍。'
        : '端上快标已出；云端精修可提高准确度。点标注可加入生词本。';
  }

  @override
  Widget build(BuildContext context) {
    final bool blocked = widget.busy || widget.refining;
    return SafeArea(
      child: Material(
        color: const Color(0xFF0F0A24),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '拍照识词',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.refining
                              ? '端上快标 · 云端精修中'
                              : (widget.refined ? '云端精修完成' : '端上快标'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.cover,
                          ),
                          if (_showLabels)
                            ...widget.labels.map((SceneWordLabel label) {
                              final bool saved = _saved.contains(label.word);
                              return Positioned(
                                left: constraints.maxWidth * label.anchorX - 72,
                                top: constraints.maxHeight * label.anchorY - 28,
                                child: _FloatingWordChip(
                                  label: label,
                                  showPhonetic: _showPhonetic,
                                  saved: saved,
                                  saving: _savingWord == label.word,
                                  onTap: blocked
                                      ? null
                                      : () async {
                                          setState(
                                            () => _savingWord = label.word,
                                          );
                                          try {
                                            await widget.onAddWord(label);
                                            if (mounted) {
                                              setState(
                                                () => _saved.add(label.word),
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(
                                                () => _savingWord = null,
                                              );
                                            }
                                          }
                                        },
                                ),
                              );
                            }),
                          if (blocked)
                            ColoredBox(
                              color: const Color(0x66000000),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const CircularProgressIndicator(),
                                    if (widget.refining) ...<Widget>[
                                      const SizedBox(height: 12),
                                      Text(
                                        '云端精修中…',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.9,
                                          ),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: <Widget>[
                  _ToolChip(
                    label: '标注',
                    active: _showLabels,
                    onTap: () => setState(() => _showLabels = !_showLabels),
                  ),
                  _ToolChip(
                    label: '音标',
                    active: _showPhonetic,
                    onTap: () => setState(() => _showPhonetic = !_showPhonetic),
                  ),
                  _ToolChip(
                    label: widget.refined ? '再识别一次' : '云端精修',
                    onTap: blocked ? null : () => widget.onRefine(),
                  ),
                  _ToolChip(
                    label: '重拍',
                    onTap: blocked ? null : widget.onRetake,
                  ),
                  _ToolChip(
                    label: '聊这个场景',
                    emphasized: true,
                    onTap: blocked ? null : () => widget.onShareWithCoach(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                _footerHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingWordChip extends StatelessWidget {
  const _FloatingWordChip({
    required this.label,
    required this.showPhonetic,
    required this.saved,
    required this.saving,
    this.onTap,
  });

  final SceneWordLabel label;
  final bool showPhonetic;
  final bool saved;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: const Color(0x44000000),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label.word,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (showPhonetic && label.phonetic.isNotEmpty)
                    Text(
                      label.phonetic,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (label.chinese.isNotEmpty)
                    Text(
                      label.chinese,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              if (saving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  saved ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 20,
                  color: saved
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF9CA3AF),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.label,
    this.onTap,
    this.active = false,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final Color bg = emphasized
        ? const Color(0xFF6D28D9)
        : (active ? const Color(0xFF4C1D95) : Colors.white.withValues(alpha: 0.12));
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: onTap == null ? 0.45 : 0.95),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
