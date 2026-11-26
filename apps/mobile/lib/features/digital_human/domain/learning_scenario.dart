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
      id: 'greetings_a1',
      title: '简单打招呼',
      goal: '用一两句问候并回答名字或近况',
      prompt: 'Say hello and tell me your name. Then answer one easy question.',
      difficulty: 'A1',
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
      id: 'directions_a2',
      title: '问路与指路',
      goal: '问怎么去一个地方，并听懂简单指路',
      prompt:
          'Ask for directions to the nearest subway station, then confirm one detail.',
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
    LearningScenario(
      id: 'opinion_b1',
      title: '表达看法',
      goal: '对一个日常话题给出观点并说明一个理由',
      prompt:
          'Share your opinion about learning English with apps, and give one reason.',
      difficulty: 'B1',
    ),
    LearningScenario(
      id: 'exam_interview',
      title: '考试口语考官',
      goal: '模拟考官提问：自我介绍、观点表达与追问，并给出简短纠错',
      prompt:
          'You are an English exam examiner. Ask me warm-up and opinion questions, '
          'correct mistakes briefly, and keep the interview going.',
      difficulty: 'B2',
    ),
    LearningScenario(
      id: 'exam_describe',
      title: '考试看图/话题描述',
      goal: '用完整段落描述一个熟悉话题，考官追问细节',
      prompt:
          'Ask me to describe a familiar topic for one minute, then ask two follow-up questions '
          'like an oral exam examiner.',
      difficulty: 'B1',
    ),
    LearningScenario(
      id: 'debate_b2',
      title: '简短辩论',
      goal: '对一个争议话题给出立场，并回应一次反驳',
      prompt:
          'Take a side on remote work vs office work. Defend it, then answer one counter-argument.',
      difficulty: 'B2',
    ),
  ];
}
