/// First-party scenario dialogue task from `/api/learning/tasks`.
class LearningScenario {
  const LearningScenario({
    required this.id,
    required this.title,
    required this.goal,
    required this.prompt,
    this.difficulty = 'B1',
  });

  factory LearningScenario.fromJson(Map<String, dynamic> json) {
    return LearningScenario(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      goal: '${json['goal'] ?? ''}'.trim(),
      prompt: '${json['prompt'] ?? ''}'.trim(),
      difficulty: '${json['difficulty'] ?? 'B1'}'.trim().isEmpty
          ? 'B1'
          : '${json['difficulty']}'.trim(),
    );
  }

  final String id;
  final String title;
  final String goal;
  final String prompt;
  final String difficulty;

  bool get isVideoGrounded => id == 'video_line';

  bool get isFreeChat => id == 'freechat';

  /// Offline fallback when the API is unreachable.
  static const List<LearningScenario> seeds = <LearningScenario>[
    LearningScenario(
      id: 'freechat',
      title: '自由闲聊',
      goal: '用自然英语随便聊日常、兴趣或当下想法，外教像朋友一样接话并纠错',
      prompt:
          'Let\'s just chat in English about anything — your day, hobbies, or whatever is on your mind.',
      difficulty: 'B1',
    ),
    LearningScenario(
      id: 'weekend',
      title: '描述周末',
      goal: '说清过去的活动、同行的人以及自己的感受或原因',
      prompt:
          'Tell me about your last weekend. What did you do, who with, and how did you feel?',
      difficulty: 'A2',
    ),
    LearningScenario(
      id: 'restaurant',
      title: '在餐厅点餐',
      goal: '说明餐点和数量、饮品，再提出一个要求或问题',
      prompt:
          'You are at a cafe. Order food and a drink, then ask one question.',
      difficulty: 'A2',
    ),
    LearningScenario(
      id: 'hotel',
      title: '办理酒店入住',
      goal: '说明已有预订、提供必要信息，再询问一项住宿信息',
      prompt:
          'Check in at a hotel. Mention your reservation and ask one question about the stay.',
      difficulty: 'B1',
    ),
    LearningScenario(
      id: 'video_line',
      title: '视频当前句对话',
      goal: '围绕视频当前英文字幕自然多说几句，并回应外教追问',
      prompt:
          'Talk about the current video line. Paraphrase it, then answer follow-ups.',
      difficulty: 'B1',
    ),
  ];
}
