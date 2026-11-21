import 'package:flutter/material.dart';

/// Isolated, in-memory product preview. Never writes to production APIs.
class CommunityPreviewScreen extends StatefulWidget {
  const CommunityPreviewScreen({super.key});

  @override
  State<CommunityPreviewScreen> createState() => _CommunityPreviewScreenState();
}

class _CommunityPreviewScreenState extends State<CommunityPreviewScreen> {
  String _filter = '全部';
  final Set<int> _liked = <int>{};
  final Set<int> _saved = <int>{};
  final Set<String> _followed = <String>{};
  final Set<String> _joined = <String>{};
  final Map<int, List<String>> _comments = <int, List<String>>{};
  final List<
    ({
      String author,
      String level,
      String kind,
      String title,
      String body,
      int likes,
    })
  >
  _posts = [
    (
      author: '林间听风',
      level: 'B1',
      kind: '视频精听',
      title: '把点单这 3 句话练熟，开口不再卡壳',
      body: '今天精听了 8 分钟日常对话。Could I get… 比 I want… 更自然。我的方法：盲听 → 看字幕 → 影子跟读三遍。',
      likes: 128,
    ),
    (
      author: 'Mia 的英语日记',
      level: 'A2',
      kind: '学习打卡',
      title: '第 21 天：终于敢关字幕听完一小段了',
      body: '每天只学 15 分钟，先把能坚持的事做好。今天掌握 12 个表达，最喜欢 take your time。',
      likes: 86,
    ),
    (
      author: '周末不摆烂',
      level: 'B1',
      kind: '找搭子',
      title: '招 2 位晚间跟读搭子｜每天 20 分钟',
      body: '工作日 21:30，一起练生活场景。互相发一句跟读成果，不卷时长，连续坚持 7 天。',
      likes: 42,
    ),
    (
      author: 'Alex',
      level: 'B2',
      kind: '学习方法',
      title: '听懂但说不出？试试「替换一个词」练习',
      body: '不背整段。把 I have been working on… 换成自己的工作、运动、计划，再录音复听。',
      likes: 203,
    ),
    (
      author: '南瓜同学',
      level: 'A2',
      kind: '问答',
      title: 'used to 和 be used to 到底怎么区分？',
      body: '前者是过去常常做，后者是习惯于。有没有更好记的场景例句？欢迎一起补充。',
      likes: 57,
    ),
    (
      author: '社区小助手',
      level: '官方',
      kind: '产品反馈',
      title: '本周共创：你最想优化哪个学习环节？',
      body: '导入、字幕校对、复习提醒还是口语陪练？欢迎带上具体使用场景，我们会整理进改进清单。',
      likes: 64,
    ),
  ];

  void _toggle<T>(Set<T> values, T value) => setState(
    () => values.contains(value) ? values.remove(value) : values.add(value),
  );

