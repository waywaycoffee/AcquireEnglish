import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../words/presentation/word_book_provider.dart';

class StudyPkScreen extends ConsumerStatefulWidget {
  const StudyPkScreen({super.key, this.embedded = false});

  /// When true, omit the outer [Scaffold] so [PadScaffold] can own chrome.
  final bool embedded;

  @override
  ConsumerState<StudyPkScreen> createState() => _StudyPkScreenState();
}

class _StudyPkScreenState extends ConsumerState<StudyPkScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _lobby;
  Map<String, dynamic>? _match;
  String? _error;
  bool _busy = false;
  int _days = 7;
  int _count = 10;
  String _source = 'intersection'; // intersection | syllabus
  List<Map<String, dynamic>> _syllabusUnits = <Map<String, dynamic>>[];
  String? _bookId;
  int _unitIndex = 0;
  int? _selected;
  int _seconds = 0;
  int _generation = 0;
  Timer? _timer;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_load);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _deadline == null) return;
      final int remaining = _deadline!
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, 20);
      if (_seconds != remaining) setState(() => _seconds = remaining);
    });
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      if (_match == null) {
        unawaited(_load());
      } else {
        unawaited(_open(_match!['id'] as int));
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) => ref
      .read(acquireApiClientProvider)
      .studyPkRequest(method, path, data: data);

  String _message(Object error) {
    if (error is DioException && error.response?.data is Map) {
      final Object? detail =
          (error.response!.data as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
    }
    return '暂时无法连接PK服务，请重试。';
  }

  Future<void> _loadSyllabusUnits() async {
    try {
      final Map<String, dynamic> payload = await _request(
        'GET',
        '/syllabus-units',
      );
      final List<Map<String, dynamic>> units =
          (payload['units'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((Map row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _syllabusUnits = units;
        if (units.isEmpty) {
          _bookId = null;
          _unitIndex = 0;
          return;
        }
        final bool keep = units.any(
          (Map<String, dynamic> u) =>
              u['book_id'] == _bookId && u['unit_index'] == _unitIndex,
        );
        if (!keep) {
          _bookId = '${units.first['book_id']}';
          _unitIndex = (units.first['unit_index'] as num?)?.toInt() ?? 0;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _syllabusUnits = <Map<String, dynamic>>[]);
    }
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> lobby = await _request('GET', '');
      if (mounted && generation == _generation) {
        setState(() => _lobby = lobby);
        unawaited(_loadSyllabusUnits());
      }
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() {
          _lobby = null;
          _error = _message(error);
        });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  String _sourceLabel(Map<String, dynamic> match) {
    final String source = '${match['source'] ?? ''}';
    if (source == 'syllabus') {
      final String book = '${match['book_title'] ?? match['book_id'] ?? '词书'}';
      final String unit = '${match['unit_label'] ?? ''}';
      return unit.isEmpty ? book : '$book · $unit';
    }
    if (source == 'cafe') return '约定词表';
    return '近${match['days']}天';
  }

  Future<void> _open(int id) async {
    final int generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> match = await _request('GET', '/$id');
      if (!mounted || generation != _generation) return;
      final Map<String, dynamic>? question =
          match['question'] as Map<String, dynamic>?;
      setState(() {
        _match = match;
        _selected = null;
        _seconds = (question?['seconds_remaining'] as num?)?.toInt() ?? 0;
        _deadline = question == null
            ? null
            : DateTime.now().add(Duration(seconds: _seconds));
      });
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() {
          _match = null;
          _error = _message(error);
        });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      if (!mounted) return;
      if (_match == null) {
        await _load();
      } else {
        await _open(_match!['id'] as int);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authSessionProvider.select((AuthSessionState s) => s.accessToken),
      (String? old, String next) {
        _generation++;
        setState(() {
          _match = null;
          _lobby = null;
          _deadline = null;
          _error = '账号已切换，请返回同桌页后重新进入。';
        });
      },
    );
    final Map<String, dynamic>? question =
        _match?['question'] as Map<String, dynamic>?;
    final Map<String, dynamic>? result =
        _match?['result'] as Map<String, dynamic>?;
    final Widget body = ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),
          if (_match == null && _lobby != null) ...<Widget>[
            const Text(
              '比一场，看看最近学的词记住了多少。',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Text('双方各自作答，同一题组。单题20秒；答案与分数由服务端校验，双方完成后才公布。'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('允许近期已学单词用于同桌 PK'),
              subtitle: const Text('仅用于组题，不共享私有原句；关闭会取消未完成对局。'),
              value: _lobby!['my_consent'] == true,
              onChanged: _busy
                  ? null
                  : (bool enabled) async {
                      if (!await _confirm(
                            enabled ? '开启PK授权' : '关闭PK授权',
                            enabled
                                ? '同意将已同步的近期学习单词用于与当前同桌比赛。'
                                : '关闭后取消当前未完成比赛，双方不能继续答题。',
                          ) ||
                          !mounted)
                        return;
                      await _action(() async {
                        await _request(
                          'PUT',
                          '/consent',
                          data: <String, dynamic>{'enabled': enabled},
                        );
                      });
                    },
            ),
            Text(_lobby!['peer_consent'] == true ? '对方已同意用于PK' : '等待对方开启PK授权'),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _action(() async {
                      final String message = await ref
                          .read(dailyReviewProvider.notifier)
                          .syncCloudBackup();
                      if (mounted)
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(message)));
                    }),
              icon: const Icon(Icons.sync),
              label: const Text('同步我的复习记录'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('共同学过词'),
                  selected: _source == 'intersection',
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _source = 'intersection'),
                ),
                ChoiceChip(
                  label: const Text('词书单元'),
                  selected: _source == 'syllabus',
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _source = 'syllabus');
                          unawaited(_loadSyllabusUnits());
                        },
                ),
                if (_source == 'intersection')
                  for (final int days in <int>[7, 30])
                    ChoiceChip(
                      label: Text('近$days天'),
                      selected: _days == days,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _days = days),
                    ),
                for (final int count in <int>[5, 10])
                  ChoiceChip(
                    label: Text('$count题'),
                    selected: _count == count,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _count = count),
                  ),
              ],
            ),
            if (_source == 'syllabus') ...<Widget>[
              const SizedBox(height: 8),
              if (_syllabusUnits.isEmpty)
                const Text('暂无可用词书单元，请稍后再试或改用其他题库。')
              else
                DropdownButtonFormField<String>(
                  value: _bookId == null
                      ? null
                      : '$_bookId:$_unitIndex',
                  decoration: const InputDecoration(
                    labelText: '约定词书单元',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final Map<String, dynamic> unit in _syllabusUnits)
                      DropdownMenuItem<String>(
                        value: '${unit['book_id']}:${unit['unit_index']}',
                        child: Text(
                          '${unit['book_title']} · ${unit['unit_label']}'
                          '（${unit['word_count']}词）',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (String? value) {
                          if (value == null) return;
                          final List<String> parts = value.split(':');
                          setState(() {
                            _bookId = parts.first;
                            _unitIndex = int.tryParse(parts.last) ?? 0;
                          });
                        },
                ),
            ],
            Text(
              _source == 'syllabus'
                  ? '约定词书单元：双方用同一本服务端词书的同一单元对战，不要求共同学过。'
                  : '只取双方共同学过的单词；不足时请扩大范围、选5题，或改用约定词表。',
            ),
            FilledButton(
              onPressed:
                  _busy ||
                      _lobby!['my_consent'] != true ||
                      _lobby!['peer_consent'] != true ||
                      (_source == 'syllabus' &&
                          (_bookId == null || _syllabusUnits.isEmpty))
                  ? null
                  : () => _action(() async {
                      await _request(
                        'POST',
                        '',
                        data: <String, dynamic>{
                          'days': _days,
                          'count': _count,
                          'source': _source,
                          if (_source == 'syllabus') ...<String, dynamic>{
                            'book_id': _bookId,
                            'unit_index': _unitIndex,
                          },
                        },
                      );
                    }),
              child: Text(
                _source == 'syllabus' ? '发起词书单元 PK' : '向同桌发起比赛',
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '最近对局',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if ((_lobby!['matches'] as List<dynamic>).isEmpty)
              const Text('暂无可查看对局'),
            for (final dynamic match in _lobby!['matches'] as List<dynamic>)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '第 ${match['id']} 局 · ${match['count']} 题 · '
                        '${_sourceLabel(Map<String, dynamic>.from(match as Map))}',
                      ),
                      Text(_status('${match['status']}')),
                      if (match['status'] == 'pending')
                        Wrap(
                          children: <Widget>[
                            if (match['incoming'] == true)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _action(() async {
                                        await _request(
                                          'POST',
                                          '/${match['id']}/accept',
                                        );
                                      }),
                                child: const Text('接受比赛'),
                              ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _action(() async {
                                      await _request(
                                        'POST',
                                        '/${match['id']}/${match['incoming'] == true ? 'decline' : 'cancel'}',
                                      );
                                    }),
                              child: Text(
                                match['incoming'] == true ? '婉拒' : '撤回',
                              ),
                            ),
                          ],
                        ),
                      if (match['status'] == 'active' ||
                          match['status'] == 'completed')
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _open(match['id'] as int),
                          child: Text(
                            match['status'] == 'completed' ? '查看结果与复盘' : '继续比赛',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
          if (_match != null) ...<Widget>[
            Text(
              '第 ${_match!['id']} 局 · ${_match!['count']} 题',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (question != null) ...<Widget>[
              Text(
                '第 ${(question['index'] as int) + 1} / ${_match!['count']} 题 · ${_seconds > 0 ? '剩余 $_seconds 秒' : '本题已超时'}',
              ),
              const SizedBox(height: 24),
              Text(
                '${question['word']}',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text('选出对应的中文释义'),
              for (
                int index = 0;
                index < (question['choices'] as List<dynamic>).length;
                index++
              )
                Card(
                  child: ListTile(
                    selected: _selected == index,
                    title: Text('${question['choices'][index]}'),
                    leading: Icon(
                      _selected == index
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    onTap: _busy || _seconds == 0
                        ? null
                        : () => setState(() => _selected = index),
                  ),
                ),
              FilledButton(
                onPressed: _busy || (_seconds > 0 && _selected == null)
                    ? null
                    : () => _action(() async {
                        await _request(
                          'PUT',
                          '/${_match!['id']}/answer',
                          data: <String, dynamic>{
                            'index': question['index'],
                            'choice': _seconds == 0 ? null : _selected,
                          },
                        );
                      }),
                child: Text(_seconds == 0 ? '记录未答并继续' : '提交本题'),
              ),
              const Text('退出后计时仍继续；重新进入恢复同一道题，不能重置计时。'),
            ] else if (result == null)
              Text(
                _match!['status'] == 'active'
                    ? '你已完成，等待同桌作答。点击右上角刷新查看结算。'
                    : _status('${_match!['status']}'),
              ),
            if (result != null) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                '${result['outcome']} · 我 ${result['my_score']} / 对方 ${result['peer_score']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Text('同分为平局。不按网络速度判断记忆能力；本局不修改你的FSRS计划。'),
              for (final dynamic row in result['review'] as List<dynamic>)
                Card(
                  child: ListTile(
                    leading: Icon(
                      row['correct'] == true
                          ? Icons.check_circle_outline
                          : Icons.refresh,
                    ),
                    title: Text('${row['word']}'),
                    subtitle: Text('${row['definition']}'),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (!await _confirm(
                                    '加入我的收藏',
                                    '收藏 ${row['word']}，不复制对方的学习记录或私有语境。',
                                  ) ||
                                  !mounted)
                                return;
                              await ref
                                  .read(wordBookProvider.notifier)
                                  .mergeRemoteFavorite(word: '${row['word']}');
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已加入我的收藏')),
                                );
                            },
                      child: const Text('收藏'),
                    ),
                  ),
                ),
            ],
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _match = null;
                        _deadline = null;
                      });
                      unawaited(_load());
                    },
              child: const Text('返回PK大厅'),
            ),
          ],
        ],
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('近期单词 PK'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy
                ? null
                : () => _match == null ? _load() : _open(_match!['id'] as int),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新对局',
          ),
        ],
      ),
      body: body,
    );
  }

  String _status(String status) =>
      <String, String>{
        'pending': '等待接受',
        'active': '进行中',
        'completed': '已完成',
        'cancelled': '已取消',
        'declined': '已婉拒',
        'expired': '已过期',
      }[status] ??
      status;
}
