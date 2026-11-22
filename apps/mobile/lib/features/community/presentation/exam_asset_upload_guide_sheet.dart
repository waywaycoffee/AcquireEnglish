import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/community_models.dart';

Future<void> showExamAssetUploadGuideSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (BuildContext ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (BuildContext context, ScrollController scroll) {
          return _ExamAssetUploadGuideBody(scroll: scroll);
        },
      );
    },
  );
}

class _ExamAssetUploadGuideBody extends ConsumerStatefulWidget {
  const _ExamAssetUploadGuideBody({required this.scroll});

  final ScrollController scroll;

  @override
  ConsumerState<_ExamAssetUploadGuideBody> createState() =>
      _ExamAssetUploadGuideBodyState();
}

class _ExamAssetUploadGuideBodyState
    extends ConsumerState<_ExamAssetUploadGuideBody> {
  ExamAssetUploadGuideDto? _guide;
  String? _error;
  bool _loading = true;

  static final ExamAssetUploadGuideDto _localFallback = ExamAssetUploadGuideDto(
    title: '社区上传资料 · 赚会员天数',
    headline: '上传考试学习资料，审核通过后奖励 Pro 会员 3 天（每月最多 2 次）。',
    rewardDaysPerApproval: 3,
    monthlyRewardCountCap: 2,
    maxUploadMb: 80,
    steps: const <Map<String, dynamic>>[
      <String, dynamic>{
        'title': '进入社区「考试」页',
        'body': '打开 App → 社区 → 顶部「考试」标签，点「上传资料」。',
      },
      <String, dynamic>{
        'title': '选择考试族与资料类型',
        'body': '选中考 / 高考 / 雅思等，并标明听力、脚本、解析、词表等类型。',
      },
      <String, dynamic>{
        'title': '按格式准备文件并命名清楚',
        'body': '标题写清「考试族 + 年份/套卷 + 题型」，例如「高考英语 2024 全国甲卷 听力原文」。',
      },
      <String, dynamic>{
        'title': '确认授权后上传',
        'body': '确认仅供个人学习或已获授权。审核通过后入库，并自动发放会员天数。',
      },
      <String, dynamic>{
        'title': '查看审核结果',
        'body': '在「我的上传」查看待审 / 已通过；合规文件多数会系统初审通过。',
      },
    ],
    formats: const <Map<String, dynamic>>[
      <String, dynamic>{
        'label': '听力音频',
        'extensions': <String>['.mp3', '.m4a', '.wav', '.aac'],
        'tips': '建议 ≤80MB；完整音轨、清晰可辨。',
      },
      <String, dynamic>{
        'label': '字幕 / 脚本',
        'extensions': <String>['.txt', '.srt', '.vtt', '.md'],
        'tips': 'UTF-8；尽量与音频对齐。',
      },
      <String, dynamic>{
        'label': '解析与答案',
        'extensions': <String>['.pdf', '.md', '.txt', '.json'],
        'tips': '标明题号与正确答案。',
      },
      <String, dynamic>{
        'label': '词表',
        'extensions': <String>['.csv', '.txt', '.json'],
        'tips': 'CSV 建议列：word,phonetic,meaning,example。',
      },
    ],
    rules: const <String>[
      '仅上传有权分享的学习资料。',
      '禁止广告、引流与盗版贩卖包。',
      '重复文件不重复发奖。',
      '单文件不超过 80MB；标题至少 4 个字符。',
      '审核通过奖励 Pro 3 天，每月最多 2 次。',
    ],
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ExamAssetUploadGuideDto guide =
          await ref.read(acquireApiClientProvider).examAssetUploadGuide();
      if (!mounted) return;
      setState(() {
        _guide = guide;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guide = _localFallback;
        _error = '已显示离线版说明（云端指南暂不可用）';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExamAssetUploadGuideDto guide = _guide ?? _localFallback;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: <Widget>[
        Text(
          guide.title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            guide.headline,
            style: const TextStyle(
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: Color(0xFF065F46),
            ),
          ),
        ),
        if ((_error ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...<Widget>[
          const SizedBox(height: 18),
          const Text(
            '上传步骤',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < guide.steps.length; i++) ...<Widget>[
            _StepCard(
              index: i + 1,
              title: '${guide.steps[i]['title'] ?? ''}',
              body: '${guide.steps[i]['body'] ?? ''}',
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          const Text(
            '详细格式要求',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '单文件上限 ${guide.maxUploadMb}MB。按类型选择扩展名：',
            style: TextStyle(
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final Map<String, dynamic> fmt in guide.formats) ...<Widget>[
            _FormatCard(fmt: fmt),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          const Text(
            '奖励与规则',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '通过奖励：Pro ${guide.rewardDaysPerApproval} 天 / 次；'
            '每月最多 ${guide.monthlyRewardCountCap} 次。',
            style: const TextStyle(height: 1.45, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final String rule in guide.rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('·  ', style: TextStyle(fontWeight: FontWeight.w800)),
                  Expanded(
                    child: Text(
                      rule,
                      style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.body,
  });

  final int index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 14,
            backgroundColor: AppDesignTokens.brandGreenDark,
            child: Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({required this.fmt});

  final Map<String, dynamic> fmt;

  @override
  Widget build(BuildContext context) {
    final Object? extRaw = fmt['extensions'];
    final String exts = extRaw is List
        ? extRaw.map((e) => '$e').join(' ')
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${fmt['label'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (exts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              exts,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${fmt['tips'] ?? ''}',
            style: TextStyle(
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
