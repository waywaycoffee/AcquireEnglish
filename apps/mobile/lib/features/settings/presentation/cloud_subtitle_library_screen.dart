import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../shared/presentation/continue_learning_button.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/personal_import_sync.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';

/// Browse personal cloud subtitle assets and the public shared Bilibili cache.
class CloudSubtitleLibraryScreen extends ConsumerStatefulWidget {
  const CloudSubtitleLibraryScreen({super.key});

  @override
  ConsumerState<CloudSubtitleLibraryScreen> createState() =>
      _CloudSubtitleLibraryScreenState();
}

class _CloudSubtitleLibraryScreenState
    extends ConsumerState<CloudSubtitleLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Future<List<PersonalImportAsset>>? _personal;
  Future<({int total, List<SharedBilibiliSubtitleListItem> items})>? _shared;
  bool _restoring = false;
  String? _message;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    final AuthSessionState auth = ref.read(authSessionProvider);
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    setState(() {
      _message = null;
      _shared = api.listSharedBilibiliSubtitles(
        query: _search.text.trim().isEmpty ? null : _search.text.trim(),
        limit: 80,
      );
      if (!auth.isLoggedIn) {
        _personal = Future<List<PersonalImportAsset>>.value(
          const <PersonalImportAsset>[],
        );
      } else {
        _personal = api.listPersonalImports();
      }
    });
  }

  Future<void> _restoreAll() async {
    if (_restoring) return;
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn) {
      setState(() => _message = '请先登录后再恢复私人字幕。');
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
            description: '私人字幕跟账号走；公共字幕库显示社区缓存的标题与中文预览。',
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
              label: Text(_restoring ? '恢复中' : '恢复私人'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TabBar(
              controller: _tabs,
              labelColor: AppDesignTokens.textPrimary,
              unselectedLabelColor: AppDesignTokens.textSecondary,
              indicatorColor: const Color(0xFF2563EB),
              tabs: const <Tab>[
                Tab(text: '公共字幕'),
                Tab(text: '私人字幕'),
              ],
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
            child: TabBarView(
              controller: _tabs,
              children: <Widget>[
                _buildSharedTab(),
                _buildPersonalTab(auth),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedTab() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜索标题 / BVID / 中文预览',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: '搜索',
                onPressed: _reload,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
          ),
        ),
        Expanded(
          child: FutureBuilder<
              ({int total, List<SharedBilibiliSubtitleListItem> items})>(
            future: _shared,
            builder: (
              BuildContext context,
              AsyncSnapshot<
                      ({
                        int total,
                        List<SharedBilibiliSubtitleListItem> items
                      })>
                  snap,
            ) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '加载公共字幕失败：${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final List<SharedBilibiliSubtitleListItem> items =
                  snap.data?.items ?? const <SharedBilibiliSubtitleListItem>[];
              final int total = snap.data?.total ?? items.length;
              if (items.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '公共字幕库还是空的。\n完成 B 站字幕补全后会自动贡献到这里。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return Text(
                      '共 $total 条 · 显示 ${items.length} 条',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppDesignTokens.textSecondary,
                      ),
                    );
                  }
                  final SharedBilibiliSubtitleListItem item = items[index - 1];
                  return _SharedCard(item: item);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalTab(AuthSessionState auth) {
    return FutureBuilder<List<PersonalImportAsset>>(
      future: _personal,
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
                      asset.title.trim().isNotEmpty
                          ? asset.title
                          : asset.externalId,
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
                        _chip(asset.hasEn ? '英文已存' : '无英文', asset.hasEn),
                        _chip(asset.hasZh ? '中文已存' : '无中文', asset.hasZh),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SharedCard extends StatelessWidget {
  const _SharedCard({required this.item});

  final SharedBilibiliSubtitleListItem item;

  @override
  Widget build(BuildContext context) {
    final String preview = item.previewZh.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              item.displayTitle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${item.bvid} · 第${item.page}P'
              '${item.cueCount > 0 ? ' · ${item.cueCount} 句' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            if (preview.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Color(0xFF374151),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                _chip(item.hasEn ? '英文已存' : '无英文', item.hasEn),
                _chip(item.hasZh ? '中文已存' : '无中文', item.hasZh),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _chip(String label, bool ok) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: ok ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
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
