import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';
import '../data/netdisk_local_download.dart';

Future<void> showNetdiskImportSheet(
  BuildContext context,
  WidgetRef ref, {
  String? initialProvider,
  String? initialSearch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppDesignTokens.appWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext sheetContext) {
      return _NetdiskImportSheet(
        initialProvider: initialProvider,
        initialSearch: initialSearch,
      );
    },
  );
}

class _NetdiskImportSheet extends ConsumerStatefulWidget {
  const _NetdiskImportSheet({this.initialProvider, this.initialSearch});

  final String? initialProvider;
  final String? initialSearch;

  @override
  ConsumerState<_NetdiskImportSheet> createState() =>
      _NetdiskImportSheetState();
}

class _NetdiskImportSheetState extends ConsumerState<_NetdiskImportSheet> {
  late String _provider;
  final TextEditingController _credential = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final List<String> _pathStack = <String>[];
  List<Map<String, dynamic>> _entries = const <Map<String, dynamic>>[];
  final Set<String> _selected = <String>{};
  bool _loading = true;
  bool _busy = false;
  bool _openlistReady = false;
  bool _baiduOauthReady = false;
  bool _bound = false;
  bool _healthy = true;
  bool _showAdvancedCookie = false;
  String? _healthError;
  String? _error;
  String? _progressHint;
  int _progressDone = 0;
  int _progressTotal = 0;
  String? _listHint;
  String _mountPath = '';
  String? _baiduAccountLabel;
  Timer? _oauthPoll;

  static const List<(String, String)> _providers = <(String, String)>[
    ('baidu', '百度'),
    ('quark', '夸克'),
    ('aliyun', '阿里'),
    ('pan115', '115'),
  ];

