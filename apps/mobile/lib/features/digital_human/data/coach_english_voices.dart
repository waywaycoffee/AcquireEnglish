const String coachEnglishVoicePreference = 'coach_english_voice_v1';

typedef CoachEnglishVoice = ({String id, String name, String description});

const List<CoachEnglishVoice> coachEnglishVoices = <CoachEnglishVoice>[
  (
    id: 'qwen-audio-3.0-tts-flash-loongolivialin',
    name: 'Olivia Lin',
    description: '温柔知性 · 女声',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loonglunawang',
    name: 'Luna Wang',
    description: '日常对话 · 女声',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongalexanderhu',
    name: 'Alexander Hu',
    description: '复古质感 · 男声',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongnorahu',
    name: 'Nora Hu',
    description: '活泼灵动 · 女声',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongadriangao',
    name: 'Adrian Gao',
    description: '沉稳大气 · 男声',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongjameszhao',
    name: 'James Zhao',
    description: '清晰播报 · 男声',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongryanma',
    name: 'Ryan Ma',
    description: '轻快潮流 · 男声',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongivyhu',
    name: 'Ivy Hu',
    description: '自信从容 · 女声',
  ),
];

const List<CoachEnglishVoice> coachBilingualVoices = <CoachEnglishVoice>[
  (id: 'longanfengyue', name: '龙安风悦', description: '自然亲切 · 中英双语'),
  (id: 'longanxiaoxin', name: '龙安小昕', description: '亲切活泼 · 中英双语'),
  (id: 'longanlingxi', name: '龙安灵希', description: '甜美轻快 · 中英双语'),
  (id: 'longanhuan_v3.6', name: '龙安欢', description: '女声 · 中英双语'),
];

const List<CoachEnglishVoice> coachVoices = <CoachEnglishVoice>[
  ...coachBilingualVoices,
  ...coachEnglishVoices,
];

bool isBilingualCoachVoice(String? id) =>
    coachBilingualVoices.any((CoachEnglishVoice voice) => voice.id == id);
