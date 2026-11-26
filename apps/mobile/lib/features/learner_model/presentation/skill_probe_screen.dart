import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/learner_skill_profile.dart';
import '../domain/skill_probe_bank.dart';
import 'learner_skill_profile_provider.dart';

/// One or two first-attempt items for listening or reading.
class SkillProbeScreen extends ConsumerStatefulWidget {
  const SkillProbeScreen({super.key, required this.skill});

  final LearnerSkill skill;

  @override
  ConsumerState<SkillProbeScreen> createState() => _SkillProbeScreenState();
}

class _SkillProbeScreenState extends ConsumerState<SkillProbeScreen> {
  List<SkillProbeItem> _items = const <SkillProbeItem>[];
  final FlutterTts _tts = FlutterTts();
  int _index = 0;
  int _correct = 0;
  bool _speaking = false;
  bool _revealed = false;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final LearnerSkillProfile profile = ref.read(learnerSkillProfileProvider);
    final Set<String> answered = ref
        .read(learnerSkillProfileProvider.notifier)
        .probes()
        .where((ProbeAttempt row) => row.skill == widget.skill)
        .map((ProbeAttempt row) => row.itemId)
        .toSet();
    _items = pickSkillProbes(
      skill: widget.skill,
      band: profile.recommendationEstimate(widget.skill).band,
      answeredIds: answered,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _items.isNotEmpty && _items.first.speakPassage) {
        unawaited(_speakCurrent());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  Future<void> _speakCurrent() async {
    if (_items.isEmpty) return;
    final SkillProbeItem item = _items[_index];
    if (!item.speakPassage) return;
    setState(() => _speaking = true);
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.42);
      await _tts.speak(item.passage);
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _answer(int choice) async {
    if (_items.isEmpty) return;
    final SkillProbeItem item = _items[_index];
    final bool correct = choice == item.answer;
    if (correct) _correct += 1;
    await ref.read(learnerSkillProfileProvider.notifier).recordProbe(
          skill: item.skill,
          itemId: item.id,
          correct: correct,
          band: item.band,
        );
    if (!mounted) return;
    if (_index + 1 >= _items.length) {
      Navigator.of(context).pop(_correct);
      return;
    }
    setState(() {
      _index += 1;
      _revealed = false;
    });
    if (_items[_index].speakPassage) unawaited(_speakCurrent());
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.skill == LearnerSkill.listening
        ? '听力小测'
        : '阅读小测';
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: AppDesignTokens.softWhite,
        appBar: AppBar(
          backgroundColor: AppDesignTokens.softWhite,
          title: Text(title, style: TextStyle(color: AppDesignTokens.textPrimary)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '这一档暂时没有新的抽测题了。去学一会儿再回来。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
          ),
        ),
      );
    }
    final SkillProbeItem item = _items[_index];
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.softWhite,
        title: Text(
          '$title · ${_index + 1} / ${_items.length}',
          style: TextStyle(color: AppDesignTokens.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            '约 ${item.band} · 只记第一次作答',
            style: TextStyle(
              color: AppDesignTokens.brandGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (item.speakPassage) ...<Widget>[
            Text(
              '先听一遍，再答题。需要时可以再听。',
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _speaking ? null : _speakCurrent,
              icon: Icon(_speaking ? Icons.volume_up : Icons.play_arrow_rounded),
              label: Text(_speaking ? '播放中…' : '播放听力材料'),
            ),
            if (_revealed) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                item.passage,
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  height: 1.5,
                ),
              ),
            ] else
              TextButton(
                onPressed: () => setState(() => _revealed = true),
                child: const Text('显示原文（会记为需要辅助）'),
              ),
          ] else ...<Widget>[
            Text(
              item.passage,
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontSize: 18,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            item.question,
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < item.choices.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () => unawaited(_answer(i)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppDesignTokens.textPrimary,
                  side: BorderSide(color: AppDesignTokens.borderGray),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(item.choices[i]),
                ),
              ),
            ),
          TextButton(
            onPressed: () => unawaited(_answer(-1)),
            child: Text(
              '不确定',
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