  Future<void> _compose({int? postId}) async {
    final TextEditingController controller = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(postId == null ? '分享今天的学习' : '参与讨论'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '写下你的收获、问题或建议…'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty)
                Navigator.pop(context, controller.text.trim());
            },
            child: const Text('发布到演示区'),
          ),
        ],
      ),
    );
    // Dispose after route transition, when the text field has detached.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (text == null || !mounted) return;
    setState(() {
      if (postId == null) {
        _filter = '全部';
        _posts.add((
          author: '我（演示）',
          level: 'B1',
          kind: '学习打卡',
          title: '我的学习分享',
          body: text,
          likes: 0,
        ));
      } else {
        (_comments[postId] ??= <String>[]).add(text);
      }
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已发布到本次演示，退出后重置')));
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );

  Widget _feed() => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '一起学，让坚持更容易',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('发现好内容 · 遇见同频搭子 · 看见每天的进步'),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              children: <Widget>[
                Chip(label: Text('🔥 7 天跟读挑战')),
                Chip(label: Text('🎧 每日 15 分钟')),
              ],
            ),
            OutlinedButton.icon(
              onPressed: () => _compose(),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('分享我的学习'),
            ),
          ],
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final String kind in <String>[
              '全部',
              '视频精听',
              '学习打卡',
              '找搭子',
              '学习方法',
              '问答',
              '产品反馈',
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(kind),
                  selected: _filter == kind,
                  onSelected: (_) => setState(() => _filter = kind),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      for (int i = 0; i < _posts.length; i++)
        if (_filter == '全部' || _posts[i].kind == _filter) _post(i),
    ],
  );

  Widget _post(int id) {
    final post = _posts[id];
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(child: Text(post.author.substring(0, 1))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${post.author} · ${post.level}\n${post.kind} · 示例内容',
                ),
              ),
              IconButton(
                tooltip: '屏蔽示例内容',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('正式版规划：举报、屏蔽与审核处理；演示不会提交举报。')),
                  );
                },
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(post.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(post.body),
          if (post.kind == '视频精听')
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.play_circle_outline, size: 42),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'COFFEE & CONVERSATION\n生活英语 · 08:24 · B1\n演示课程卡片，不关联真实视频',
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TextButton.icon(
                onPressed: () => _toggle(_liked, id),
                icon: Icon(
                  _liked.contains(id) ? Icons.favorite : Icons.favorite_border,
                ),
                label: Text('${post.likes + (_liked.contains(id) ? 1 : 0)}'),
              ),
              TextButton.icon(
                onPressed: () => _compose(postId: id),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text('讨论 ${2 + (_comments[id]?.length ?? 0)}'),
              ),
              TextButton.icon(
                onPressed: () => _toggle(_saved, id),
                icon: Icon(
                  _saved.contains(id) ? Icons.bookmark : Icons.bookmark_border,
                ),
                label: Text(_saved.contains(id) ? '已收藏' : '收藏'),
              ),
            ],
          ),
          const Divider(),
          const Text(
            '小橙：这个方法很适合通勤时练习。\nRiver：明天也来一起打卡！',
            style: TextStyle(fontSize: 13),
          ),
          for (final String comment in _comments[id] ?? <String>[])
            Text('我：$comment'),
        ],
      ),
    );
  }

  Widget _people() => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('找到你的学习同路人', style: Theme.of(context).textTheme.headlineSmall),
      const Text('以下人物与匹配理由均为演示；正式版按自愿公开的水平、兴趣与时间匹配。'),
      const SizedBox(height: 16),
      for (final person in <({String name, String level, String bio})>[
        (name: '晚风', level: 'A2', bio: '旅行英语 · 每天 20:00 · 15 分钟'),
        (name: 'River', level: 'B1', bio: '职场表达 · 工作日 21:30 · 20 分钟'),
        (name: 'Mia', level: 'B1', bio: '美剧精听 · 周末上午 · 30 分钟'),
        (name: 'Alex', level: 'B2', bio: '新闻讨论 · 午休 12:30 · 15 分钟'),
      ])
        _card(
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(person.name.substring(0, 1))),
            title: Text('${person.name} · ${person.level}'),
            subtitle: Text(person.bio),
            trailing: TextButton(
              onPressed: () => _toggle(_followed, person.name),
              child: Text(_followed.contains(person.name) ? '已关注' : '关注'),
            ),
          ),
        ),
      _card(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('搭子安全约定'),
            Text('先公开交流，不交换敏感信息；组队邀请须对方同意。私信、拉黑与举报在正式版分阶段开放。'),
          ],
        ),
      ),
    ],
  );

  Widget _leaderboard() => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('本周坚持榜', style: Theme.of(context).textTheme.headlineSmall),
      const Text('演示排名 · 比的是坚持，不鼓励挂机刷时长'),
      const SizedBox(height: 16),
      for (final entry in <({String name, int minutes})>[
        (name: '林间听风', minutes: 245),
        (name: 'Mia', minutes: 210),
        (name: 'River', minutes: 185),
        (name: '晚风', minutes: 150),
      ])
        _card(
          ListTile(
            leading: const Icon(
              Icons.emoji_events_outlined,
              color: Colors.amber,
            ),
            title: Text(entry.name),
            subtitle: const Text('本周学习 · 示例'),
            trailing: Text('${entry.minutes} 分钟'),
          ),
        ),
      _card(
        const ListTile(
          title: Text('我的本周目标'),
          subtitle: Text('已完成 3 / 5 天（演示）'),
          trailing: Icon(Icons.local_fire_department, color: Colors.orange),
        ),
      ),
    ],
  );

  Widget _activities() => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('小目标，一起完成', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      for (final String title in <String>[
        '7 天影子跟读挑战',
        '通勤精听 15 分钟',
        '周末英文电影台词共读',
      ])
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.flag_circle_outlined, size: 40),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const Text('示例活动 · 每天提交一条学习收获\n活动进度与奖励为展示，不发放真实积分或会员'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _toggle(_joined, title),
                child: Text(
                  _joined.contains(title) ? '已加入演示 · 点击退出' : '加入挑战（演示）',
                ),
              ),
            ],
          ),
        ),
      _card(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('本周热门话题'),
            Text('# 不背单词怎么练口语\n# 我的第一段无字幕精听\n# 找一个可以坚持的学习节奏'),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('社区全景预览'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: <Tab>[
            Tab(text: '发现动态'),
            Tab(text: '学习搭子'),
            Tab(text: '坚持榜单'),
            Tab(text: '活动广场'),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          MaterialBanner(
            content: const Text('演示模式：人物、内容和数字均为 mock。互动仅在本页有效，退出重置，不影响真实社区。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回真实社区'),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _feed(),
                _people(),
                _leaderboard(),
                _activities(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
