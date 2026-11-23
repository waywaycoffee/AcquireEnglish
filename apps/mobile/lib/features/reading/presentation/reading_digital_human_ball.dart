import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../digital_human/data/digital_human_catalog.dart';
import '../../digital_human/data/oral_coach_pipeline_client.dart';
import '../../membership/domain/oral_doc_library.dart';
import '../../membership/domain/oral_explore_entitlements.dart';
import '../../player/data/pronunciation_providers.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/reading_coach_context.dart';
import '../domain/reading_doc.dart';
import 'reading_page_quiz.dart';

class _ChatBubble {
  const _ChatBubble({required this.role, required this.text});

  final String role; // user | coach
  final String text;
}

/// Draggable digital-human orb on the reading page; tap to voice-ask the coach.
class ReadingDigitalHumanBallHost extends ConsumerStatefulWidget {
  const ReadingDigitalHumanBallHost({
    required this.doc,
    required this.child,
    this.focusedSentence = '',
    this.onPreparePageQuiz,
    this.onOpenPageQuiz,
    super.key,
  });

  final ReadingDoc doc;
  final Widget child;
  final String focusedSentence;
  /// Build quiz while the companion sheet stays open.
  final Future<ReadingPageQuizBundle?> Function()? onPreparePageQuiz;
  /// Called after the sheet closes with a ready quiz bundle.
  final Future<void> Function(ReadingPageQuizBundle bundle)? onOpenPageQuiz;

  @override
  ConsumerState<ReadingDigitalHumanBallHost> createState() =>
      _ReadingDigitalHumanBallHostState();
}

