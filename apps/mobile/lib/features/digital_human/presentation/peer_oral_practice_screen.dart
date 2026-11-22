import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../player/data/pronunciation_providers.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../reading/domain/reading_doc.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/livekit_peer_client.dart';
import '../data/oral_coach_pipeline_client.dart';
import '../domain/oral_expression_diagnosis.dart';
import 'widgets/oral_diagnosis_card.dart';

/// Commercial peer oral: lobby → match/invite → LiveKit + AI rewrite → favorite.
class PeerOralPracticeScreen extends ConsumerStatefulWidget {
  const PeerOralPracticeScreen({super.key});

  @override
  ConsumerState<PeerOralPracticeScreen> createState() =>
      _PeerOralPracticeScreenState();
}

enum _PeerPhase { lobby, matching, waitingInvite, chat, diagnose, resay, ended }

const List<String> _kPeerTopics = <String>[
  '日常生活',
  '旅行出行',
  '工作职场',
  '学习考试',
  '影视娱乐',
  '美食购物',
  '兴趣爱好',
  '自由闲聊',
];

class _PeerOralPracticeScreenState
    extends ConsumerState<PeerOralPracticeScreen> {
  bool _languageExchange = false;
  String _nativeLang = 'zh';
  String _targetLang = 'en';
  String _selectedTopic = '日常生活';
  OralMatchContent _selectedContent = const OralMatchContent();
  List<OralMatchStatus> _openInvites = const <OralMatchStatus>[];
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 45;

  final OralCoachPipelineClient _pipeline = OralCoachPipelineClient();
  final LiveKitPeerClient _voice = LiveKitPeerClient();
  final List<_PeerBubble> _bubbles = <_PeerBubble>[];
  final TextEditingController _preview = TextEditingController();

  PronunciationMicrophone? _microphone;
  final Uint8List _recordingBuffer = Uint8List(_maxRecordingBytes);
  int _recordingBytesWritten = 0;
  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _recordingLimitTimer;

  _PeerPhase _phase = _PeerPhase.lobby;
  bool _busy = false;
  bool _recording = false;
  bool _saved = false;
  bool _micMuted = false;
  bool _voiceConnected = false;
  bool _peerVoicePresent = false;
  bool _peerOnline = true;
  String _status = '先选话题和素材，再匹配或发邀请';
  String? _error;
  OralCoachSession? _session;
  OralExpressionDiagnosis? _pending;
  String _peerName = '口语搭子';
  String? _roomId;
  String? _inviteId;
  OralMatchContent _roomContent = const OralMatchContent();
  String? _lastMessageId;
  String? _learningSessionId;
  Timer? _matchPoll;
  Timer? _messagePoll;
  Timer? _heartbeat;
  bool _leftSent = false;

  @override
  void initState() {
    super.initState();
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    _voice.onStatus = (String status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        _voiceConnected = _voice.isConnected;
      });
    };
    _voice.onPeerPresence = ({required bool peerConnected}) {
      if (!mounted) return;
      setState(() => _peerVoicePresent = peerConnected);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshOpenInvites());
    });
  }

  @override
  void dispose() {
    _recordingLimitTimer?.cancel();
    _matchPoll?.cancel();
    _messagePoll?.cancel();
    _heartbeat?.cancel();
    unawaited(_recordingSubscription?.cancel());
    unawaited(_microphone?.stop());
    unawaited(_microphone?.dispose());
    unawaited(_voice.disconnect());
    unawaited(_leaveQuietly());
    _preview.dispose();
    super.dispose();
  }

  Future<void> _leaveQuietly() async {
    if (_leftSent || !ref.read(authSessionProvider).isLoggedIn) return;
    _leftSent = true;
    try {
      await ref.read(acquireApiClientProvider).leaveOralMatch();
    } catch (_) {}
  }

  OralMatchContent get _prefsContent {
    final OralMatchContent base = _selectedContent;
    final String topic = _languageExchange ? '语言交换' : _selectedTopic;
    return OralMatchContent(
      topic: topic,
      kind: base.kind,
      id: base.id,
      title: base.title,
      route: base.route,
    );
  }

  Future<void> _bootstrapMatch() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() {
        _phase = _PeerPhase.lobby;
        _error = '请先登录后再进行真人对练';
        _status = '未登录';
      });
      return;
    }
    setState(() {
      _phase = _PeerPhase.matching;
      _status = '正在匹配口语搭子…';
      _error = null;
      _bubbles.clear();
      _roomId = null;
      _inviteId = null;
      _roomContent = _prefsContent;
      _session = null;
      _voiceConnected = false;
      _peerVoicePresent = false;
      _peerOnline = true;
      _leftSent = false;
    });
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final OralMatchStatus status = await api.enqueueOralMatch(
        mode: _languageExchange ? 'language_exchange' : 'peer_oral',
        nativeLang: _languageExchange ? _nativeLang : '',
        targetLang: _languageExchange ? _targetLang : '',
        topic: _prefsContent.topic,
        content: _prefsContent,
      );
      if (!mounted) return;
      if (status.isMatched) {
        await _onMatched(status);
        return;
      }
      _matchPoll?.cancel();
      _matchPoll = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_pollMatch());
      });
      setState(() {
        _status = status.queuePosition == null
            ? (_languageExchange
                ? '语言交换排队中，等待互补母语搭子…'
                : '排队中，优先匹配同话题/同素材…')
            : '排队中（第 ${status.queuePosition} 位）…';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _PeerPhase.lobby;
        _error = '匹配失败：$error';
        _status = '请稍后重试';
      });
    }
  }

  Future<void> _createInviteRoom() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() {
        _error = '请先登录后再发邀请';
        _status = '未登录';
      });
      return;
    }
    setState(() {
      _phase = _PeerPhase.waitingInvite;
      _status = '房间已创建，等待他人接受邀请…';
      _error = null;
      _bubbles.clear();
      _roomId = null;
      _inviteId = null;
      _roomContent = _prefsContent;
      _session = null;
      _leftSent = false;
    });
    try {
      final OralMatchStatus status = await ref
          .read(acquireApiClientProvider)
          .createOralMatchInvite(content: _prefsContent);
      if (!mounted) return;
      if (status.isMatched) {
        await _onMatched(status);
        return;
      }
      _inviteId = status.inviteId;
      _matchPoll?.cancel();
      _matchPoll = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_pollMatch());
      });
      setState(() {
        _status = status.content.hasMaterial
            ? '邀请已发出 · ${status.content.title}'
            : '邀请已发出 · 话题 ${_prefsContent.topic}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _PeerPhase.lobby;
        _error = '发邀请失败：$error';
        _status = '请稍后重试';
      });
    }
  }

  Future<void> _refreshOpenInvites() async {
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    try {
      final List<OralMatchStatus> invites =
          await ref.read(acquireApiClientProvider).listOralMatchInvites();
      if (!mounted) return;
      setState(() => _openInvites = invites);
    } catch (_) {}
  }

  Future<void> _acceptInvite(OralMatchStatus invite) async {
    final String? inviteId = invite.inviteId;
    if (inviteId == null || inviteId.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在加入房间…';
    });
    try {
      final OralMatchStatus status = await ref
          .read(acquireApiClientProvider)
          .acceptOralMatchInvite(inviteId);
      if (!mounted) return;
      await _onMatched(status);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '接受邀请失败：$error';
        _status = '请刷新邀请列表后重试';
      });
    }
  }

  Future<void> _pollMatch() async {
    if (!mounted) return;
    if (_phase != _PeerPhase.matching && _phase != _PeerPhase.waitingInvite) {
      return;
    }
    try {
      final OralMatchStatus status =
          await ref.read(acquireApiClientProvider).oralMatchStatus();
      if (!mounted) return;
      if (status.isMatched) {
        _matchPoll?.cancel();
        await _onMatched(status);
        return;
      }
      if (status.isWaitingInvite) {
        setState(() {
          _phase = _PeerPhase.waitingInvite;
          _inviteId = status.inviteId;
          _roomContent = status.content.hasTopic || status.content.hasMaterial
              ? status.content
              : _roomContent;
          _status = '房间等待中 · 他人可在邀请列表接受';
        });
        return;
      }
      if (status.status == 'waiting') {
        setState(() {
          _phase = _PeerPhase.matching;
          _status = status.queuePosition == null
              ? '排队中，等待另一位学习者…'
              : '排队中（第 ${status.queuePosition} 位）…';
        });
        return;
      }
      if (_phase == _PeerPhase.matching) {
        await ref.read(acquireApiClientProvider).enqueueOralMatch(
              mode: _languageExchange ? 'language_exchange' : 'peer_oral',
              nativeLang: _languageExchange ? _nativeLang : '',
              targetLang: _languageExchange ? _targetLang : '',
              topic: _prefsContent.topic,
              content: _prefsContent,
            );
      }
    } catch (_) {}
  }

  Future<void> _onMatched(OralMatchStatus status) async {
    _roomId = status.roomId;
    _inviteId = null;
    _peerName = (status.peerDisplayName ?? '').isEmpty
        ? '口语搭子'
        : status.peerDisplayName!;
    _roomContent = status.content.hasTopic || status.content.hasMaterial
        ? status.content
        : _prefsContent;
    _session = null;
    final String material = _roomContent.hasMaterial
        ? (_roomContent.kind == 'article' ? '文章' : '视频') +
            '「${_roomContent.title}」'
        : '';
    final String topicBit =
        _roomContent.topic.isNotEmpty ? '话题：${_roomContent.topic}' : '';
    setState(() {
      _phase = _PeerPhase.chat;
      _busy = false;
      _peerOnline = status.peerOnline ?? true;
      _status = '已匹配 $_peerName · 正在接通实时语音…';
      _bubbles.add(
        _PeerBubble(
          role: 'system',
          text: <String>[
            '已匹配 $_peerName。',
            if (topicBit.isNotEmpty) topicBit,
            if (material.isNotEmpty) '围绕$material聊聊。',
            '可直接语音；需要时按住下方按钮：系统改语法/中译英后，再跟读发送。觉得地道可点星收藏。',
          ].join(' '),
        ),
      );
    });
    _startMessagePoll();
    _startHeartbeat();
    unawaited(_ensureLearningSession());
    await _connectVoice(status.livekit);
  }

  Future<void> _ensureLearningSession() async {
    if (_learningSessionId != null) return;
    try {
      final String sid =
          await ref.read(acquireApiClientProvider).startLearningSession(
                taskId: 'peer_oral',
                courseTitle: '真人口语对练',
                currentEnglish: 'Peer oral practice with $_peerName',
              );
      _learningSessionId = sid;
    } catch (_) {
      // Learning write is best-effort; voice/chat must still work.
    }
  }

  Future<void> _connectVoice(AcquireLiveKitToken? token) async {
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _status =
            '已匹配 $_peerName · 语音通道未配置，仍可用文字改写对练';
        _error = '服务器未配置 LiveKit，实时语音暂不可用';
      });
      return;
    }
    try {
      final String preferred =
          ref.read(learningSettingsProvider).liveKitUrl.trim();
      await _voice.connectWithToken(creds: token, preferredUrl: preferred);
      if (!mounted) return;
      setState(() {
        _voiceConnected = true;
        _micMuted = false;
        _status = _peerVoicePresent
            ? '实时语音已接通 · 也可按住做 AI 改写'
            : '语音已就绪，等待对方进入…';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '语音接通失败：$error';
        _status = '仍可用文字改写对练';
      });
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_sendHeartbeat());
    });
    unawaited(_sendHeartbeat());
  }

  Future<void> _sendHeartbeat() async {
    if (!mounted ||
        _roomId == null ||
        _phase == _PeerPhase.lobby ||
        _phase == _PeerPhase.ended) {
      return;
    }
    try {
      final OralMatchStatus status =
          await ref.read(acquireApiClientProvider).oralMatchHeartbeat();
      if (!mounted) return;
      if (status.peerLeft) {
        await _handlePeerLeft();
        return;
      }
      setState(() {
        _peerOnline = status.peerOnline ?? _peerOnline;
      });
    } catch (_) {}
  }

  void _startMessagePoll() {
    _messagePoll?.cancel();
    if (_roomId == null) return;
    _messagePoll = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pullPeerMessages());
    });
  }

  Future<void> _pullPeerMessages() async {
    final String? roomId = _roomId;
    if (!mounted ||
        roomId == null ||
        _phase == _PeerPhase.lobby ||
        _phase == _PeerPhase.ended) {
      return;
    }
    try {
      final OralMatchInbox inbox =
          await ref.read(acquireApiClientProvider).fetchOralMatchInbox(
                roomId: roomId,
                afterId: _lastMessageId,
              );
      if (!mounted) return;
      if (inbox.roomClosed) {
        await _handlePeerLeft();
        return;
      }
      setState(() {
        _peerOnline = inbox.peerOnline;
        for (final OralMatchMessage msg in inbox.messages) {
          _lastMessageId = msg.id;
          if (msg.mine) continue;
          _bubbles.add(
            _PeerBubble(
              role: msg.kind == 'system' ? 'system' : 'peer',
              text: msg.text,
            ),
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _handlePeerLeft() async {
    if (_phase == _PeerPhase.lobby || _phase == _PeerPhase.ended) return;
    _matchPoll?.cancel();
    _messagePoll?.cancel();
    _heartbeat?.cancel();
    await _voice.disconnect();
    if (!mounted) return;
    setState(() {
      _phase = _PeerPhase.lobby;
      _peerOnline = false;
      _voiceConnected = false;
      _roomId = null;
      _inviteId = null;
      _status = '对方已离开，可重新匹配或发邀请';
      _bubbles.add(
        const _PeerBubble(role: 'system', text: '对方已结束本次对练。'),
      );
    });
    unawaited(_refreshOpenInvites());
  }

  Future<void> _toggleMute() async {
    final bool next = !_micMuted;
    await _voice.setMicrophoneEnabled(enabled: !next);
    if (!mounted) return;
    setState(() {
      _micMuted = next;
      _status = next ? '已静音（对方听不到你）' : '麦克风已打开';
    });
  }

  Future<void> _reportPeer() async {
    final String? roomId = _roomId;
    if (roomId == null) return;
    final TextEditingController reason = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('举报对方'),
        content: TextField(
          controller: reason,
          maxLength: 200,
          decoration: const InputDecoration(hintText: '请简述原因'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    final String text = reason.text.trim();
    reason.dispose();
    if (ok != true || text.isEmpty || !mounted) return;
    try {
      await ref.read(acquireApiClientProvider).reportOralMatchPeer(
            roomId: roomId,
            reason: text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交举报')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '举报失败：$error');
    }
  }

  Future<OralCoachSession?> _ensureSession() async {
    if (_session != null) return _session;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String base = settings.oralCoachPipelineUrl.trim();
    if (base.isEmpty) {
      throw StateError('请先在设置中填写口语陪练管线地址。');
    }
    final OralMatchContent content = _roomContent;
    final String topic =
        content.topic.isNotEmpty ? content.topic : '日常口语';
    final String materialTitle =
        content.title.isNotEmpty ? content.title : 'peer practice';
    final String kindLabel = content.kind == 'article'
        ? 'article'
        : (content.kind == 'video' ? 'video' : 'conversation');
    final OralCoachSession session = await _pipeline.createSession(
      rawBaseUrl: base,
      context: OralCoachVideoContext(
        courseTitle: '真人口语对练',
        episodeTitle: materialTitle,
        topicSummary:
            'Peer oral about "$topic"${content.hasMaterial ? ' using $kindLabel "$materialTitle"' : ''}.',
        articleExcerpt:
            'Practice spoken English with a matched partner about "$topic". '
            '${content.hasMaterial ? 'Shared $kindLabel: $materialTitle. ' : ''}'
            'When the learner mixes Chinese, rewrite into natural idiomatic English. '
            'Correct grammar gently and keep the meaning.',
        difficulty: 'B1',
      ),
    );
    _session = session;
    return session;
  }

  Future<void> _holdStart() async {
    if (_busy || _recording) return;
    if (_phase == _PeerPhase.matching ||
        _phase == _PeerPhase.waitingInvite ||
        _phase == _PeerPhase.lobby ||
        _phase == _PeerPhase.ended) {
      return;
    }
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
      // Avoid fighting LiveKit for the exclusive audio session.
      await _voice.setMicrophoneEnabled(enabled: false);
      _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
      _recordingBytesWritten = 0;
      await _recordingSubscription?.cancel();
      final Stream<Uint8List> stream = await microphone.start();
      if (!mounted) {
        await microphone.cancel();
        await _restoreLiveMic();
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
            : '正在听你说（临时关闭实时麦）…';
        _error = null;
      });
    } catch (_) {
      await _restoreLiveMic();
      if (mounted) {
        setState(() => _error = '无法启动录音');
      }
    }
  }

  Future<void> _restoreLiveMic() async {
    if (!_voiceConnected || _micMuted) return;
    await _voice.setMicrophoneEnabled(enabled: true);
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
      await _restoreLiveMic();
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
      await _restoreLiveMic();
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

    unawaited(_recordLearningDiagnosis(source: confirmed, diagnosis: diagnosis));
    setState(() {
      _pending = diagnosis;
      _saved = false;
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
      _status = '先跟读地道英文，再说给对方听；觉得好可点星收藏';
    });
  }

  Future<void> _recordLearningDiagnosis({
    required String source,
    required OralExpressionDiagnosis diagnosis,
  }) async {
    await _ensureLearningSession();
    final String? sid = _learningSessionId;
    if (sid == null) return;
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    final String idiomatic = diagnosis.idiomaticEn.isNotEmpty
        ? diagnosis.idiomaticEn
        : diagnosis.literalEn;
    try {
      await api.appendLearningTurn(
        sessionId: sid,
        role: 'user',
        text: source,
        machineTranscript: source,
        confirmed: true,
      );
      if (idiomatic.trim().isNotEmpty) {
        await api.saveReviewExpression(
          expression: idiomatic,
          sourceQuote: source,
        );
        await api.finalizeLearningFeedback(
          sessionId: sid,
          items: <Map<String, dynamic>>[
            <String, dynamic>{
              'quote': source,
              'suggestion': idiomatic,
              'reason': diagnosis.tip.isNotEmpty
                  ? diagnosis.tip
                  : 'peer_oral_diagnosis',
            },
          ],
        );
      }
    } catch (_) {}
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

    if (_roomId != null) {
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

    final String? sid = _learningSessionId;
    if (sid != null) {
      try {
        await ref.read(acquireApiClientProvider).appendLearningTurn(
              sessionId: sid,
              role: 'user',
              text: confirmed,
              confirmed: true,
              scores: <String, dynamic>{'peer_sent': true},
            );
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _bubbles.add(_PeerBubble(role: 'me', text: confirmed, sent: true));
      _pending = null;
      _phase = _PeerPhase.chat;
      _preview.clear();
      _busy = false;
      _status = '已发给 $_peerName · 可继续语音或再改写';
    });
  }

  void _saveToBank(
    OralExpressionDiagnosis diagnosis, {
    bool notify = false,
  }) {
    final String english = diagnosis.idiomaticEn.isNotEmpty
        ? diagnosis.idiomaticEn
        : diagnosis.literalEn;
    if (english.trim().isEmpty) {
      if (notify && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无可收藏的地道表达')),
        );
      }
      return;
    }
    final bool added = ref.read(phraseBookProvider.notifier).addPhraseIfMissing(
          english: english,
          chinese: diagnosis.source,
          course: '口语诊断',
          episode: '真人口语对练',
          time: 'oral_idiomatic',
          needsReview: true,
          today: true,
          note: diagnosis.tip.isNotEmpty ? diagnosis.tip : 'peer_oral_diagnosis',
        );
    _saved = true;
    if (!notify || !mounted) return;
    final bool asSentence =
        english.trim().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).length >=
        5;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? (asSentence ? '已收藏到句子复习' : '已收藏到短语复习')
              : (asSentence ? '该句子已在复习队列中' : '该表达已在语言库中'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _cancelWaiting() async {
    _matchPoll?.cancel();
    final String? inviteId = _inviteId;
    await _leaveQuietly();
    if (inviteId != null && inviteId.isNotEmpty) {
      try {
        await ref.read(acquireApiClientProvider).cancelOralMatchInvite(inviteId);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _phase = _PeerPhase.lobby;
      _inviteId = null;
      _roomId = null;
      _status = '已取消，可重新选择话题或素材';
    });
    unawaited(_refreshOpenInvites());
  }

  Future<void> _endSession() async {
    _matchPoll?.cancel();
    _messagePoll?.cancel();
    _heartbeat?.cancel();
    await _voice.disconnect();
    await _leaveQuietly();
    if (!mounted) return;
    if (_phase == _PeerPhase.lobby) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    setState(() {
      _phase = _PeerPhase.lobby;
      _roomId = null;
      _inviteId = null;
      _voiceConnected = false;
      _status = '已结束，可重新匹配或发邀请';
    });
    unawaited(_refreshOpenInvites());
  }

  Future<void> _pickContent() async {
    final List<LibraryCourseData> courses = ref.read(libraryCatalogProvider);
    final List<ReadingDoc> articles =
        ref.read(readingLibraryProvider).builtin.take(20).toList();
    final OralMatchContent? picked = await showModalBottomSheet<OralMatchContent>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: <Widget>[
                  const TabBar(
                    tabs: <Widget>[
                      Tab(text: '视频课程'),
                      Tab(text: '文章阅读'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        ListView(
                          children: <Widget>[
                            ListTile(
                              leading: const Icon(Icons.clear),
                              title: const Text('不指定视频'),
                              onTap: () => Navigator.pop(
                                context,
                                OralMatchContent(topic: _selectedTopic),
                              ),
                            ),
                            for (final LibraryCourseData course
                                in courses.take(30))
                              ListTile(
                                leading: const Icon(Icons.movie_outlined),
                                title: Text(course.title),
                                subtitle: Text(
                                  course.episodes.isEmpty
                                      ? '课程'
                                      : '${course.episodes.length} 集',
                                ),
                                onTap: () => Navigator.pop(
                                  context,
                                  OralMatchContent(
                                    topic: _selectedTopic,
                                    kind: 'video',
                                    id: course.id,
                                    title: course.title,
                                    route: Uri(
                                      path: '/library',
                                      queryParameters: <String, String>{
                                        'courseId': course.id,
                                      },
                                    ).toString(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        ListView(
                          children: <Widget>[
                            ListTile(
                              leading: const Icon(Icons.clear),
                              title: const Text('不指定文章'),
                              onTap: () => Navigator.pop(
                                context,
                                OralMatchContent(topic: _selectedTopic),
                              ),
                            ),
                            for (final ReadingDoc doc in articles)
                              ListTile(
                                leading: const Icon(Icons.menu_book_outlined),
                                title: Text(doc.displayTitle),
                                subtitle: Text(
                                  doc.level.isEmpty
                                      ? '阅读'
                                      : '${doc.level} · ${doc.wordCount} 词',
                                ),
                                onTap: () => Navigator.pop(
                                  context,
                                  OralMatchContent(
                                    topic: _selectedTopic,
                                    kind: 'article',
                                    id: doc.id,
                                    title: doc.displayTitle,
                                    route:
                                        '/reading/${Uri.encodeComponent(doc.id)}',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedContent = picked);
  }

  Widget _buildLobby(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: <Widget>[
        const Text(
          '选择感兴趣的话题',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String topic in _kPeerTopics)
              ChoiceChip(
                label: Text(topic),
                selected: _selectedTopic == topic && !_languageExchange,
                onSelected: _languageExchange
                    ? null
                    : (bool selected) {
                        if (!selected) return;
                        setState(() => _selectedTopic = topic);
                      },
              ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          '选择视频或文章（可选）',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _selectedContent.kind == 'article'
                ? Icons.menu_book_outlined
                : Icons.movie_outlined,
          ),
          title: Text(
            _selectedContent.hasMaterial
                ? _selectedContent.title
                : '不指定具体素材，只按话题聊',
          ),
          subtitle: Text(
            _selectedContent.hasMaterial
                ? (_selectedContent.kind == 'article' ? '文章' : '视频')
                : '点这里从书库 / 阅读里挑',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(_pickContent()),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('语言交换模式'),
          subtitle: Text(
            _languageExchange
                ? '母语 $_nativeLang ↔ 目标语 $_targetLang'
                : '关闭时按普通口语搭子匹配',
          ),
          value: _languageExchange,
          onChanged: (bool v) => setState(() => _languageExchange = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_bootstrapMatch()),
          child: const Text('快速匹配同好'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => unawaited(_createInviteRoom()),
          child: const Text('创建房间并发邀请'),
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                '可接受的邀请',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_refreshOpenInvites()),
              child: const Text('刷新'),
            ),
          ],
        ),
        if (_openInvites.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '暂时没有开放邀请，你可以先创建房间。',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
        for (final OralMatchStatus invite in _openInvites)
          Card(
            child: ListTile(
              leading: const Icon(Icons.meeting_room_outlined),
              title: Text(
                invite.hostDisplayName?.isNotEmpty == true
                    ? invite.hostDisplayName!
                    : '口语搭子',
              ),
              subtitle: Text(
                <String>[
                  if (invite.content.topic.isNotEmpty) invite.content.topic,
                  if (invite.content.hasMaterial) invite.content.title,
                ].join(' · '),
              ),
              trailing: FilledButton(
                onPressed: _busy ? null : () => unawaited(_acceptInvite(invite)),
                child: const Text('接受'),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool gateResay =
        _phase == _PeerPhase.diagnose || _phase == _PeerPhase.resay;
    final bool canHold =
        _phase == _PeerPhase.chat ||
        _phase == _PeerPhase.diagnose ||
        _phase == _PeerPhase.resay;
    final bool inRoom = _phase == _PeerPhase.chat ||
        _phase == _PeerPhase.diagnose ||
        _phase == _PeerPhase.resay;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F0FF),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _phase == _PeerPhase.lobby ? '真人口语' : _peerName,
            ),
            Text(
              _phase == _PeerPhase.matching
                  ? '匹配中'
                  : (_phase == _PeerPhase.waitingInvite
                        ? '等待接受邀请'
                        : (_phase == _PeerPhase.lobby
                              ? '话题 · 素材 · 邀请'
                              : (_voiceConnected
                                    ? (_peerVoicePresent
                                          ? '实时语音已接通'
                                          : '语音就绪 · 等待对方')
                                    : (_peerOnline
                                          ? '在线 · 文字对练'
                                          : '对方可能离线')))),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: <Widget>[
          if (_voiceConnected && inRoom)
            IconButton(
              tooltip: _micMuted ? '取消静音' : '静音',
              onPressed: () => unawaited(_toggleMute()),
              icon: Icon(_micMuted ? Icons.mic_off : Icons.mic),
            ),
          if (_roomId != null && inRoom)
            IconButton(
              tooltip: '举报',
              onPressed: () => unawaited(_reportPeer()),
              icon: const Icon(Icons.flag_outlined),
            ),
          if (_roomContent.hasMaterial &&
              _roomContent.route.isNotEmpty &&
              inRoom)
            IconButton(
              tooltip: '打开素材',
              onPressed: () => context.push(_roomContent.route),
              icon: const Icon(Icons.open_in_new),
            ),
          IconButton(
            tooltip: _phase == _PeerPhase.lobby ? '关闭' : '结束',
            onPressed: () => unawaited(_endSession()),
            icon: Icon(
              _phase == _PeerPhase.lobby ? Icons.close : Icons.call_end,
            ),
          ),
        ],
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
            if (inRoom &&
                (_roomContent.hasTopic || _roomContent.hasMaterial))
              Material(
                color: const Color(0xFFEDE7FF),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    _roomContent.kind == 'article'
                        ? Icons.menu_book_outlined
                        : Icons.forum_outlined,
                  ),
                  title: Text(
                    _roomContent.hasMaterial
                        ? _roomContent.title
                        : _roomContent.topic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    <String>[
                      if (_roomContent.topic.isNotEmpty) _roomContent.topic,
                      if (_roomContent.kind == 'video') '视频话题',
                      if (_roomContent.kind == 'article') '文章话题',
                    ].join(' · '),
                  ),
                  trailing: _roomContent.route.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => context.push(_roomContent.route),
                        )
                      : null,
                ),
              ),
            Expanded(
              child: _phase == _PeerPhase.lobby
                  ? _buildLobby(context)
                  : (_phase == _PeerPhase.matching ||
                          _phase == _PeerPhase.waitingInvite)
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(_status, textAlign: TextAlign.center),
                          ),
                          if (_roomContent.hasMaterial) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              _roomContent.title,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          TextButton(
                            onPressed: () => unawaited(_cancelWaiting()),
                            child: const Text('取消'),
                          ),
                        ],
                      ),
                    )
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
                                _saveToBank(bubble.diagnosis!, notify: true);
                                setState(() => _saved = true);
                              },
                            ),
                          );
                        }
                        if (bubble.role == 'system') {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              bubble.text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
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
            if (canHold)
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
                                    : (gateResay ? '按住再说一次' : '按住 AI 改写')),
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

  final String role; // me | peer | diagnosis | system
  final String text;
  final OralExpressionDiagnosis? diagnosis;
  final bool sent;
}
