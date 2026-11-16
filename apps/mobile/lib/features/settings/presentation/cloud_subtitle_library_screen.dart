import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../shared/presentation/continue_learning_button.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/personal_import_sync.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';

/// Browse personal cloud subtitle assets and pull them onto this device.
class CloudSubtitleLibraryScreen extends ConsumerStatefulWidget {
  const CloudSubtitleLibraryScreen({super.key});

  @override
  ConsumerState<CloudSubtitleLibraryScreen> createState() =>
      _CloudSubtitleLibraryScreenState();
}

class _CloudSubtitleLibraryScreenState
    extends ConsumerState<CloudSubtitleLibraryScreen> {
  Future<List<PersonalImportAsset>>? _assets;
  bool _restoring = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn) {
      setState(() {
        _assets = Future<List<PersonalImportAsset>>.value(
          const <PersonalImportAsset>[],
        );
        _message = '登录后可查看并恢复私人字幕库。';
      });
      return;
    }
    setState(() {
      _message = null;
      _assets = ref.read(acquireApiClientProvider).listPersonalImports();
    });
  }

  Future<void> _restoreAll() async {
    if (_restoring) return;
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn) {
      setState(() => _message = '请先登录后再恢复。');
      return;
    }
    setState(() {
      _restoring = true;
      _message = '正在从云端恢复私人字幕与片源…';
    });
    try {
      await syncCloudCatalogAndFeed(ref);
      final int n = await restorePersonalImportAssets(ref);
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _message = n > 0 ? '已恢复 $n 个片源到本机书库。' : '云端资产已同步（无需新增下载）。';
      });
      _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _message = '恢复失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthSessionState auth = ref.watch(authSessionProvider);
    return Scaffold(
      floatingActionButton: const ContinueLearningButton(),
      backgroundColor: AppDesignTokens.softWhite,
      body: Column(
        children: <Widget>[
          PadTopBar(
            title: '云端字幕库',
            description: '私人字幕跟账号走；共享字幕在补全时自动命中社区缓存。',
            leading: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            trailing: TextButton.icon(
              onPressed: (!auth.isLoggedIn || _restoring) ? null : _restoreAll,
              icon: _restoring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_rounded, size: 18),
              label: Text(_restoring ? '恢复中' : '恢复到本机'),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _message!,
                style: TextStyle(
                  fontSize: 13,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<PersonalImportAsset>>(
              future: _assets,
              builder: (
                BuildContext context,
                AsyncSnapshot<List<PersonalImportAsset>> snap,
              ) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '加载失败：${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final List<PersonalImportAsset> items =
                    snap.data ?? const <PersonalImportAsset>[];
                if (!auth.isLoggedIn) {
                  return const Center(
                    child: Text('请先登录爱快账号查看私人字幕库。'),
                  );
                }
                if (items.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '私人字幕库还是空的。\n导入 B 站视频并完成字幕补全后，会自动上传到这里。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final PersonalImportAsset asset = items[index];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              asset.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${asset.source} · ${asset.externalId}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppDesignTokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: <Widget>[
                                _chip(
                                  asset.hasEn ? '英文已存' : '无英文',
                                  asset.hasEn,
                                ),
                                _chip(
                                  asset.hasZh ? '中文已存' : '无中文',
                                  asset.hasZh,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ok ? const Color(0xFF166534) : const Color(0xFF6B7280),
        ),
      ),
    );
  }
}
