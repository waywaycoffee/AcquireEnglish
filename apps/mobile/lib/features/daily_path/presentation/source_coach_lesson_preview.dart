import 'package:flutter/material.dart';

import '../../digital_human/presentation/digital_human_coach_screen.dart';

class SourceCoachLessonPreview extends StatelessWidget {
  const SourceCoachLessonPreview({
    required this.sourceTitle,
    required this.topic,
    required this.sourceLines,
    required this.isVideo,
    this.onConfirmedLearnerTurn,
    super.key,
  });

  final String sourceTitle;
  final String topic;
  final List<String> sourceLines;
  final bool isVideo;
  final ValueChanged<String>? onConfirmedLearnerTurn;

  @override
  Widget build(BuildContext context) {
    final List<String> lines = sourceLines
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .take(2)
        .toList(growable: false);
    const List<(IconData, String, String)> steps = <(IconData, String, String)>[
      (Icons.flag_outlined, '开场', '了解今天要学会的表达'),
      (Icons.play_circle_outline, '示范', '外教演示来源中的真实句子'),
      (Icons.mic_none, '跟读', '放慢语速，分句开口'),
      (Icons.swap_horiz, '替换', '换词说出自己的句子'),
      (Icons.forum_outlined, '场景对话', '和外教完成 2～3 轮交流'),
      (Icons.task_alt, '小结', '查看表现并领取复习任务'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('外教课预览')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  Text(sourceTitle, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 10),
                  Text(topic, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('约 10 分钟 · 六步完成 · 不会说时可以用中文求助'),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(isVideo ? '视频原句' : '文章原句',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (lines.isEmpty) const Text('当前单元尚无可用英文原句'),
                          for (final String line in lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(line),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final (IconData icon, String title, String detail) in steps)
                    ListTile(
                      leading: Icon(icon),
                      title: Text(title),
                      subtitle: Text(detail),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: lines.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DigitalHumanCoachScreen(
                                lessonTitle: topic,
                                lessonText: lines.join('\n'),
                                practiceRole: 'learner',
                                onConfirmedLearnerTurn: onConfirmedLearnerTurn,
                              ),
                            ),
                          ),
                  child: const Text('开始外教课'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