  @override
  void initState() {
    super.initState();
    _provider = const <String>{'baidu', 'quark', 'aliyun', 'pan115'}
            .contains(widget.initialProvider)
        ? widget.initialProvider!
        : 'baidu';
    final String seed = (widget.initialSearch ?? '').trim();
    if (seed.isNotEmpty) {
      _search.text = seed;
    }
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reloadStatus());
    });
  }

  @override
  void dispose() {
    _oauthPoll?.cancel();
    _credential.dispose();
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibleEntries {
    final String q = _search.text.trim().toLowerCase();
    if (q.isEmpty) {
      return _entries;
    }
    return _entries
        .where((Map<String, dynamic> row) {
          final String name = '${row['name'] ?? ''}'.toLowerCase();
          final String path = '${row['path'] ?? ''}'.toLowerCase();
          return name.contains(q) || path.contains(q);
        })
        .toList(growable: false);
  }

  String get _currentFolderPath {
    if (_pathStack.isEmpty) {
      return _mountPath;
    }
    return '$_mountPath/${_pathStack.join('/')}';
  }

  List<String> get _videoPathsInDir => _entries
      .where((Map<String, dynamic> row) => row['is_dir'] != true)
      .map((Map<String, dynamic> row) => '${row['path'] ?? ''}')
      .where((String p) => p.isNotEmpty)
      .toList(growable: false);

  bool get _hasSeasonDirs => _entries.any(
        (Map<String, dynamic> row) => row['is_dir'] == true,
      );

  /// Parent show folders (Season 01…) can import recursively via API.
  bool get _canImportFolderAsSeries =>
      _currentFolderPath.isNotEmpty &&
      (_videoPathsInDir.isNotEmpty || _hasSeasonDirs);

  String _credentialHint() {
    switch (_provider) {
      case 'quark':
        return '在浏览器登录 pan.quark.cn，复制 Cookie 粘贴到下方。';
      case 'aliyun':
        return '粘贴阿里云盘 Open 的 refresh_token（或含 refresh_token 的 JSON）。';
      case 'pan115':
        return '在浏览器登录 115，复制 Cookie 粘贴到下方。';
      default:
        return '粘贴百度网盘 Cookie（含 BDUSS/STOKEN）或 refresh_token（高级）。';
    }
  }

  bool get _useBaiduOauth => _provider == 'baidu' && _baiduOauthReady;

  Future<void> _reloadStatus() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '请先登录爱快账号';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> status =
          await ref.read(acquireApiClientProvider).netdiskStatus();
      final bool ready = status['openlist_configured'] == true;
      final bool baiduOauth = status['baidu_oauth_configured'] == true;
      final List<dynamic> providers =
          (status['providers'] as List<dynamic>?) ?? const <dynamic>[];
      bool bound = false;
      bool healthy = true;
      String? healthError;
      String mount = '';
      String? accountLabel;
      for (final dynamic row in providers) {
        if (row is! Map) continue;
        if ('${row['provider']}' == _provider) {
          bound = row['bound'] == true;
          mount = '${row['mount_path'] ?? ''}';
          healthy = row['healthy'] != false;
          final Object? err = row['error'];
          healthError = err == null ? null : '$err';
          final Object? accountRaw = row['account'];
          if (accountRaw is Map) {
            final String name =
                '${accountRaw['baidu_name'] ?? accountRaw['netdisk_name'] ?? ''}'
                    .trim();
            final bool isVip = accountRaw['is_vip'] == true;
            if (name.isNotEmpty) {
              accountLabel = isVip ? '$name · 会员' : '$name · 非会员';
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _openlistReady = ready;
        _baiduOauthReady = baiduOauth;
        _bound = bound;
        _mountPath = mount;
        _healthy = healthy;
        _healthError = healthError;
        _baiduAccountLabel = accountLabel;
        _loading = false;
      });
      if (bound && healthy) {
        _oauthPoll?.cancel();
        await _loadDir();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _bind() async {
    final String cred = _credential.text.trim();
    if (cred.length < 8) {
      setState(() => _error = '请粘贴有效的 Cookie / token');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(acquireApiClientProvider).bindNetdisk(
            provider: _provider,
            credential: cred,
          );
      _credential.clear();
      await _reloadStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startBaiduOauth({String mode = 'password'}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> started = await ref
          .read(acquireApiClientProvider)
          .startBaiduNetdiskOauth(mode: mode);
      final String url = '${started['authorize_url'] ?? ''}'.trim();
      if (url.isEmpty) {
        throw Exception('未返回授权地址');
      }
      final Uri uri = Uri.parse(url);
      final bool opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw Exception('无法打开百度授权页，请检查浏览器');
      }
      if (!mounted) return;
      final bool qr = mode == 'qrcode';
      setState(() {
        _busy = false;
        _error = qr
            ? '请用百度 App 扫码；会绑定 App 里当前登录的号，完成后自动刷新'
            : '请在无痕浏览器登录：用户名填 linghusgc（不要填手机号、不要短信），'
                '再输入密码。成功页必须是「嘉佑真好」，若仍是令狐上官冲1 说明又用了手机号登录。';
      });
      _oauthPoll?.cancel();
      _oauthPoll = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(_reloadStatus());
      });
      // Stop polling after 3 minutes.
      Timer(const Duration(minutes: 3), () {
        _oauthPoll?.cancel();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadDir({String? pushName}) async {
    // Ignore double-taps while a listing is in flight; concurrent pushes
    // duplicate path segments (…/Foo/Foo) and Baidu returns object-not-found.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (pushName != null) {
        _pathStack.add(pushName);
      }
      _selected.clear();
    });
    try {
      final String rel = _pathStack.join('/');
      final Map<String, dynamic> data = await ref
          .read(acquireApiClientProvider)
          .listNetdisk(provider: _provider, path: rel);
      final List<dynamic> raw =
          (data['entries'] as List<dynamic>?) ?? const <dynamic>[];
      final String? hint = data['hint']?.toString();
      if (!mounted) return;
      setState(() {
        _listHint = hint;
        _entries = raw
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> row) =>
                  row.map((Object? k, Object? v) => MapEntry('$k', v)),
            )
            .toList(growable: false);
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.replaceFirst('Exception: ', '');
        if (pushName != null && _pathStack.isNotEmpty) {
          _pathStack.removeLast();
        }
      });
    }
  }

  Future<void> _goUp() async {
    if (_pathStack.isEmpty) return;
    _pathStack.removeLast();
    await _loadDir();
  }

  void _selectAllVideos() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_videoPathsInDir);
    });
  }

  Future<void> _finishImport(Map<String, dynamic> result) async {
    await syncCloudCatalogAndFeed(ref);
    final List<dynamic> items =
        (result['items'] as List<dynamic>?) ?? const <dynamic>[];
    final List<Map<Object?, Object?>> okItems = items
        .whereType<Map<Object?, Object?>>()
        .where((Map<Object?, Object?> row) => row['ok'] == true)
        .toList(growable: false);
    final Object? seriesRaw = result['series_course'];
    String? seriesCourseId;
    if (seriesRaw is Map) {
      seriesCourseId = '${seriesRaw['id'] ?? ''}';
    }
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    final LibraryCatalogNotifier catalog =
        ref.read(libraryCatalogProvider.notifier);
    final List<LibraryCourseData> courses = ref.read(libraryCatalogProvider);

    if (seriesCourseId != null && seriesCourseId.isNotEmpty) {
      LibraryCourseData? series;
      for (final LibraryCourseData c in courses) {
        if (c.id == seriesCourseId) {
          series = c;
          break;
        }
      }
      if (series != null) {
        for (final LibraryEpisodeItem ep in series.episodes) {
          try {
            await materializeNetdiskSoftsubs(
              api: api,
              catalog: catalog,
              courseId: seriesCourseId,
              episode: ep,
              importId: parseNetdiskImportIdFromUrl(ep.enSubtitleAsset) ??
                  parseNetdiskImportIdFromUrl(ep.cnSubtitleAsset) ??
                  parseNetdiskImportIdFromUrl(ep.videoAsset),
            );
          } catch (_) {}
        }
      }
    } else {
      for (final Map<Object?, Object?> row in okItems) {
        final String courseId = '${row['course_id'] ?? ''}';
        if (courseId.isEmpty) continue;
        LibraryEpisodeItem? episode;
        for (final LibraryCourseData course in courses) {
          if (course.id == courseId && course.episodes.isNotEmpty) {
            episode = course.episodes.first;
            break;
          }
        }
        try {
          await materializeNetdiskSoftsubs(
            api: api,
            catalog: catalog,
            courseId: courseId,
            episode: episode,
          );
        } catch (_) {}
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    final String msg = seriesCourseId != null && seriesCourseId.isNotEmpty
        ? '已导入为合集课程（${okItems.length} 集）。缺英文字幕的集可「先下后学」自动补全。'
        : '已导入 ${okItems.length} 个网盘视频到课程库';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _importSelected() async {
    if (_selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await ref
          .read(acquireApiClientProvider)
          .importNetdiskVideos(
            provider: _provider,
            paths: _selected.toList(growable: false),
            seriesFolder: _currentFolderPath.isEmpty ? null : _currentFolderPath,
          );
      await _finishImport(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _importFolderAsSeries() async {
    if (_currentFolderPath.isEmpty) {
      setState(() => _error = '请先进入剧集文件夹');
      return;
    }
    if (!_canImportFolderAsSeries) {
      setState(() => _error = '当前文件夹没有视频或季目录');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progressHint = '正在启动导入…';
      _progressDone = 0;
      _progressTotal = 0;
    });
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final Map<String, dynamic> started = await api.importNetdiskSeries(
        provider: _provider,
        folderPath: _currentFolderPath,
      );
      final String jobId = '${started['job_id'] ?? ''}';
      if (jobId.isEmpty) {
        throw Exception('服务器未返回导入任务 ID');
      }
      Map<String, dynamic> job = started;
      for (int i = 0; i < 3600; i++) {
        job = await api.netdiskImportJob(jobId);
        final String status = '${job['status'] ?? ''}';
        final String message = '${job['message'] ?? ''}';
        final String current = '${job['current'] ?? ''}';
        final int done = int.tryParse('${job['done'] ?? 0}') ?? 0;
        final int total = int.tryParse('${job['total'] ?? 0}') ?? 0;
        if (!mounted) return;
        setState(() {
          _progressDone = done;
          _progressTotal = total;
          if (total > 0) {
            final String fileBit =
                current.isNotEmpty ? '\n$current' : '';
            _progressHint = message.isNotEmpty
                ? '$message$fileBit'
                : '导入中 $done/$total$fileBit';
          } else {
            _progressHint = message.isNotEmpty ? message : '处理中…';
          }
        });
        if (status == 'done') {
          final Object? resultRaw = job['result'];
          final Map<String, dynamic> result = resultRaw is Map<String, dynamic>
              ? resultRaw
              : resultRaw is Map
                  ? resultRaw.map(
                      (Object? k, Object? v) => MapEntry('$k', v),
                    )
                  : <String, dynamic>{};
          await _finishImport(result);
          return;
        }
        if (status == 'error') {
          throw Exception('${job['error'] ?? job['message'] ?? '导入失败'}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      throw Exception('导入超时，请稍后在课程库查看是否已写入');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progressHint = null;
        _progressDone = 0;
        _progressTotal = 0;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height * 0.9;
    return Material(
      color: AppDesignTokens.appWhite,
      child: SafeArea(
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '添加片源',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '把你自己网盘里的视频挂进片库（不等于下载到手机；不支持分享链接）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (Set<WidgetState> states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppDesignTokens.onAccent;
                          }
                          return AppDesignTokens.textPrimary;
                        },
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (Set<WidgetState> states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppDesignTokens.primaryBlueDark;
                          }
                          return AppDesignTokens.softGray;
                        },
                      ),
                    ),
                    segments: <ButtonSegment<String>>[
                      for (final (String value, String label) in _providers)
                        ButtonSegment<String>(
                          value: value,
                          label: Text(label),
                        ),
                    ],
                    selected: <String>{_provider},
                    onSelectionChanged: _busy
                        ? null
                        : (Set<String> next) {
                            setState(() {
                              _provider = next.first;
                              _pathStack.clear();
                              _entries = const <Map<String, dynamic>>[];
                              _selected.clear();
                            });
                            unawaited(_reloadStatus());
                          },
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...<Widget>[
                  if (!_openlistReady)
                    Text(
                      '服务端尚未启用 OpenList。部署后即可绑定网盘。',
                      style: TextStyle(color: AppDesignTokens.textSecondary),
                    ),
                  if (_openlistReady && !_bound) ...<Widget>[
                    if (_useBaiduOauth) ...<Widget>[
                      Text(
                        '一号两护照时：不要扫码、不要用手机号/短信登录'
                        '（短信会进「令狐上官冲1」）。\n'
                        '请用无痕浏览器打开授权页，登录名填 linghusgc + 密码'
                        '（不要填手机号）。成功页必须是「嘉佑真好」。',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => unawaited(
                                  _startBaiduOauth(mode: 'password'),
                                ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppDesignTokens.primaryBlueDark,
                          foregroundColor: AppDesignTokens.onAccent,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.password_rounded),
                        label: Text(
                          _busy ? '打开授权中…' : '用户名 linghusgc + 密码登录',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => unawaited(
                                  _startBaiduOauth(mode: 'qrcode'),
                                ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppDesignTokens.textPrimary,
                          side: BorderSide(color: AppDesignTokens.borderGray),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: const Text('改用扫码（易绑错号）'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(
                                  () => _showAdvancedCookie = !_showAdvancedCookie,
                                ),
                        child: Text(
                          _showAdvancedCookie ? '收起高级方式' : '高级：粘贴 Cookie',
                        ),
                      ),
                    ],
                    if (!_useBaiduOauth || _showAdvancedCookie) ...<Widget>[
                      Text(
                        _credentialHint(),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _credential,
                        maxLines: 4,
                        style: TextStyle(color: AppDesignTokens.textPrimary),
                        cursorColor: AppDesignTokens.primaryBlueDark,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppDesignTokens.softWhite,
                          hintText: 'Cookie / token',
                          hintStyle: TextStyle(
                            color: AppDesignTokens.textSecondary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppDesignTokens.borderGray,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppDesignTokens.borderGray,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppDesignTokens.primaryBlueDark,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _busy ? null : _bind,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppDesignTokens.primaryBlueDark,
                          foregroundColor: AppDesignTokens.onAccent,
                        ),
                        child: Text(_busy ? '绑定中…' : '绑定并打开网盘'),
                      ),
                    ],
                  ],
                  if (_openlistReady && _bound && !_healthy) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppDesignTokens.borderGray),
                      ),
                      child: Text(
                        '授权可能已失效${_healthError == null ? '' : '：$_healthError'}。请解绑后重新绑定。',
                        style: TextStyle(
                          color: AppDesignTokens.dangerText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await ref
                                  .read(acquireApiClientProvider)
                                  .unbindNetdisk(_provider);
                              await _reloadStatus();
                            },
                      child: const Text('解绑并重新授权'),
                    ),
                  ],
                  if (_openlistReady && _bound && _healthy) ...<Widget>[
                    if (_provider == 'baidu' &&
                        (_baiduAccountLabel?.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '当前百度账号：$_baiduAccountLabel\n'
                          '若不是有会员、有资源的那个，请解绑后重新授权，'
                          '登录页务必选对百度护照（198 开头那套里核对昵称/会员）。',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    Row(
                      children: <Widget>[
                        IconButton(
                          onPressed:
                              _pathStack.isEmpty || _busy ? null : _goUp,
                          icon: Icon(
                            Icons.arrow_upward_rounded,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _pathStack.isEmpty
                                ? (_mountPath.isEmpty ? '根目录' : _mountPath)
                                : _currentFolderPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy || _videoPathsInDir.isEmpty
                              ? null
                              : _selectAllVideos,
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await ref
                                      .read(acquireApiClientProvider)
                                      .unbindNetdisk(_provider);
                                  await _reloadStatus();
                                },
                          child: const Text('解绑'),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索当前目录（剧名 / 文件夹）',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除',
                                  onPressed: () => _search.clear(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (_listHint != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _listHint!,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: AppDesignTokens.dangerText),
                        ),
                      ),
                    Expanded(
                      child: _busy && _entries.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : _visibleEntries.isEmpty
                              ? Center(
                                  child: Text(
                                    _search.text.trim().isEmpty
                                        ? '此目录为空'
                                        : '没有匹配「${_search.text.trim()}」的项目',
                                    style: TextStyle(
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                  ),
                                )
                          : ListView.builder(
                              itemCount: _visibleEntries.length,
                              itemBuilder:
                                  (BuildContext context, int index) {
                                final Map<String, dynamic> row =
                                    _visibleEntries[index];
                                final bool isDir = row['is_dir'] == true;
                                final String name = '${row['name'] ?? ''}';
                                final String path = '${row['path'] ?? ''}';
                                final bool selected =
                                    _selected.contains(path);
                                return ListTile(
                                  iconColor: AppDesignTokens.textSecondary,
                                  textColor: AppDesignTokens.textPrimary,
                                  leading: Icon(
                                    isDir
                                        ? Icons.folder_rounded
                                        : Icons.movie_rounded,
                                  ),
                                  title: Text(name),
                                  trailing: isDir
                                      ? Icon(
                                          Icons.chevron_right_rounded,
                                          color:
                                              AppDesignTokens.textSecondary,
                                        )
                                      : Checkbox(
                                          value: selected,
                                          activeColor:
                                              AppDesignTokens.primaryBlueDark,
                                          onChanged: (bool? value) {
                                            setState(() {
                                              if (value == true) {
                                                _selected.add(path);
                                              } else {
                                                _selected.remove(path);
                                              }
                                            });
                                          },
                                        ),
                                  onTap: () {
                                    if (isDir) {
                                      if (_busy || name.isEmpty) return;
                                      unawaited(_loadDir(pushName: name));
                                      return;
                                    }
                                    setState(() {
                                      if (selected) {
                                        _selected.remove(path);
                                      } else {
                                        _selected.add(path);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    FilledButton(
                      onPressed: _busy || !_canImportFolderAsSeries
                          ? null
                          : _importFolderAsSeries,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppDesignTokens.primaryBlueDark,
                        foregroundColor: AppDesignTokens.onAccent,
                      ),
                      child: Text(
                        _busy
                            ? (_progressTotal > 0
                                ? '导入中 $_progressDone/$_progressTotal'
                                : '导入中…')
                            : _videoPathsInDir.isNotEmpty
                                ? '导入本文件夹为课程（${_videoPathsInDir.length} 集）'
                                : '导入本文件夹为课程（含 Season 子目录）',
                      ),
                    ),
                    if (_busy) ...<Widget>[
                      const SizedBox(height: 10),
                      if (_progressTotal > 0)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (_progressDone / _progressTotal)
                                .clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: AppDesignTokens.borderGray,
                            color: AppDesignTokens.primaryBlueDark,
                          ),
                        )
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            backgroundColor: AppDesignTokens.borderGray,
                            color: AppDesignTokens.primaryBlueDark,
                          ),
                        ),
                      if (_progressHint != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          _progressHint!,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : _importSelected,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppDesignTokens.textPrimary,
                        side: BorderSide(color: AppDesignTokens.borderGray),
                      ),
                      child: Text(
                        _busy
                            ? '请稍候…'
                            : '导入选中 ${_selected.length} 个视频（合并为本目录合集）',
                      ),
                    ),
                  ],
                  if (_error != null && !_bound)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: AppDesignTokens.dangerText),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
