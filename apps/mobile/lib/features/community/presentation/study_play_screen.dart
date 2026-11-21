import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../avatar/presentation/avatar_preview.dart';
import '../../avatar/presentation/avatar_provider.dart';
import '../../avatar/presentation/avatar_shop_screen.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/study_activity_service.dart';
import 'study_desk_screen.dart';

/// Dark library-like palette from the approved check-in board design.
class _PlayTone {
  static const Color bg = Color(0xFF12141A);
  static const Color surface = Color(0xFF22252E);
  static const Color surface2 = Color(0xFF2A2E39);
  static const Color text = Color(0xFFF3F4F6);
  static const Color muted = Color(0xFFA5ADBB);
  static const Color blue = Color(0xFF1CB0F6);
  static const Color blueDim = Color(0x241CB0F6);
  static const Color border = Color(0x0FFFFFFF);
  static const Color disabled = Color(0xFF3A3E4A);
  static const Color disabledText = Color(0xFF8B919C);
  static const Color amber = Color(0xFFF0A020);
  static const Color sheet = Color(0xFF1A1D26);
}

class StudyPlayScreen extends ConsumerStatefulWidget {
  const StudyPlayScreen({super.key});
  @override
  ConsumerState<StudyPlayScreen> createState() => _StudyPlayScreenState();
}

class _StudyPlayScreenState extends ConsumerState<StudyPlayScreen> {
  Map<String, dynamic>? _checkin;
  Map<String, dynamic>? _battles;
  List<dynamic> _challenges = <dynamic>[];
  Map<String, dynamic>? _battle;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  int _step = -1;
  Timer? _animation;
  Timer? _returnMotion;
  bool _striking = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _generation++;
    _animation?.cancel();
    _returnMotion?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(String method, String path) =>
      ref.read(acquireApiClientProvider).studyPlayRequest(method, path);

