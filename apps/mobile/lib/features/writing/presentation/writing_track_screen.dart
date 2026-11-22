import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/writing_tracks.dart';

class WritingTrackScreen extends StatelessWidget {
  const WritingTrackScreen({required this.trackId, super.key});

  final WritingTrackId trackId;

  @override
  Widget build(BuildContext context) {
    final WritingTrack track = writingTrackById(trackId);
    return Scaffold(
      appBar: AppBar(title: Text(track.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: <Widget>[
          Text(
            track.oneLiner,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '目标约 ${track.targetWords} 词 · 批改模板 ${track.defaultRubric}',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 20),
          Text(
            '评分重心',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          for (final String b in track.focusBullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('· $b', style: const TextStyle(height: 1.4)),
            ),
          const SizedBox(height: 12),
          Text(
            '习惯提醒',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          for (final String b in track.habits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('· $b', style: const TextStyle(height: 1.4)),
            ),
          const SizedBox(height: 20),
          Text(
            '练习题',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          for (final WritingPromptSeed seed in track.prompts)
            Card(
              child: ListTile(
                title: Text(seed.title),
                subtitle: Text(
                  seed.prompt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () {
                  final String id =
                      'w_${DateTime.now().millisecondsSinceEpoch}';
                  context.push(
                    '/writing/$id'
                    '?rubric=${Uri.encodeComponent(seed.rubric)}'
                    '&title=${Uri.encodeComponent(seed.title)}'
                    '&prompt=${Uri.encodeComponent(seed.prompt)}'
                    '&track=${track.storageId}',
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final String id = 'w_${DateTime.now().millisecondsSinceEpoch}';
              context.push(
                '/writing/$id'
                '?rubric=${Uri.encodeComponent(track.defaultRubric)}'
                '&track=${track.storageId}'
                '&title=${Uri.encodeComponent(track.title)}',
              );
            },
            child: const Text('自由命题开写'),
          ),
        ],
      ),
    );
  }
}
