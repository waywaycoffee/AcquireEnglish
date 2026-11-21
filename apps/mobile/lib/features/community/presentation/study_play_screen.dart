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

class StudyPlayScreen extends ConsumerStatefulWidget {
  const StudyPlayScreen({super.key});
  @override
  ConsumerState<StudyPlayScreen> createState() => _StudyPlayScreenState();
}

class _StudyPlayScreenState extends ConsumerState<StudyPlayScreen> {
  Map<String, dynamic>? _checkin;
  Map<String, dynamic>? _battles;
  List<dynamic> _challenges = [];
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
          token == ref.read(authSessionProvider).accessToken)
        setState(() {
          _checkin = checkin;
          _challenges = challenges['challenges'] as List<dynamic>;
          _battles = battles;
        });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          token == ref.read(authSessionProvider).accessToken)
        setState(() => _error = _message(error));
    } finally {
      if (mounted &&
          generation == _generation &&
          token == ref.read(authSessionProvider).accessToken)
        setState(() => _busy = false);
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
      if (mounted && token == ref.read(authSessionProvider).accessToken)
        setState(() => _error = _message(error));
    } finally {
      if (mounted && token == ref.read(authSessionProvider).accessToken)
        setState(() => _busy = false);
    }
  }

  Future<void> _open(int id) async {
    final int generation = _generation;
    final String token = ref.read(authSessionProvider).accessToken;
    final Map<String, dynamic> battle = await _request('GET', '/battles/$id');
    if (!mounted ||
        generation != _generation ||
        token != ref.read(authSessionProvider).accessToken)
      return;
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
    if (_striking)
      _returnMotion = Timer(const Duration(milliseconds: 350), () {
        if (mounted) setState(() => _striking = false);
      });
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
    return '近7天：${s['minutes']}分钟 · ${s['words']}条词句 · ${s['days']}天\n攻击 ${(s['attack'] as num).toStringAsFixed(1)} · 护甲 ${(s['armor'] as num).toStringAsFixed(1)}';
  }

  void _play() {
    _animation?.cancel();
    final List<dynamic> steps =
        (_battle?['result'] as Map<String, dynamic>?)?['steps']
            as List<dynamic>? ??
        [];
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

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    ref.listen(
      authSessionProvider.select((AuthSessionState s) => s.accessToken),
      (String? old, String next) {
        _generation++;
        _animation?.cancel();
        setState(() {
          _checkin = null;
          _challenges = [];
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('一起练 · 打卡与大比武'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) _card('提示', <Widget>[Text(_error!)]),
          _card('我的个人形象', <Widget>[
            Center(child: AvatarPreview(loadout: mine, height: 170)),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AvatarShopScreen(),
                ),
              ),
              child: const Text('背包与形象商店'),
            ),
          ]),
          if (_checkin != null)
            _card('今日打卡 · ${_checkin!['day']}', <Widget>[
              Text(
                '复习核验 ${_checkin!['review_count']} / ${_checkin!['review_target']} 条',
              ),
              Text(
                '服务器限速累计播放 ${(_checkin!['seconds'] as num).toInt()} / 600 秒',
              ),
              Text(
                '${_checkin!['rule']}',
                style: const TextStyle(fontSize: 12),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                        await ref
                            .read(studyActivityServiceProvider)
                            .touchReview();
                        final String message = await ref
                            .read(dailyReviewProvider.notifier)
                            .syncCloudBackup();
                        if (mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                      }),
                child: const Text('同步复习并刷新资格'),
              ),
              FilledButton(
                onPressed:
                    _busy ||
                        _checkin!['eligible'] != true ||
                        _checkin!['claimed'] == true
                    ? null
                    : () => _action(() async {
                        final Map<String, dynamic> result = await _request(
                          'POST',
                          '/checkin',
                        );
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result['awarded'] == true
                                    ? '打卡成功，10积分已到账；双方完成时另有2积分加成。'
                                    : '今天已打卡，不重复发放。',
                              ),
                            ),
                          );
                      }),
                child: Text(
                  _checkin!['claimed'] == true ? '今日已打卡' : '确认打卡并领取积分',
                ),
              ),
              Text('最近打卡：${(_checkin!['history'] as List<dynamic>).join('、')}'),
              const Text(
                '累计7天打卡赠送指定基础卫衣。个人打卡不依赖同桌，奖励不随机。',
                style: TextStyle(fontSize: 12),
              ),
            ]),
          _card('7天一起坚持活动', <Widget>[
            for (final dynamic challenge in _challenges)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${challenge['title']} · ${challenge['progress']} / 7 天',
                    ),
                    Text(
                      '${challenge['rule']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '确定奖励：${challenge['reward'] == 'bg.campus' ? '校园背景' : '耳机装扮'}',
                    ),
                    Wrap(
                      children: <Widget>[
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _action(() async {
                                  await _request(
                                    'POST',
                                    '/challenges/${challenge['id']}/${challenge['joined'] == true ? 'leave' : 'join'}',
                                  );
                                }),
                          child: Text(
                            challenge['joined'] == true ? '退出活动（保留进度）' : '加入活动',
                          ),
                        ),
                        if (challenge['joined'] == true)
                          TextButton(
                            onPressed:
                                _busy ||
                                    challenge['claimed'] == true ||
                                    (challenge['progress'] as int) < 7
                                ? null
                                : () => _action(() async {
                                    await _request(
                                      'POST',
                                      '/challenges/${challenge['id']}/claim',
                                    );
                                  }),
                            child: Text(
                              challenge['claimed'] == true ? '奖励已领取' : '领取确定奖励',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ]),
          _card('学习力大比武', <Widget>[
            const Text('以最近7天核验学习记录形成属性，加入±10%随机浮动。装扮不影响战斗，动画重播不重掷结果，也不发胜负积分。'),
            if (_battles == null || _battles!['need_deskmate'] == true) ...<Widget>[
              const Text('还没有同桌时，先去寻找同桌（无人可配会分配练习搭子），打卡不受影响。'),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const StudyDeskScreen(),
                          ),
                        ),
                child: const Text('去寻找同桌'),
              ),
            ] else ...<Widget>[
              if (_battles!['can_battle'] != true)
                const Text('双方需在同桌页开启学习统计共享，再邀请切磋。'),
              FilledButton(
                onPressed: _busy || _battles!['can_battle'] != true
                    ? null
                    : () => _action(() async {
                        final Map<String, dynamic> created =
                            await _request('POST', '/battles');
                        if (created['status'] == 'completed' &&
                            created['id'] != null &&
                            mounted) {
                          await _open(created['id'] as int);
                        }
                      }),
                child: Text(
                  _battles!['peer_virtual'] == true ? '与练习搭子切磋' : '向同桌发起切磋',
                ),
              ),
              for (final dynamic match in _battles!['matches'] as List<dynamic>)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '第 ${match['id']} 场 · ${match['status'] == 'completed'
                        ? '已完成'
                        : match['status'] == 'pending'
                        ? '等待接受'
                        : '已结束'}',
                  ),
                  subtitle: match['status'] == 'pending'
                      ? Wrap(
                          children: <Widget>[
                            if (match['incoming'] == true)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _action(() async {
                                        await _request(
                                          'POST',
                                          '/battles/${match['id']}/accept',
                                        );
                                        await _open(match['id'] as int);
                                      }),
                                child: const Text('接受并生成对局'),
                              ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _action(() async {
                                      await _request(
                                        'POST',
                                        '/battles/${match['id']}/${match['incoming'] == true ? 'decline' : 'cancel'}',
                                      );
                                    }),
                              child: Text(
                                match['incoming'] == true ? '婉拒' : '撤回',
                              ),
                            ),
                          ],
                        )
                      : null,
                  trailing: match['status'] == 'completed'
                      ? TextButton(
                          onPressed: _busy
                              ? null
                              : () => _action(() => _open(match['id'] as int)),
                          child: const Text('播放战报'),
                        )
                      : null,
                ),
            ],
          ]),
          if (_battle?['result'] != null) _battleCard(),
        ],
      ),
    );
  }

  Widget _battleCard() {
    final Map<String, dynamic> result =
        _battle!['result'] as Map<String, dynamic>;
    final List<dynamic> steps = result['steps'] as List<dynamic>;
    final String myId = '${_battle!['my_id']}',
        peerId = '${_battle!['peer_id']}';
    final Map<String, dynamic> health = _step < 0
        ? <String, dynamic>{myId: 100, peerId: 100}
        : steps[_step]['health'] as Map<String, dynamic>;
    final Map<String, dynamic>? step = _step < 0
        ? null
        : steps[_step] as Map<String, dynamic>;
    final Map<String, dynamic> avatars =
        (result['avatars'] as Map<String, dynamic>?) ?? {};
    final bool done = _step >= steps.length - 1;
    return _card('第 ${_battle!['id']} 场战报', <Widget>[
      Row(
        children: <Widget>[
          for (final String id in <String>[myId, peerId])
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(id == myId ? '我' : '同桌'),
                  Text('HP ${health[id]} / 100'),
                  LinearProgressIndicator(
                    value: (health[id] as num).toDouble() / 100,
                  ),
                  AnimatedSlide(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 230),
                    offset:
                        _striking && step != null && '${step['attacker']}' == id
                        ? Offset(id == myId ? .12 : -.12, 0)
                        : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity:
                          _striking && step != null && '${step['target']}' == id
                          ? .65
                          : 1,
                      child: AvatarPreview(
                        loadout:
                            avatars[id] is Map &&
                                (avatars[id] as Map).isNotEmpty
                            ? (avatars[id] as Map).cast<String, String>()
                            : <String, String>{
                                'body': id == myId
                                    ? 'body.cartoon1'
                                    : 'body.cartoon2',
                              },
                        height: 160,
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
            : '第${step['round']}回合 · ${step['action']}\n${_battleText('${step['text']}', myId, peerId)}',
      ),
      if (done)
        Text(
          result['winner'] == null
              ? '本场平局'
              : '${result['winner']}' == myId
              ? '本场你获胜'
              : '本场同桌获胜',
        ),
      Wrap(
        spacing: 8,
        children: <Widget>[
          FilledButton(onPressed: _play, child: const Text('播放 / 重播动画')),
          TextButton(
            onPressed: () {
              _animation?.cancel();
              _showStep((_step + 1).clamp(0, steps.length - 1));
            },
            child: const Text('下一动作'),
          ),
          TextButton(
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
      ExpansionTile(
        title: const Text('完整战斗日志与属性'),
        children: <Widget>[
          Text(
            '我：${_statsText(result['stats'][myId])}\n同桌：${_statsText(result['stats'][peerId])}',
          ),
          for (final dynamic row in steps)
            Text(
              '回合${row['round']} · ${_battleText('${row['text']}', myId, peerId)}',
            ),
        ],
      ),
    ]);
  }
}