  String _message(Object error) {
    if (error is DioException && error.response?.data is Map) {
      final Object? detail =
          (error.response!.data as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
    }
    return '服务暂时不可用，请重试。';
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    final String token = ref.read(authSessionProvider).accessToken;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> checkin = await _request('GET', '/checkin');
      final Map<String, dynamic> challenges = await _request(
        'GET',
        '/challenges',
      );
      Map<String, dynamic>? battles;
      try {
        battles = await _request('GET', '/battles');
      } catch (_) {
        battles = null;
      }
      if (mounted &&
          generation == _generation &&
          token == ref.read(authSessionProvider).accessToken) {
        setState(() {
          _checkin = checkin;
          _challenges = challenges['challenges'] as List<dynamic>? ?? <dynamic>[];
          _battles = battles;
        });
      }
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          token == ref.read(authSessionProvider).accessToken) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted &&
          generation == _generation &&
          token == ref.read(authSessionProvider).accessToken) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    final String token = ref.read(authSessionProvider).accessToken;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && token == ref.read(authSessionProvider).accessToken) {
        await _load();
        unawaited(ref.read(avatarMeProvider.notifier).refresh());
      }
    } catch (error) {
      if (mounted && token == ref.read(authSessionProvider).accessToken) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && token == ref.read(authSessionProvider).accessToken) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open(int id) async {
    final int generation = _generation;
    final String token = ref.read(authSessionProvider).accessToken;
    final Map<String, dynamic> battle = await _request('GET', '/battles/$id');
    if (!mounted ||
        generation != _generation ||
        token != ref.read(authSessionProvider).accessToken) {
      return;
    }
    _animation?.cancel();
    setState(() {
      _battle = battle;
      _step = -1;
    });
  }

  void _showStep(int index) {
    _returnMotion?.cancel();
    setState(() {
      _step = index;
      _striking = !MediaQuery.disableAnimationsOf(context);
    });
    if (_striking) {
      _returnMotion = Timer(const Duration(milliseconds: 350), () {
        if (mounted) setState(() => _striking = false);
      });
    }
  }

  String _battleText(String text, String mine, String peer) =>
      text.replaceAllMapped(
        RegExp(r'学员(\d+)'),
        (Match m) => m[1] == mine
            ? '我'
            : m[1] == peer
            ? '同桌'
            : '学员',
      );

  String _statsText(dynamic value) {
    final Map<String, dynamic> s = value as Map<String, dynamic>;
    return '近7天：${s['minutes']}分钟 · ${s['words']}条词句 · ${s['days']}天\n'
        '攻击 ${(s['attack'] as num).toStringAsFixed(1)} · '
        '护甲 ${(s['armor'] as num).toStringAsFixed(1)}';
  }

  void _play() {
    _animation?.cancel();
    final List<dynamic> steps =
        (_battle?['result'] as Map<String, dynamic>?)?['steps']
            as List<dynamic>? ??
        <dynamic>[];
    if (steps.isEmpty) return;
    setState(() => _step = -1);
    if (MediaQuery.disableAnimationsOf(context)) {
      _returnMotion?.cancel();
      setState(() {
        _step = steps.length - 1;
        _striking = false;
      });
      return;
    }
    _animation = Timer.periodic(const Duration(milliseconds: 850), (
      Timer timer,
    ) {
      if (!mounted || _step + 1 >= steps.length) {
        timer.cancel();
        return;
      }
      _showStep(_step + 1);
    });
  }

  String _rewardLabel(Object? reward) {
    switch ('$reward') {
      case 'bg.campus':
        return '校园背景';
      case 'accessory.headphones':
        return '耳机装扮';
      case 'top.hoodie':
        return '基础卫衣';
      default:
        return '$reward';
    }
  }

  String _datePill(Object? day) {
    final String raw = '$day';
    final Match? m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (m == null) return raw;
    return '${m[2]}-${m[3]}';
  }

  int _streakDays(List<dynamic> history) {
    if (history.isEmpty) return 0;
    final Set<String> days = history.map((dynamic e) => '$e').toSet();
    DateTime cursor = DateTime.now().toUtc().add(const Duration(hours: 8));
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    final String today =
        '${cursor.year.toString().padLeft(4, '0')}-'
        '${cursor.month.toString().padLeft(2, '0')}-'
        '${cursor.day.toString().padLeft(2, '0')}';
    if (!days.contains(today)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (true) {
      final String key =
          '${cursor.year.toString().padLeft(4, '0')}-'
          '${cursor.month.toString().padLeft(2, '0')}-'
          '${cursor.day.toString().padLeft(2, '0')}';
      if (!days.contains(key)) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<void> _openDesk() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const StudyDeskScreen()),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _showTipSheet({
    required String title,
    required List<({String title, String body})> rules,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _PlayTone.sheet,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(
                  top: BorderSide(color: Color(0x14FFFFFF)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0x2EFFFFFF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        color: _PlayTone.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '仅在需要时展开，不占主界面',
                      style: TextStyle(
                        color: _PlayTone.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < rules.length; i++) ...<Widget>[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          color: Color(0x0DFFFFFF),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _PlayTone.blueDim,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: _PlayTone.blue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    rules[i].title,
                                    style: const TextStyle(
                                      color: _PlayTone.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    rules[i].body,
                                    style: const TextStyle(
                                      color: _PlayTone.muted,
                                      fontSize: 12,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _PlayTone.blue,
                          foregroundColor: const Color(0xFF041018),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          '知道了',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authSessionProvider.select((AuthSessionState s) => s.accessToken),
      (String? old, String next) {
        _generation++;
        _animation?.cancel();
        setState(() {
          _checkin = null;
          _challenges = <dynamic>[];
          _busy = false;
          _battles = null;
          _battle = null;
          _error = '账号已切换，请重新进入。';
        });
      },
    );
    final Map<String, String> mine =
        ref.watch(avatarMeProvider).asData?.value.loadout ??
        <String, String>{'body': 'body.cartoon1'};

    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _PlayTone.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _PlayTone.bg,
          foregroundColor: _PlayTone.text,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: _PlayTone.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: _PlayTone.text),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: _PlayTone.surface2,
          contentTextStyle: TextStyle(color: _PlayTone.text),
        ),
        dividerColor: const Color(0x14FFFFFF),
      ),
      child: Scaffold(
        backgroundColor: _PlayTone.bg,
        appBar: AppBar(
          title: const Text('一起练 · 打卡与大比武'),
          actions: <Widget>[
            IconButton(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新',
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
          children: <Widget>[
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              _PlayCard(
                child: Text(
                  _error!,
                  style: const TextStyle(color: _PlayTone.muted, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _avatarCard(mine),
            const SizedBox(height: 10),
            if (_checkin != null) ...<Widget>[
              _checkinCard(_checkin!),
              const SizedBox(height: 10),
            ],
            _challengesCard(),
            const SizedBox(height: 10),
            _battleBoardCard(),
            if (_battle?['result'] != null) ...<Widget>[
              const SizedBox(height: 10),
              _battleCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avatarCard(Map<String, String> mine) {
    return _PlayCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF2E3444), Color(0xFF1A1D26)],
              ),
              border: Border.all(color: _PlayTone.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: AvatarPreview(loadout: mine, height: 48),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '我的形象',
                  style: TextStyle(
                    color: _PlayTone.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '查看与更换装扮',
                  style: TextStyle(color: _PlayTone.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _PlayTone.blue,
              side: BorderSide(color: _PlayTone.blue.withValues(alpha: 0.55)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const AvatarShopScreen(),
              ),
            ),
            child: const Text(
              '背包商店',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkinCard(Map<String, dynamic> checkin) {
    final int reviewCount = (checkin['review_count'] as num?)?.toInt() ?? 0;
    final int reviewTarget = (checkin['review_target'] as num?)?.toInt() ?? 5;
    final int seconds = (checkin['seconds'] as num?)?.toInt() ?? 0;
    final bool claimed = checkin['claimed'] == true;
    final bool eligible = checkin['eligible'] == true;
    final List<dynamic> history =
        checkin['history'] as List<dynamic>? ?? <dynamic>[];
    final int streak = _streakDays(history);
    final bool canClaim = !_busy && eligible && !claimed;

    return _PlayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardHead(
            title: '今日打卡',
            trailing: <Widget>[
              _DatePill(label: _datePill(checkin['day'])),
              _TipButton(
                onTap: () => _showTipSheet(
                  title: '今日打卡说明',
                  rules: const <({String title, String body})>[
                    (
                      title: '达标条件',
                      body: '复习核验 5 条，或限速播放满 600 秒',
                    ),
                    (
                      title: '每日积分',
                      body: '确认打卡后发放 +10；双方同日完成另有加成',
                    ),
                    (
                      title: '7 天礼物',
                      body: '累计 7 天打卡赠送基础卫衣；不依赖同桌、不随机',
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricTile(
                  label: '复习核验',
                  value: '$reviewCount',
                  suffix: ' / $reviewTarget',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: '限速播放',
                  value: '$seconds',
                  suffix: ' / 600秒',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: _PlayTone.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    children: <InlineSpan>[
                      TextSpan(text: '完成可得 '),
                      TextSpan(
                        text: '+10',
                        style: TextStyle(
                          color: _PlayTone.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: ' 积分'),
                    ],
                  ),
                ),
              ),
              Text(
                '连续 $streak / 7 天',
                style: const TextStyle(color: _PlayTone.muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _OutlineAction(
            label: '同步并刷新',
            enabled: !_busy,
            onPressed: () => _action(() async {
              await ref.read(studyActivityServiceProvider).touchReview();
              final String message =
                  await ref.read(dailyReviewProvider.notifier).syncCloudBackup();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(message)),
                );
              }
            }),
          ),
          const SizedBox(height: 8),
          _PrimaryAction(
            label: claimed ? '今日已打卡' : '确认打卡',
            enabled: canClaim,
            onPressed: () => _action(() async {
              final Map<String, dynamic> result =
                  await _request('POST', '/checkin');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['awarded'] == true
                          ? '打卡成功，10积分已到账；双方完成时另有2积分加成。'
                          : '今天已打卡，不重复发放。',
                    ),
                  ),
                );
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _challengesCard() {
    return _PlayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardHead(
            title: '7天一起坚持',
            trailing: <Widget>[
              _TipButton(
                onTap: () => _showTipSheet(
                  title: '7天一起坚持说明',
                  rules: const <({String title, String body})>[
                    (
                      title: '如何计入',
                      body: '加入后累计 7 个不同打卡日，不要求连续',
                    ),
                    (
                      title: '共用记录',
                      body: '两条活动共用个人打卡，不额外要求公开发帖',
                    ),
                    (
                      title: '奖励领取',
                      body: '满 7 天后可领取确定装扮；退出保留进度',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_challenges.isEmpty)
            const Text(
              '活动加载中…',
              style: TextStyle(color: _PlayTone.muted, fontSize: 13),
            )
          else
            for (int i = 0; i < _challenges.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 8),
              _ChallengeRow(
                challenge: _challenges[i] as Map<String, dynamic>,
                busy: _busy,
                rewardLabel: _rewardLabel,
                onJoinLeave: (Map<String, dynamic> challenge) => _action(
                  () async {
                    final bool joined = challenge['joined'] == true;
                    await _request(
                      'POST',
                      '/challenges/${challenge['id']}/${joined ? 'leave' : 'join'}',
                    );
                  },
                ),
                onClaim: (Map<String, dynamic> challenge) => _action(() async {
                  await _request(
                    'POST',
                    '/challenges/${challenge['id']}/claim',
                  );
                }),
              ),
            ],
        ],
      ),
    );
  }

  Widget _battleBoardCard() {
    final bool needDeskmate =
        _battles == null || _battles!['need_deskmate'] == true;
    final bool peerVirtual = _battles?['peer_virtual'] == true;
    final bool canBattle = _battles?['can_battle'] == true;
    final List<dynamic> matches =
        _battles?['matches'] as List<dynamic>? ?? <dynamic>[];

    String statusText;
    if (needDeskmate) {
      statusText = '需先建立同桌关系';
    } else if (!canBattle) {
      statusText = '双方需开启学习统计共享';
    } else if (peerVirtual) {
      statusText = '练习搭子已就绪，可随时切磋';
    } else {
      statusText = '同桌已配对，可发起切磋';
    }

    return _PlayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardHead(
            title: '学习力大比武',
            trailing: <Widget>[
              _TipButton(
                onTap: () => _showTipSheet(
                  title: '学习力大比武说明',
                  rules: const <({String title, String body})>[
                    (
                      title: '对手',
                      body: '需先寻找同桌；无人可配时自动分配练习搭子',
                    ),
                    (
                      title: '属性来源',
                      body: '近 7 天核验学习记录形成攻击/护甲，±10% 浮动',
                    ),
                    (
                      title: '结果',
                      body: '装扮不影响战斗；动画重播不重掷，也不发胜负积分',
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: needDeskmate
                      ? _PlayTone.amber
                      : canBattle
                      ? _PlayTone.blue
                      : _PlayTone.muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: _PlayTone.muted,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Expanded(
                child: _MiniStat(label: '周期', value: '近 7 天'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: '对手',
                  value: needDeskmate
                      ? '同桌'
                      : peerVirtual
                      ? '练习搭子'
                      : '同桌',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (needDeskmate)
            _PrimaryAction(
              label: '寻找同桌',
              enabled: !_busy,
              onPressed: _openDesk,
            )
          else ...<Widget>[
            _PrimaryAction(
              label: peerVirtual ? '与练习搭子切磋' : '开始比武',
              enabled: !_busy && canBattle,
              onPressed: () => _action(() async {
                final Map<String, dynamic> created =
                    await _request('POST', '/battles');
                if (created['status'] == 'completed' &&
                    created['id'] != null &&
                    mounted) {
                  await _open(created['id'] as int);
                }
              }),
            ),
            if (!canBattle) ...<Widget>[
              const SizedBox(height: 8),
              _OutlineAction(
                label: '去同桌页开启共享',
                enabled: !_busy,
                onPressed: _openDesk,
              ),
            ],
            for (final dynamic raw in matches)
              _MatchTile(
                match: raw as Map<String, dynamic>,
                busy: _busy,
                onAccept: (int id) => _action(() async {
                  await _request('POST', '/battles/$id/accept');
                  await _open(id);
                }),
                onDeclineOrCancel: ({
                  required int id,
                  required bool incoming,
                }) =>
                    _action(() async {
                      await _request(
                        'POST',
                        '/battles/$id/${incoming ? 'decline' : 'cancel'}',
                      );
                    }),
                onReplay: (int id) => _action(() => _open(id)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _battleCard() {
    final Map<String, dynamic> result =
        _battle!['result'] as Map<String, dynamic>;
    final List<dynamic> steps = result['steps'] as List<dynamic>;
    final String myId = '${_battle!['my_id']}';
    final String peerId = '${_battle!['peer_id']}';
    final Map<String, dynamic>? step =
        _step < 0 ? null : steps[_step] as Map<String, dynamic>;
    final Map<String, dynamic> health = step == null
        ? <String, dynamic>{myId: 100, peerId: 100}
        : step['health'] as Map<String, dynamic>;
    final Map<String, dynamic> avatars =
        (result['avatars'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final bool done = _step >= steps.length - 1;
    final bool peerVirtual = _battles?['peer_virtual'] == true;
    final String peerLabel = peerVirtual ? '练习搭子' : '同桌';

    return _PlayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '第 ${_battle!['id']} 场战报',
            style: const TextStyle(
              color: _PlayTone.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              for (final String id in <String>[myId, peerId])
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Text(
                        id == myId ? '我' : peerLabel,
                        style: const TextStyle(
                          color: _PlayTone.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'HP ${health[id]} / 100',
                        style: const TextStyle(
                          color: _PlayTone.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (health[id] as num).toDouble() / 100,
                          minHeight: 6,
                          backgroundColor: const Color(0x14FFFFFF),
                          color: _PlayTone.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedSlide(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 230),
                        offset: _striking &&
                                step != null &&
                                '${step['attacker']}' == id
                            ? Offset(id == myId ? .12 : -.12, 0)
                            : Offset.zero,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _striking &&
                                  step != null &&
                                  '${step['target']}' == id
                              ? .65
                              : 1,
                          child: AvatarPreview(
                            loadout: () {
                              final Object? raw = avatars[id];
                              if (raw is Map && raw.isNotEmpty) {
                                return raw.cast<String, String>();
                              }
                              return <String, String>{
                                'body': id == myId
                                    ? 'body.cartoon1'
                                    : 'body.cartoon2',
                              };
                            }(),
                            height: 140,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            step == null
                ? '双方准备就绪 · 100 HP'
                : '第${step['round']}回合 · ${step['action']}\n'
                    '${_battleText('${step['text']}', myId, peerId)}',
            style: const TextStyle(
              color: _PlayTone.text,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          if (done)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                result['winner'] == null
                    ? '本场平局'
                    : '${result['winner']}' == myId
                    ? '本场你获胜'
                    : '本场$peerLabel获胜',
                style: const TextStyle(
                  color: _PlayTone.blue,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _PlayTone.blue,
                  foregroundColor: const Color(0xFF041018),
                ),
                onPressed: _play,
                child: const Text('播放 / 重播动画'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: _PlayTone.blue),
                onPressed: () {
                  _animation?.cancel();
                  _showStep((_step + 1).clamp(0, steps.length - 1));
                },
                child: const Text('下一动作'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: _PlayTone.muted),
                onPressed: () {
                  _animation?.cancel();
                  _returnMotion?.cancel();
                  setState(() {
                    _step = steps.length - 1;
                    _striking = false;
                  });
                },
                child: const Text('跳过动画'),
              ),
            ],
          ),
          Material(
            color: Colors.transparent,
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  '完整战斗日志与属性',
                  style: TextStyle(color: _PlayTone.muted, fontSize: 13),
                ),
                iconColor: _PlayTone.muted,
                collapsedIconColor: _PlayTone.muted,
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      () {
                        final Map<String, dynamic> stats =
                            result['stats'] as Map<String, dynamic>;
                        return '我：${_statsText(stats[myId])}\n'
                            '$peerLabel：${_statsText(stats[peerId])}';
                      }(),
                      style: const TextStyle(
                        color: _PlayTone.text,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final dynamic row in steps)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '回合${(row as Map<String, dynamic>)['round']} · '
                          '${_battleText('${row['text']}', myId, peerId)}',
                          style: const TextStyle(
                            color: _PlayTone.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayCard extends StatelessWidget {
  const _PlayCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _PlayTone.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _PlayTone.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _CardHead extends StatelessWidget {
  const _CardHead({required this.title, required this.trailing});

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _PlayTone.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _PlayTone.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: _PlayTone.muted, fontSize: 11),
      ),
    );
  }
}

class _TipButton extends StatelessWidget {
  const _TipButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _PlayTone.muted.withValues(alpha: 0.35)),
        ),
        child: const Text(
          '?',
          style: TextStyle(
            color: _PlayTone.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.suffix,
  });

  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _PlayTone.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(color: _PlayTone.muted, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: _PlayTone.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.02,
                ),
                children: <InlineSpan>[
                  TextSpan(text: value),
                  TextSpan(
                    text: suffix,
                    style: const TextStyle(
                      color: _PlayTone.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _PlayTone.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(color: _PlayTone.muted, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: _PlayTone.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: _PlayTone.blue,
          disabledForegroundColor: _PlayTone.disabledText,
          side: BorderSide(
            color: enabled
                ? _PlayTone.blue
                : _PlayTone.disabledText.withValues(alpha: 0.35),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? _PlayTone.blue : _PlayTone.disabled,
          foregroundColor:
              enabled ? const Color(0xFF041018) : _PlayTone.disabledText,
          disabledBackgroundColor: _PlayTone.disabled,
          disabledForegroundColor: _PlayTone.disabledText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({
    required this.challenge,
    required this.busy,
    required this.rewardLabel,
    required this.onJoinLeave,
    required this.onClaim,
  });

  final Map<String, dynamic> challenge;
  final bool busy;
  final String Function(Object? reward) rewardLabel;
  final void Function(Map<String, dynamic> challenge) onJoinLeave;
  final void Function(Map<String, dynamic> challenge) onClaim;

  @override
  Widget build(BuildContext context) {
    final int progress = (challenge['progress'] as num?)?.toInt() ?? 0;
    final bool joined = challenge['joined'] == true;
    final bool claimed = challenge['claimed'] == true;
    final bool canClaim = joined && !claimed && progress >= 7;

    String actionLabel;
    if (!joined) {
      actionLabel = '加入';
    } else if (claimed) {
      actionLabel = '已领取';
    } else if (canClaim) {
      actionLabel = '领取';
    } else {
      actionLabel = '退出';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _PlayTone.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${challenge['title']}',
              style: const TextStyle(
                color: _PlayTone.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (progress.clamp(0, 7)) / 7,
                      minHeight: 6,
                      backgroundColor: const Color(0x14FFFFFF),
                      color: _PlayTone.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$progress/7',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: _PlayTone.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x0AFFFFFF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _PlayTone.border),
                  ),
                  child: Text(
                    '奖励 · ${rewardLabel(challenge['reward'])}',
                    style: const TextStyle(
                      color: _PlayTone.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _PlayTone.blue,
                    disabledForegroundColor: _PlayTone.disabledText,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: busy
                      ? null
                      : claimed
                      ? null
                      : canClaim
                      ? () => onClaim(challenge)
                      : () => onJoinLeave(challenge),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.match,
    required this.busy,
    required this.onAccept,
    required this.onDeclineOrCancel,
    required this.onReplay,
  });

  final Map<String, dynamic> match;
  final bool busy;
  final void Function(int id) onAccept;
  final void Function({required int id, required bool incoming})
      onDeclineOrCancel;
  final void Function(int id) onReplay;

  @override
  Widget build(BuildContext context) {
    final int id = match['id'] as int;
    final String status = '${match['status']}';
    final bool incoming = match['incoming'] == true;
    final String statusLabel = status == 'completed'
        ? '已完成'
        : status == 'pending'
        ? '等待接受'
        : '已结束';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _PlayTone.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '第 $id 场 · $statusLabel',
                style: const TextStyle(
                  color: _PlayTone.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (status == 'pending')
                Wrap(
                  children: <Widget>[
                    if (incoming)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: _PlayTone.blue,
                        ),
                        onPressed: busy ? null : () => onAccept(id),
                        child: const Text('接受并生成对局'),
                      ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: _PlayTone.muted,
                      ),
                      onPressed: busy
                          ? null
                          : () => onDeclineOrCancel(
                                id: id,
                                incoming: incoming,
                              ),
                      child: Text(incoming ? '婉拒' : '撤回'),
                    ),
                  ],
                )
              else if (status == 'completed')
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: _PlayTone.blue),
                  onPressed: busy ? null : () => onReplay(id),
                  child: const Text('播放战报'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