class _ReadingDigitalHumanBallHostState
    extends ConsumerState<ReadingDigitalHumanBallHost> {
  Offset _offset = const Offset(18, 140);

  Future<void> _openSheet() async {
    final OralExploreSnapshot explore =
        await ref.read(oralExploreSnapshotProvider.future);
    final bool allowed = await OralDocLibraryStore.registerDoc(
      docId: widget.doc.id,
      limits: explore.docLibraries,
    );
    if (!allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '口语文档库已达上限（${explore.docLibraries.limit} 个）。'
            '探索版请先移除其他文档再挂载。',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final ReadingPageQuizBundle? bundle =
        await showModalBottomSheet<ReadingPageQuizBundle>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext ctx) {
        return ReadingCoachAskSheet(
          doc: widget.doc,
          focusedSentence: widget.focusedSentence,
          onPreparePageQuiz: widget.onPreparePageQuiz,
        );
      },
    );
    if (!mounted || bundle == null) return;
    final Future<void> Function(ReadingPageQuizBundle bundle)? open =
        widget.onOpenPageQuiz;
    if (open != null) {
      await open(bundle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DigitalHumanPersona persona =
        ref.watch(learningSettingsProvider).selectedDigitalHuman;
    final String avatar = persona.assetPath;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(child: widget.child),
        Positioned(
          right: _offset.dx,
          bottom: _offset.dy,
          child: GestureDetector(
            onPanUpdate: (DragUpdateDetails d) {
              setState(() {
                _offset = Offset(
                  (_offset.dx - d.delta.dx).clamp(8, 280),
                  (_offset.dy - d.delta.dy).clamp(80, 640),
                );
              });
            },
            onTap: _openSheet,
            child: Material(
              color: Colors.transparent,
              elevation: 6,
              shape: const CircleBorder(),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95),
                    width: 2.5,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppDesignTokens.brandGreenDark.withValues(
                        alpha: 0.35,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.asset(
                      avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: AppDesignTokens.brandGreenDark,
                        child: Center(
                          child: Text(
                            persona.displayName.isNotEmpty
                                ? persona.displayName[0]
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(bottom: 3, top: 2),
                        color: Colors.black.withValues(alpha: 0.45),
                        child: const Text(
                          '问我',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReadingCoachAskSheet extends ConsumerStatefulWidget {
  const ReadingCoachAskSheet({
    required this.doc,
    this.focusedSentence = '',
    this.onPreparePageQuiz,
    super.key,
  });

  final ReadingDoc doc;
  final String focusedSentence;
  final Future<ReadingPageQuizBundle?> Function()? onPreparePageQuiz;

  @override
  ConsumerState<ReadingCoachAskSheet> createState() =>
      _ReadingCoachAskSheetState();
}

class _ReadingCoachAskSheetState extends ConsumerState<ReadingCoachAskSheet> {
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 45;

  final OralCoachPipelineClient _pipeline = OralCoachPipelineClient();
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatBubble> _bubbles = <_ChatBubble>[];
  final Uint8List _recordingBuffer = Uint8List(_maxRecordingBytes);

  PronunciationMicrophone? _microphone;
  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _recordingLimitTimer;
  OralCoachSession? _session;
  int _recordingBytesWritten = 0;
  bool _recordingActive = false;
  bool _busy = false;
  bool _greeted = false;
  /// Default off: opening the sheet must not auto-play AI/TTS voice.
  bool _coachVoiceEnabled = false;
  String _status = '按住麦克风提问';
  String? _error;

  @override
  void initState() {
    super.initState();
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureSessionAndGreet());
    });
  }

  @override
  void dispose() {
    _recordingLimitTimer?.cancel();
    unawaited(_recordingSubscription?.cancel());
    unawaited(_microphone?.dispose() ?? Future<void>.value());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  OralCoachVideoContext _contextFor(LearningSettingsState settings) {
    final DigitalHumanPersona persona = settings.selectedDigitalHuman;
    return buildReadingCoachContext(
      doc: widget.doc,
      persona: persona,
      focusedSentence: widget.focusedSentence,
      ttsVoice: readingCoachVoiceForPersona(persona),
    );
  }

  Future<void> _ensureSessionAndGreet() async {
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    if (!settings.usesOralCoachPipeline) {
      setState(() {
        _error = '请先在设置中启用「视频陪练管线」';
        _status = '陪练未连接';
      });
      return;
    }
    try {
      setState(() {
        _busy = true;
        _status = '数字人准备中…';
        _error = null;
      });
      final OralCoachSession session = await _pipeline.createSession(
        rawBaseUrl: settings.oralCoachPipelineUrl,
        context: _contextFor(settings),
      );
      if (!mounted) return;
      _session = session;
      final DigitalHumanPersona persona = settings.selectedDigitalHuman;
      final String greet =
          '你好，我是 ${persona.displayName}。一起读《${widget.doc.title}》—— '
          '有不懂的词或句子，按住麦克风问我；'
          '也可以点下方「出阅读理解题」考考自己。';
      setState(() {
        _bubbles.add(_ChatBubble(role: 'coach', text: greet));
        _busy = false;
        _status = '按住麦克风提问';
        _greeted = true;
      });
      _scrollToEnd();
      // Never auto-play greeting voice (绿野仙踪等长篇打开伴读时最易“偷跑”).
      if (_coachVoiceEnabled) {
        await _speakCoach(greet, settings);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '连接失败：$error';
        _status = '稍后重试';
      });
    }
  }

  Future<void> _speakCoach(String text, LearningSettingsState settings) async {
    final String spoken = text.trim();
    if (spoken.isEmpty || !_coachVoiceEnabled) return;
    final DigitalHumanPersona persona = settings.selectedDigitalHuman;
    try {
      final String? url = await _pipeline.synthesizeSpeech(
        rawBaseUrl: settings.oralCoachPipelineUrl,
        text: spoken,
        digitalHumanId: persona.id,
        ttsVoice: readingCoachVoiceForPersona(persona),
        language: 'zh',
      );
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        await ref.read(wordPronunciationServiceProvider).speak(
              spoken,
              recordedUrl: url,
              allowSynthesisFallback: false,
            );
        return;
      }
    } catch (_) {}
    // No device/OEM fallback — avoids “AI 语音偷跑”.
  }

  Future<void> _onHoldStart() async {
    if (_busy || _recordingActive) return;
    if (_session == null && !_greeted) {
      await _ensureSessionAndGreet();
      if (_session == null) return;
    }
    final PronunciationMicrophone? microphone = _microphone;
    if (microphone == null) {
      setState(() => _error = '麦克风不可用');
      return;
    }
    setState(() {
      _error = null;
      _status = '正在听你说…';
    });
    try {
      _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
      _recordingBytesWritten = 0;
      final bool allowed = await microphone.requestPermission();
      if (!mounted) return;
      if (!allowed) {
        setState(() => _error = '需要麦克风权限');
        return;
      }
      final Stream<Uint8List> stream = await microphone.start();
      if (!mounted) {
        await microphone.cancel();
        return;
      }
      setState(() => _recordingActive = true);
      _recordingSubscription = stream.listen(
        (Uint8List chunk) {
          final int remaining = _maxRecordingBytes - _recordingBytesWritten;
          if (remaining <= 0) {
            unawaited(_stopRecordingAndSend());
            return;
          }
          final int n = min(remaining, chunk.length);
          _recordingBuffer.setRange(
            _recordingBytesWritten,
            _recordingBytesWritten + n,
            chunk,
          );
          _recordingBytesWritten += n;
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _error = '录音中断';
            _recordingActive = false;
          });
        },
      );
      _recordingLimitTimer = Timer(
        const Duration(seconds: 45),
        () => unawaited(_stopRecordingAndSend()),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _recordingActive = false;
          _error = '无法启动录音';
        });
      }
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_recordingActive) return;
    _recordingLimitTimer?.cancel();
    _recordingActive = false;
    if (mounted) {
      setState(() {
        _busy = true;
        _status = '正在理解你的话…';
      });
    }
    try {
      await _microphone?.stop();
    } catch (_) {}
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;

    final int audioLength = _recordingBytesWritten & ~1;
    final Pcm16MonoAudio audio = Pcm16MonoAudio(
      bytes: _recordingBuffer.sublist(0, audioLength),
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
    ).trimLeadingSilence();
    _recordingBytesWritten = 0;
    if (!mounted) return;
    if (!audio.hasSpeechEnergy) {
      setState(() {
        _busy = false;
        _status = '没听清，请再说一次';
      });
      return;
    }

    String? path;
    try {
      final Directory directory = await getTemporaryDirectory();
      path =
          '${directory.path}/reading-coach-${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(audio.toWav(), flush: true);
      await _runVoiceTurn(audioPath: path);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
          _status = '本回合失败';
        });
      }
    } finally {
      if (path != null) {
        try {
          final File file = File(path);
          if (file.existsSync()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _runVoiceTurn({required String audioPath}) async {
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    OralCoachSession? session = _session;
    if (session == null) {
      session = await _pipeline.createSession(
        rawBaseUrl: settings.oralCoachPipelineUrl,
        context: _contextFor(settings),
      );
      _session = session;
    } else {
      try {
        await _pipeline.updateContext(
          session: session,
          context: _contextFor(settings),
        );
      } catch (_) {}
    }
    if (!mounted) return;

    final OralCoachDraftResult draft = await _pipeline.createDraft(
      session: session,
      audioPath: audioPath,
    );
    if (!mounted) return;
    final String confirmed = draft.transcript.trim();
    if (confirmed.isEmpty) {
      setState(() {
        _busy = false;
        _status = '没听清，请再说一次';
      });
      return;
    }
    await _confirmAndReply(
      settings: settings,
      session: session,
      draftId: draft.draftId,
      confirmed: confirmed,
    );
  }

  Future<void> _sendTyped() async {
    final String question = _text.text.trim();
    if (question.isEmpty || _busy) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    if (!settings.usesOralCoachPipeline) {
      setState(() => _error = '请先在设置中启用「视频陪练管线」');
      return;
    }
    setState(() {
      _busy = true;
      _status = '外教思考中…';
      _error = null;
      _text.clear();
    });
    String? path;
    try {
      OralCoachSession? session = _session;
      if (session == null) {
        session = await _pipeline.createSession(
          rawBaseUrl: settings.oralCoachPipelineUrl,
          context: _contextFor(settings),
        );
        _session = session;
      }
      // Tiny silence WAV so the server can create a draft; confirmed_text wins.
      final Pcm16MonoAudio silence = Pcm16MonoAudio(
        bytes: Uint8List((Pcm16MonoAudio.expectedSampleRate ~/ 5) & ~1),
        sampleRate: Pcm16MonoAudio.expectedSampleRate,
      );
      final Directory directory = await getTemporaryDirectory();
      path =
          '${directory.path}/reading-coach-text-${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(silence.toWav(), flush: true);
      final OralCoachDraftResult draft = await _pipeline.createDraft(
        session: session,
        audioPath: path,
      );
      if (!mounted) return;
      await _confirmAndReply(
        settings: settings,
        session: session,
        draftId: draft.draftId,
        confirmed: question,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
          _status = '发送失败';
        });
      }
    } finally {
      if (path != null) {
        try {
          final File file = File(path);
          if (file.existsSync()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _confirmAndReply({
    required LearningSettingsState settings,
    required OralCoachSession session,
    required String draftId,
    required String confirmed,
  }) async {
    final DigitalHumanPersona persona = settings.selectedDigitalHuman;
    setState(() {
      _bubbles.add(_ChatBubble(role: 'user', text: confirmed));
      _busy = true;
      _status = '外教思考中…';
    });
    _scrollToEnd();

    final OralCoachTurnResult turn = await _pipeline.confirmDraft(
      session: session,
      draftId: draftId,
      confirmedText: confirmed,
      digitalHumanId: persona.id,
      ttsVoice: readingCoachVoiceForPersona(persona),
      replyLanguage: 'zh',
      textOnly: true,
    );
    if (!mounted) return;
    final String reply = turn.coachText.trim().isNotEmpty
        ? turn.coachText.trim()
        : turn.avatarText.trim();
    final String shown = reply.isEmpty ? '（教练暂时没有回复，请再试一次）' : reply;
    setState(() {
      _bubbles.add(_ChatBubble(role: 'coach', text: shown));
      _busy = false;
      _status = '按住麦克风提问';
    });
    _scrollToEnd();

    if (!_coachVoiceEnabled) return;
    if (turn.ttsUrl != null && turn.ttsUrl!.isNotEmpty) {
      try {
        await ref.read(wordPronunciationServiceProvider).speak(
              shown,
              recordedUrl: turn.ttsUrl,
              allowSynthesisFallback: false,
            );
        return;
      } catch (_) {}
    }
    await _speakCoach(shown, settings);
  }

  @override
  Widget build(BuildContext context) {
    final DigitalHumanPersona persona =
        ref.watch(learningSettingsProvider).selectedDigitalHuman;
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final String focus = widget.focusedSentence.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: AssetImage(
                      persona.assetPath,
                    ),
                    onBackgroundImageError: (_, __) {},
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${persona.displayName} · 阅读陪练',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          focus.isEmpty
                              ? '针对《${widget.doc.title}》随时提问'
                              : '当前句：${focus.length > 48 ? '${focus.substring(0, 48)}…' : focus}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF6B6B76),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: <Widget>[
                      Icon(
                        _coachVoiceEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        size: 18,
                        color: const Color(0xFF6B6B76),
                      ),
                      Switch(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        value: _coachVoiceEnabled,
                        onChanged: (bool v) {
                          setState(() => _coachVoiceEnabled = v);
                          if (!v) {
                            unawaited(
                              ref
                                  .read(wordPronunciationServiceProvider)
                                  .stop(),
                            );
                          }
                        },
                      ),
                      const Text(
                        '语音',
                        style: TextStyle(fontSize: 10, color: Color(0xFF6B6B76)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if ((_error ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
                ),
              ),
            if (widget.onPreparePageQuiz != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() {
                              _busy = true;
                              _error = null;
                              _status = '正在出阅读理解题…';
                            });
                            try {
                              final ReadingPageQuizBundle? bundle =
                                  await widget.onPreparePageQuiz!();
                              if (!mounted) return;
                              if (bundle == null || bundle.quiz.isEmpty) {
                                setState(() {
                                  _error = '出题失败，请稍后重试或换一节内容更完整的页';
                                  _status = '按住麦克风提问';
                                });
                                return;
                              }
                              Navigator.of(context).pop(bundle);
                            } catch (error) {
                              if (!mounted) return;
                              final String message = error is StateError
                                  ? error.message
                                  : '出题失败，请检查登录与网络后重试';
                              setState(() {
                                _error = message;
                                _status = '按住麦克风提问';
                              });
                            } finally {
                              if (mounted) {
                                setState(() => _busy = false);
                              }
                            }
                          },
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.quiz_outlined),
                    label: Text(_busy ? '正在出题…' : 'AI 出本节阅读理解题'),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                itemCount: _bubbles.length,
                itemBuilder: (BuildContext context, int index) {
                  final _ChatBubble bubble = _bubbles[index];
                  final bool mine = bubble.role == 'user';
                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                      ),
                      decoration: BoxDecoration(
                        color: mine
                            ? AppDesignTokens.brandGreenDark
                            : const Color(0xFFF2F2F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        bubble.text,
                        style: TextStyle(
                          color: mine ? Colors.white : const Color(0xFF2A2A32),
                          height: 1.4,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: _recordingActive
                      ? AppDesignTokens.brandGreenDark
                      : const Color(0xFF6B6B76),
                  fontWeight:
                      _recordingActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.paddingOf(context).bottom + 12,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_busy && !_recordingActive,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '或输入问题…',
                        filled: true,
                        fillColor: const Color(0xFFF7F7F9),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => unawaited(_sendTyped()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy || _recordingActive
                        ? null
                        : () => unawaited(_sendTyped()),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE8F5E9),
                      foregroundColor: AppDesignTokens.brandGreenDark,
                    ),
                    icon: const Icon(Icons.send_rounded),
                  ),
                  const SizedBox(width: 6),
                  Listener(
                    onPointerDown: (_) => unawaited(_onHoldStart()),
                    onPointerUp: (_) => unawaited(_stopRecordingAndSend()),
                    onPointerCancel: (_) => unawaited(_stopRecordingAndSend()),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _recordingActive
                            ? const Color(0xFFB42318)
                            : AppDesignTokens.brandGreenDark,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: (_recordingActive
                                    ? const Color(0xFFB42318)
                                    : AppDesignTokens.brandGreenDark)
                                .withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        _recordingActive
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
