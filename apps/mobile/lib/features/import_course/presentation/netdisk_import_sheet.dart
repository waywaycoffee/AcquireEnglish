import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';
import '../data/netdisk_local_download.dart';

Future<void> showNetdiskImportSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext sheetContext) {
      return const _NetdiskImportSheet();
    },
  );
}

class _NetdiskImportSheet extends ConsumerStatefulWidget {
  const _NetdiskImportSheet();

  @override
  ConsumerState<_NetdiskImportSheet> createState() =>
      _NetdiskImportSheetState();
}

class _NetdiskImportSheetState extends ConsumerState<_NetdiskImportSheet> {
  String _provider = 'baidu';
  final TextEditingController _credential = TextEditingController();
  final List<String> _pathStack = <String>[];
  List<Map<String, dynamic>> _entries = const <Map<String, dynamic>>[];
  final Set<String> _selected = <String>{};
  bool _loading = true;
  bool _busy = false;
  bool _openlistReady = false;
  bool _bound = false;
  bool _healthy = true;
  String? _healthError;
  String? _error;
  String? _listHint;
  String _mountPath = '';

  static const List<(String, String)> _providers = <(String, String)>[
    ('baidu', '百度'),
    ('quark', '夸克'),
    ('aliyun', '阿里'),
    ('pan115', '115'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reloadStatus());
    });
  }

  @override
  void dispose() {
    _credential.dispose();
    super.dispose();
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

  String _credentialHint() {
    switch (_provider) {
      case 'quark':
        return '在浏览器登录 pan.quark.cn，复制 Cookie 粘贴到下方。';
      case 'aliyun':
        return '粘贴阿里云盘 Open 的 refresh_token（或含 refresh_token 的 JSON）。';
      case 'pan115':
        return '在浏览器登录 115，复制 Cookie 粘贴到下方。';
      default:
        return '粘贴百度网盘 Cookie（含 BDUSS/STOKEN）或 refresh_token。';
    }
  }

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
      final List<dynamic> providers =
          (status['providers'] as List<dynamic>?) ?? const <dynamic>[];
      bool bound = false;
      bool healthy = true;
      String? healthError;
      String mount = '';
      for (final dynamic row in providers) {
        if (row is! Map) continue;
        if ('${row['provider']}' == _provider) {
          bound = row['bound'] == true;
          mount = '${row['mount_path'] ?? ''}';
          healthy = row['healthy'] != false;
          final Object? err = row['error'];
          healthError = err == null ? null : '$err';
        }
      }
      if (!mounted) return;
      setState(() {
        _openlistReady = ready;
        _bound = bound;
        _mountPath = mount;
        _healthy = healthy;
        _healthError = healthError;
        _loading = false;
      });
      if (bound && healthy) {
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

  Future<void> _loadDir({String? pushName}) async {
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
      setState(() => _error = '请先进入剧季文件夹');
      return;
    }
    if (_videoPathsInDir.isEmpty) {
      setState(() => _error = '当前文件夹没有视频');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await ref
          .read(acquireApiClientProvider)
          .importNetdiskSeries(
            provider: _provider,
            folderPath: _currentFolderPath,
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

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height * 0.9;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '网盘导入',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '仅导入你自己网盘里的视频（不支持分享链接）',
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
                  segments: <ButtonSegment<String>>[
                    for (final (String value, String label) in _providers)
                      ButtonSegment<String>(value: value, label: Text(label)),
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
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Cookie / token',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _busy ? null : _bind,
                    child: Text(_busy ? '绑定中…' : '绑定并打开网盘'),
                  ),
                ],
                if (_openlistReady && _bound && !_healthy) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFCCC7)),
                    ),
                    child: Text(
                      '授权可能已失效${_healthError == null ? '' : '：$_healthError'}。请解绑后重新绑定。',
                      style: const TextStyle(
                        color: Color(0xFFA8071A),
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
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: _pathStack.isEmpty || _busy ? null : _goUp,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                      Expanded(
                        child: Text(
                          _pathStack.isEmpty
                              ? (_mountPath.isEmpty ? '根目录' : _mountPath)
                              : _currentFolderPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ),
                  Expanded(
                    child: _busy && _entries.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: _entries.length,
                            itemBuilder: (BuildContext context, int index) {
                              final Map<String, dynamic> row = _entries[index];
                              final bool isDir = row['is_dir'] == true;
                              final String name = '${row['name'] ?? ''}';
                              final String path = '${row['path'] ?? ''}';
                              final bool selected = _selected.contains(path);
                              return ListTile(
                                leading: Icon(
                                  isDir
                                      ? Icons.folder_rounded
                                      : Icons.movie_rounded,
                                ),
                                title: Text(name),
                                trailing: isDir
                                    ? const Icon(Icons.chevron_right_rounded)
                                    : Checkbox(
                                        value: selected,
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
                    onPressed: _busy || _videoPathsInDir.isEmpty
                        ? null
                        : _importFolderAsSeries,
                    child: Text(
                      _busy
                          ? '导入中…'
                          : '导入本文件夹为课程（${_videoPathsInDir.length} 集）',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy || _selected.isEmpty
                        ? null
                        : _importSelected,
                    child: Text(
                      _busy
                          ? '导入中…'
                          : '导入选中 ${_selected.length} 个视频（合并为本目录合集）',
                    ),
                  ),
                ],
                if (_error != null && !_bound)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
