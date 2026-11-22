import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../import_course/presentation/netdisk_import_sheet.dart';
import '../data/community_models.dart';
import '../data/netdisk_share_link.dart';

Future<void> showCommunityNetdiskShareSheet(
    BuildContext context, WidgetRef ref, CommunityPostDto post) async {
  final String link = (post.linkUrl ?? '').trim();
  final CommunityNetdiskProvider? provider = detectCommunityNetdiskProvider(link);
  if (provider == null) return;
  final String code = '${post.meta['share_code'] ??
      Uri.tryParse(link)?.queryParameters['pwd'] ?? ''}'.trim();
  final String type = switch ('${post.meta['resource_type'] ?? 'other'}') {
    'ebook' => '电子书',
    'audio' => '音频',
    'video' => '视频',
    _ => '学习资料',
  };
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(post.title, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${provider.label} · $type · ${post.authorName}'),
            if (post.body.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(post.body),
            ],
            if (code.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (sheet.mounted) {
                    ScaffoldMessenger.of(sheet).showSnackBar(
                      const SnackBar(content: Text('提取码已复制')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: Text('复制提取码 $code'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final Uri uri = Uri.parse(link);
                final bool opened = await launchUrl(
                    uri, mode: LaunchMode.externalApplication);
                if (!opened && sheet.mounted) {
                  ScaffoldMessenger.of(sheet).showSnackBar(
                    const SnackBar(content: Text('无法打开网盘链接')));
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: Text('打开${provider.label}并转存'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(sheet).pop();
                if (!context.mounted) return;
                await showNetdiskImportSheet(context, ref,
                    initialProvider: provider.apiValue);
              },
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('我已转存 · 打开我的网盘'),
            ),
            const SizedBox(height: 8),
            const Text('转存由网盘完成，不会先下载到手机。当前网盘导入器可将已转存的视频加入课程库；电子书和音频的云端导入仍在开发中。',
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}
