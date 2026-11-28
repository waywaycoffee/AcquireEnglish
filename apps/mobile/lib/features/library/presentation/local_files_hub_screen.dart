import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../import_course/presentation/import_course_screen.dart';
import '../../import_course/presentation/netdisk_import_sheet.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import 'library_catalog_provider.dart';
import 'library_mock_data.dart';

/// Pencil「本地文件」hub: source chips + local media list.
class LocalFilesHubScreen extends ConsumerStatefulWidget {
  const LocalFilesHubScreen({super.key});

  static const String route = '/library/local-files';

  @override
  ConsumerState<LocalFilesHubScreen> createState() =>
      _LocalFilesHubScreenState();
}

enum _FilesTab { all, video, subtitle }

enum _MediaKind { video, subtitle }

class _LocalMediaRow {
  const _LocalMediaRow({
    required this.kind,
    required this.name,
    required this.meta,
    required this.sideLabel,
  });

  final _MediaKind kind;
  final String name;
  final String meta;
  final String sideLabel;
}

class _LocalFilesHubScreenState extends ConsumerState<LocalFilesHubScreen> {
  _FilesTab _tab = _FilesTab.all;

  @override
  Widget build(BuildContext context) {
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    final List<_LocalMediaRow> rows = _collectRows(courses);
    final List<_LocalMediaRow> filtered = rows.where((_LocalMediaRow r) {
      return switch (_tab) {
        _FilesTab.all => true,
        _FilesTab.video => r.kind == _MediaKind.video,
        _FilesTab.subtitle => r.kind == _MediaKind.subtitle,
      };
    }).toList(growable: false);

    return PadScaffold(
      currentDestination: AppNavDestination.library,
      showNavigation: false,
      showContinueLearning: false,
      topBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: '返回',
                onPressed: () => context.pop(),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: AppDesignTokens.navAccent,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '本地文件',
                      style: TextStyle(
                        color: AppDesignTokens.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '管理本地视频与字幕',
                      style: TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          _SourceRow(
            onNetdisk: () => unawaited(showNetdiskImportSheet(context, ref)),
            onAlbum: () => openImportCourseExperience(context),
            onLink: () => context.push('/importCourse'),
            onLocal: () => openImportCourseExperience(context),
            onPc: () => openImportCourseExperience(context),
          ),
          const SizedBox(height: 14),
          _StorageCard(fileCount: rows.length),
          const SizedBox(height: 14),
          _TabStrip(
            tab: _tab,
            onChanged: (_FilesTab t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 36),
              child: Column(
                children: <Widget>[
                  Text(
                    '还没有本地视频或字幕',
                    style: TextStyle(
                      color: AppDesignTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '用上方入口从网盘 / 本地导入到片库。',
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppDesignTokens.navAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => openImportCourseExperience(context),
                    child: const Text('去导入'),
                  ),
                ],
              ),
            )
          else
            for (final _LocalMediaRow row in filtered) ...<Widget>[
              _FileTile(row: row),
              Divider(height: 1, color: AppDesignTokens.borderGray),
            ],
        ],
      ),
    );
  }

  List<_LocalMediaRow> _collectRows(List<LibraryCourseData> courses) {
    final List<_LocalMediaRow> out = <_LocalMediaRow>[];
    for (final LibraryCourseData course in courses) {
      for (final LibraryEpisodeItem ep in course.episodes) {
        final String base = ep.title.trim().isEmpty
            ? '${libraryCourseDisplayTitle(course)} · 第${ep.numberStr}集'
            : ep.title.trim();
        final bool hasVideo =
            (ep.videoAsset ?? '').isNotEmpty && !ep.videoMissing;
        if (hasVideo) {
          out.add(
            _LocalMediaRow(
              kind: _MediaKind.video,
              name: base.toLowerCase().endsWith('.mp4') ? base : '$base.mp4',
              meta: 'MP4 · ${ep.durationMinutes} 分钟',
              sideLabel: course.sourceLabel,
            ),
          );
        }
        if (ep.hasEnglishSubtitles || ep.hasChineseSubtitles) {
          final String stem = base.replaceAll(
            RegExp(r'\.mp4$', caseSensitive: false),
            '',
          );
          out.add(
            _LocalMediaRow(
              kind: _MediaKind.subtitle,
              name: '$stem.srt',
              meta: 'SRT · ${ep.hasEnglishSubtitles && ep.hasChineseSubtitles ? "双语" : ep.hasEnglishSubtitles ? "英" : "中"}',
              sideLabel: course.sourceLabel,
            ),
          );
        }
      }
    }
    return out;
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.onNetdisk,
    required this.onAlbum,
    required this.onLink,
    required this.onLocal,
    required this.onPc,
  });

  final VoidCallback onNetdisk;
  final VoidCallback onAlbum;
  final VoidCallback onLink;
  final VoidCallback onLocal;
  final VoidCallback onPc;

  @override
  Widget build(BuildContext context) {
    final List<(String, IconData, VoidCallback)> items =
        <(String, IconData, VoidCallback)>[
      ('网盘', Icons.cloud_outlined, onNetdisk),
      ('相册', Icons.photo_outlined, onAlbum),
      ('链接', Icons.link_rounded, onLink),
      ('本地', Icons.folder_outlined, onLocal),
      ('电脑', Icons.desktop_windows_outlined, onPc),
    ];
    return Row(
      children: <Widget>[
        for (final (String label, IconData icon, VoidCallback onTap)
            in items)
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppDesignTokens.navAccent),
                      ),
                      child: Icon(icon, color: AppDesignTokens.navAccent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: AppDesignTokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.fileCount});

  final int fileCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppDesignTokens.navAccentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.sd_storage_outlined,
              color: AppDesignTokens.navAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '本地片库',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '已收录 $fileCount 个视频/字幕条目',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.folder_outlined, color: AppDesignTokens.textSecondary),
        ],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.tab, required this.onChanged});

  final _FilesTab tab;
  final ValueChanged<_FilesTab> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(_FilesTab value, String label) {
      final bool selected = tab == value;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(value),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppDesignTokens.navAccent
                        : AppDesignTokens.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                height: 2,
                color: selected
                    ? AppDesignTokens.navAccent
                    : Colors.transparent,
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        chip(_FilesTab.all, '全部'),
        chip(_FilesTab.video, '视频'),
        chip(_FilesTab.subtitle, '字幕'),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.row});

  final _LocalMediaRow row;

  @override
  Widget build(BuildContext context) {
    final bool video = row.kind == _MediaKind.video;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: video
                  ? AppDesignTokens.navAccent
                  : AppDesignTokens.softGray,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              video ? Icons.play_arrow_rounded : Icons.subtitles_outlined,
              color: video ? Colors.white : AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.meta,
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            row.sideLabel,
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
