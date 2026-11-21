import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../player/data/pronunciation_providers.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/oral_coach_pipeline_client.dart';
import '../domain/oral_expression_diagnosis.dart';
import 'widgets/oral_diagnosis_card.dart';

/// Peer oral matching: server queue → diagnose → re-say → send to peer.
class PeerOralPracticeScreen extends ConsumerStatefulWidget {
  const PeerOralPracticeScreen({super.key});

  @override
  ConsumerState<PeerOralPracticeScreen> createState() =>
      _PeerOralPracticeScreenState();
}

enum _PeerPhase { matching, chat, diagnose, resay }

class _PeerOralPracticeScreenState
    extends ConsumerState<PeerOralPracticeScreen> {
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 45;

  final OralCoachPipelineClient _pipeline = OralCoachPipelineClient();
  final List<_PeerBubble> _bubbles = <_PeerBubble>[];
  final TextEditingController _preview = TextEditingController();

  PronunciationMicrophone? _microphone;
  final Uint8List _recordingBuffer = Uint8List(_maxRecordingBytes);
  int _recordingBytesWritten = 0;
  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _recordingLimitTimer;

  _PeerPhase _phase = _PeerPhase.matching;
  bool _busy = false;
  bool _recording = false;
  bool _saved = false;
  String _status = '正在匹配口语搭子…';
  String? _error;
  OralCoachSession? _session;
  OralExpressionDiagnosis? _pending;
  String _peerName = '口语搭子';
  String? _roomId;
  String? _lastMessageId;
  Timer? _matchPoll;
  Timer? _messagePoll;
  bool _offlineFallback = false;

  @override
  void initState() {
    super.initState();
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    unawaited(_bootstrapMatch());
  }

  @override
  void dispose() {
    _recordingLimitTimer?.cancel();
    _matchPoll?.cancel();
    _messagePoll?.cancel();
    unawaited(_recordingSubscription?.cancel());
    unawaited(_microphone?.stop());
    unawaited(_microphone?.dispose());
    if (!_offlineFallback && ref.read(authSessionProvider).isLoggedIn) {
      unawaited(
        ref.read(acquireApiClientProvider).leaveOralMatch().catchError(
          (Object _) {},
        ),
      );
    }
    _preview.dispose();
    super.dispose();
  }

  Future<void> _bootstrapMatch() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      _enterOfflineFallback(
        reason: '未登录，先用本地演示搭子（登录后可真实匹配）',
      );
      return;
    }
    setState(() {
      _phase = _PeerPhase.matching;
      _status = '正在匹配口语搭子…';
      _error = null;
    });
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      OralMatchStatus status = await api.enqueueOralMatch();
      if (!mounted) return;
      if (status.isMatched) {
        _onMatched(status);
        return;
      }
      _matchPoll?.cancel();
      _matchPoll = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_pollMatch());
      });
      setState(() {
        _status = status.queuePosition == null
            ? '排队中，等待另一位学习者…'
            : '排队中（第 ${status.queuePosition} 位）…';
      });
    } catch (error) {
      if (!mounted) return;
      _enterOfflineFallback(reason: '匹配服务暂不可用，先用本地演示：${'$error'}');
    }
  }

  Future<void> _pollMatch() async {
    if (!mounted || _phase != _PeerPhase.matching) return;
    try {
      final OralMatchStatus status =
          await ref.read(acquireApiClientProvider).oralMatchStatus();
      if (!mounted) return;
      if (status.isMatched) {
        _matchPoll?.cancel();
        _onMatched(status);
        return;
      }
      if (status.status == 'waiting') {
        setState(() {
          _status = status.queuePosition == null
              ? '排队中，等待另一位学习者…'
              : '排队中（第 ${status.queuePosition} 位）…';
        });
        return;
      }
      // idle → re-enqueue
      await ref.read(acquireApiClientProvider).enqueueOralMatch();
    } catch (_) {}
  }

  void _onMatched(OralMatchStatus status) {
    _roomId = status.roomId;
    _peerName = (status.peerDisplayName ?? '').isEmpty
        ? '口语搭子'
        : status.peerDisplayName!;
    setState(() {
      _phase = _PeerPhase.chat;
      _offlineFallback = false;
      _status = '已匹配 $_peerName · 按住说话（中文 / 英文混说均可）';
      _bubbles.add(
        _PeerBubble(
          role: 'peer',
          text:
              'Hi! I\'m $_peerName. Tell me what you did today — Chinese is OK if you get stuck.',
        ),
      );
    });
    _startMessagePoll();
  }

  void _enterOfflineFallback({required String reason}) {
    _offlineFallback = true;
    _matchPoll?.cancel();
    setState(() {
      _phase = _PeerPhase.chat;
      _peerName = 'Luna';
      _error = reason;
      _status = '本地演示 · 按住说话（中文 / 英文混说均可）';
      _bubbles.add(
        const _PeerBubble(
          role: 'peer',
          text:
              'Hi! Tell me what you did today — Chinese is OK if you get stuck.',
        ),
      );
    });
  }

  void _startMessagePoll() {
    _messagePoll?.cancel();
    if (_roomId == null || _offlineFallback) return;
    _messagePoll = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pullPeerMessages());
    });
  }

  Future<void> _pullPeerMessages() async {
    final String? roomId = _roomId;
    if (!mounted || roomId == null || _offlineFallback) return;
    try {
      final List<OralMatchMessage> rows =
          await ref.read(acquireApiClientProvider).listOralMatchMessages(
                roomId: roomId,
                afterId: _lastMessageId,
              );
      if (!mounted || rows.isEmpty) return;
      setState(() {
        for (final OralMatchMessage msg in rows) {
          _lastMessageId = msg.id;
          if (msg.mine) continue;
          _bubbles.add(
            _PeerBubble(role: 'peer', text: msg.text),
          );
        }
      });
    } catch (_) {}
  }

  Future<OralCoachSession?> _ensureSession() async {
    if (_session != null) return _session;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String base = settings.oralCoachPipelineUrl.trim();
    if (base.isEmpty) {
      throw StateError('请先在设置中填写口语陪练管线地址。');
    }
    final OralCoachSession session = await _pipeline.createSession(
      rawBaseUrl: base,
      context: const OralCoachVideoContext(
        courseTitle: '真人口语对练',
        episodeTitle: 'Peer practice',
        topicSummary: 'Casual peer oral practice with idiomatic rewrite',
        articleExcerpt:
            'Practice everyday spoken English with a matched partner. '
            'When the learner mixes Chinese, rewrite into natural English.',
        difficulty: 'B1',
      ),
    );
    _session = session;
    return session;
  }

  Future<void> _holdStart() async {
    if (_busy || _recording) return;
    if (_phase == _PeerPhase.matching) return;
    final PronunciationMicrophone? microphone = _microphone;
    if (microphone == null) {
      setState(() => _error = '麦克风不可用');
      return;
    }
    try {
      final bool allowed = await microphone.requestPermission();
      if (!mounted) return;
      if (!allowed) {
        setState(() => _error = '需要麦克风权限');
        return;
      }
      _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
      _recordingBytesWritten = 0;
      await _recordingSubscription?.cancel();
      final Stream<Uint8List> stream = await microphone.start();
      if (!mounted) {
        await microphone.cancel();
        return;
      }
      _recordingSubscription = stream.listen((Uint8List chunk) {
        final int room = _maxRecordingBytes - _recordingBytesWritten;
        if (room <= 0) {
          unawaited(_holdEnd());
          return;
        }
        final int take = min(room, chunk.length);
        _recordingBuffer.setRange(
          _recordingBytesWritten,
          _recordingBytesWritten + take,
          chunk,
        );
        _recordingBytesWritten += take;
      });
      _recordingLimitTimer?.cancel();
      _recordingLimitTimer = Timer(
        const Duration(seconds: 40),
        () => unawaited(_holdEnd()),
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        if (_phase == _PeerPhase.diagnose) {
          _phase = _PeerPhase.resay;
        }
        _status = _phase == _PeerPhase.resay
            ? '正在跟读地道英文…'
            : '正在听你说…';
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法启动录音');
      }
    }
  }

  Future<void> _holdEnd() async {
    if (!_recording) return;
    _recordingLimitTimer?.cancel();
    _recording = false;
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
      setState(() => _status = '没听清，请再说一次');
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在识别并改写…';
    });

    String? path;
    try {
      final Directory directory = await getTemporaryDirectory();
      path =
          '${directory.path}/peer-oral-${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(audio.toWav(), flush: true);

      if (_phase == _PeerPhase.resay && _pending != null) {
        await _finishResayAndSend(path);
      } else {
        await _diagnoseThenGate(path);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
          _status = '本回合失败，可再按住重试';
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

  Future<void> _diagnoseThenGate(String audioPath) async {
    final OralCoachSession? session = await _ensureSession();
    if (!mounted || session == null) return;
    final OralCoachDraftResult draft = await _pipeline.createDraft(
      session: session,
      audioPath: audioPath,
    );
    final String confirmed = draft.transcript.trim();
    if (confirmed.isEmpty) throw StateError('语音转写为空');
    _preview.text = confirmed;

    final OralCoachTurnResult turn = await _pipeline.confirmDraft(
      session: session,
      draftId: draft.draftId,
      confirmedText: confirmed,
      textOnly: true,
      replyLanguage: 'en',
    );
    if (!mounted) return;

    OralExpressionDiagnosis diagnosis =
        turn.diagnosis ??
        OralExpressionDiagnosis.fallback(
          source: confirmed,
          literalEn: confirmed,
          idiomaticEn: confirmed,
          tip: transcriptLooksChineseHeavy(confirmed)
              ? '先按住再说一次地道英文，再发给对方。'
              : '可再润色成更自然的口语。',
        );
    if (!diagnosis.isUseful) {
      diagnosis = OralExpressionDiagnosis.fallback(source: confirmed);
    }

    _saveToBank(diagnosis);
    setState(() {
      _pending = diagnosis;
      _saved = true;
      _phase = _PeerPhase.diagnose;
      _bubbles.add(_PeerBubble(role: 'me', text: confirmed));
      _bubbles.add(
        _PeerBubble(
          role: 'diagnosis',
          text: diagnosis.idiomaticEn,
          diagnosis: diagnosis,
        ),
      );
      _busy = false;
      _status = '按住再说一次，再说给对方听';
    });
  }

  Future<void> _finishResayAndSend(String audioPath) async {
    final OralExpressionDiagnosis? pending = _pending;
    final OralCoachSession? session = await _ensureSession();
    if (!mounted || session == null || pending == null) return;
    final OralCoachDraftResult draft = await _pipeline.createDraft(
      session: session,
      audioPath: audioPath,
    );
    final String confirmed = draft.transcript.trim().isEmpty
        ? (pending.idiomaticEn.isNotEmpty
              ? pending.idiomaticEn
              : pending.literalEn)
        : draft.transcript.trim();

    if (!_offlineFallback && _roomId != null) {
      try {
        final OralMatchMessage sent =
            await ref.read(acquireApiClientProvider).postOralMatchMessage(
                  roomId: _roomId!,
                  text: confirmed,
                );
        _lastMessageId = sent.id;
      } catch (error) {
        if (mounted) {
          setState(() => _error = '发送失败：$error');
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _bubbles.add(_PeerBubble(role: 'me', text: confirmed, sent: true));
      if (_offlineFallback) {
        _bubbles.add(
          const _PeerBubble(
            role: 'peer',
            text: 'Got it! That sounded clearer. Tell me more?',
          ),
        );
      }
      _pending = null;
      _phase = _PeerPhase.chat;
      _preview.clear();
      _busy = false;
      _status = _offlineFallback
          ? '已发送（本地演示）· 继续按住说话'
          : '已发给 $_peerName · 等待对方回复';
    });
  }

  void _saveToBank(OralExpressionDiagnosis diagnosis) {
    final String english = diagnosis.idiomaticEn.isNotEmpty
        ? diagnosis.idiomaticEn
        : diagnosis.literalEn;
    if (english.trim().isEmpty) return;
    final bool added = ref.read(phraseBookProvider.notifier).addPhraseIfMissing(
          english: english,
          chinese: diagnosis.source,
          course: '口语诊断',
          episode: '真人口语对练',
          time: DateTime.now().toIso8601String(),
          needsReview: true,
          today: true,
          note: diagnosis.tip.isNotEmpty ? diagnosis.tip : 'peer_oral_diagnosis',
        );
    _saved = added || _saved;
  }

  @override
  Widget build(BuildContext context) {
    final bool gateResay =
        _phase == _PeerPhase.diagnose || _phase == _PeerPhase.resay;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F0FF),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_peerName),
            Text(
              _phase == _PeerPhase.matching ? '匹配中' : '当前在线 · 口语对练',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            Expanded(
              child: _phase == _PeerPhase.matching
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: _bubbles.length,
                      itemBuilder: (BuildContext context, int index) {
                        final _PeerBubble bubble = _bubbles[index];
                        if (bubble.role == 'diagnosis' &&
                            bubble.diagnosis != null) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: OralDiagnosisCard(
                              diagnosis: bubble.diagnosis!,
                              saved: _saved,
                              onSave: () {
                                _saveToBank(bubble.diagnosis!);
                                setState(() => _saved = true);
                              },
                            ),
                          );
                        }
                        final bool mine = bubble.role == 'me';
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.sizeOf(context).width * 0.78,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? const Color(0xFF7C5CFF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              bubble.text,
                              style: TextStyle(
                                color: mine
                                    ? Colors.white
                                    : const Color(0xFF111827),
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_preview.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE7FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _preview.text,
                    style: const TextStyle(
                      color: Color(0xFF4C1D95),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Material(
                color: const Color(0xFF6D28D9),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTapDown: _busy ? null : (_) => unawaited(_holdStart()),
                  onTapUp: _busy ? null : (_) => unawaited(_holdEnd()),
                  onTapCancel:
                      _busy ? null : () => unawaited(_holdEnd()),
                  child: SizedBox(
                    height: 54,
                    child: Center(
                      child: Text(
                        _busy
                            ? '处理中…'
                            : (_recording
                                  ? (gateResay ? '松开发送跟读' : '松开发送')
                                  : (gateResay ? '按住再说一次' : '按住说话')),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerBubble {
  const _PeerBubble({
    required this.role,
    required this.text,
    this.diagnosis,
    this.sent = false,
  });

  final String role; // me | peer | diagnosis
  final String text;
  final OralExpressionDiagnosis? diagnosis;
  final bool sent;
}
