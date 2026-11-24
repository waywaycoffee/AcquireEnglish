/// Catalog of selectable digital-human personas (near-real portraits + voices).
class DigitalHumanPersona {
  const DigitalHumanPersona({
    required this.id,
    required this.displayName,
    required this.tagline,
    required this.assetPath,
    required this.liveTalkingAvatarId,
    required this.edgeVoiceEn,
    required this.edgeVoiceZh,
    required this.voiceLabel,
    this.voiceGender = 'female',
    this.recommendedVoiceId,
    this.hasCartoonAtlas = true,
    this.isChild = false,
    this.isAsianAppearance = false,
    this.localPitch = 1.0,
    this.localSpeechRate = 0.48,
  });

  final String id;
  final String displayName;
  final String tagline;

  /// Local Flutter asset for idle stage / home picker (portrait photo).
  final String assetPath;

  /// 3×3 viseme/gesture atlas used for local cartoon lips (scheme 2).
  String get cartoonAssetPath => 'assets/img/digital_human/$id-cartoon.webp';

  /// Matching LiveTalking `--avatar_id` when lip-sync backend is used.
  final String liveTalkingAvatarId;

  /// Microsoft Edge Neural voice for English replies.
  final String edgeVoiceEn;

  /// Microsoft Edge Neural voice for Chinese replies.
  final String edgeVoiceZh;

  /// Short Chinese label shown in the picker.
  final String voiceLabel;
  final String? recommendedVoiceId;
  final bool hasCartoonAtlas;
  final bool isChild;

  /// Asian-coded portrait: must wire a native Mandarin+English TTS voice.
  final bool isAsianAppearance;

  /// `female` / `male` — used to pick a local device voice as Edge fallback.
  final String voiceGender;

  /// Device TTS pitch fallback (1.0 = default).
  final double localPitch;

  /// Device TTS speech rate fallback (~0.5 = natural on Android).
  final double localSpeechRate;

  String edgeVoice({required bool chinese}) =>
      chinese ? edgeVoiceZh : edgeVoiceEn;

  String locale({required bool chinese}) => chinese ? 'zh-CN' : 'en-US';

  bool get isFemaleVoice => voiceGender.toLowerCase() != 'male';
}

const String defaultDigitalHumanId = 'mia';

const List<DigitalHumanPersona> digitalHumanCatalog = <DigitalHumanPersona>[
  DigitalHumanPersona(
    id: 'mia',
    displayName: 'Mia',
    tagline: '温柔耐心 · 中英同音色',
    assetPath: 'assets/img/digital_human/mia.webp',
    liveTalkingAvatarId: 'wav2lip_avatar_glass_man',
    edgeVoiceEn: 'en-US-AriaNeural',
    edgeVoiceZh: 'zh-CN-XiaoxiaoNeural',
    voiceLabel: '龙安风悦 · 中英双语',
    voiceGender: 'female',
    recommendedVoiceId: 'longanfengyue',
    isAsianAppearance: true,
    localPitch: 1.05,
    localSpeechRate: 0.46,
  ),
  DigitalHumanPersona(
    id: 'leo',
    displayName: 'Leo',
    tagline: '清晰稳重 · 中英同音色',
    assetPath: 'assets/img/digital_human/leo.webp',
    liveTalkingAvatarId: 'wav2lip_avatar_glass_man',
    edgeVoiceEn: 'en-US-GuyNeural',
    edgeVoiceZh: 'zh-CN-YunxiNeural',
    voiceLabel: '龙书 · 中英双语',
    voiceGender: 'male',
    recommendedVoiceId: 'longshu_v3.1',
    isAsianAppearance: true,
    localPitch: 0.92,
    localSpeechRate: 0.45,
  ),
  DigitalHumanPersona(
    id: 'emma',
    displayName: 'Emma',
    tagline: '活泼鼓励 · 美式口语',
    assetPath: 'assets/img/digital_human/emma.webp',
    liveTalkingAvatarId: 'wav2lip256_avatar1',
    edgeVoiceEn: 'en-US-JennyNeural',
    edgeVoiceZh: 'zh-CN-XiaoyiNeural',
    voiceLabel: 'Nora Hu · 英音',
    voiceGender: 'female',
    recommendedVoiceId: 'qwen-audio-3.0-tts-flash-loongnorahu',
    localPitch: 1.12,
    localSpeechRate: 0.52,
  ),
  DigitalHumanPersona(
    id: 'arun',
    displayName: 'Arun',
    tagline: '友善细致 · 美式口语',
    assetPath: 'assets/img/digital_human/arun.webp',
    liveTalkingAvatarId: 'wav2lip256_avatar1',
    edgeVoiceEn: 'en-IN-PrabhatNeural',
    edgeVoiceZh: 'zh-CN-YunjianNeural',
    voiceLabel: 'Adrian Gao · 英音',
    voiceGender: 'male',
    recommendedVoiceId: 'qwen-audio-3.0-tts-flash-loongadriangao',
    localPitch: 0.98,
    localSpeechRate: 0.47,
  ),
  DigitalHumanPersona(
    id: 'olivia',
    displayName: 'Olivia',
    tagline: '温柔知性 · 中英同音色',
    assetPath: 'assets/img/digital_human/olivia.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-AriaNeural',
    edgeVoiceZh: 'zh-CN-XiaoxiaoNeural',
    voiceLabel: '龙安风悦 · 中英双语',
    voiceGender: 'female',
    recommendedVoiceId: 'longanfengyue',
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'luna',
    displayName: 'Luna',
    tagline: '日常对话 · 中英同音色',
    assetPath: 'assets/img/digital_human/luna.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-AriaNeural',
    edgeVoiceZh: 'zh-CN-XiaoxiaoNeural',
    voiceLabel: '龙安小昕 · 中英双语',
    voiceGender: 'female',
    recommendedVoiceId: 'longanxiaoxin',
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'nora',
    displayName: 'Nora',
    tagline: '活泼鼓励 · 中英同音色',
    assetPath: 'assets/img/digital_human/nora.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-AriaNeural',
    edgeVoiceZh: 'zh-CN-XiaoxiaoNeural',
    voiceLabel: '龙安灵希 · 中英双语',
    voiceGender: 'female',
    recommendedVoiceId: 'longanlingxi',
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'ivy',
    displayName: 'Ivy',
    tagline: '自信从容 · 中英同音色',
    assetPath: 'assets/img/digital_human/ivy.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-AriaNeural',
    edgeVoiceZh: 'zh-CN-XiaoxiaoNeural',
    voiceLabel: '龙安欢 · 中英双语',
    voiceGender: 'female',
    recommendedVoiceId: 'longanhuan_v3.6',
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'alexander',
    displayName: 'Alexander',
    tagline: '复古质感 · 中英同音色',
    assetPath: 'assets/img/digital_human/alexander.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-GuyNeural',
    edgeVoiceZh: 'zh-CN-YunxiNeural',
    voiceLabel: '龙小诚 · 中英双语',
    voiceGender: 'male',
    recommendedVoiceId: 'longxiaocheng_v3.1',
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'adrian',
    displayName: 'Adrian',
    tagline: '沉稳大气 · 中英同音色',
    assetPath: 'assets/img/digital_human/adrian.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-GuyNeural',
    edgeVoiceZh: 'zh-CN-YunxiNeural',
    voiceLabel: '龙三叔 · 中英双语',
    voiceGender: 'male',
    recommendedVoiceId: 'longsanshu_v3.1',
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'james',
    displayName: 'James',
    tagline: '清晰讲解 · 中英同音色',
    assetPath: 'assets/img/digital_human/james.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-GuyNeural',
    edgeVoiceZh: 'zh-CN-YunxiNeural',
    voiceLabel: '李白 · 中英双语',
    voiceGender: 'male',
    recommendedVoiceId: 'libai_v3.1',
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'ryan',
    displayName: 'Ryan',
    tagline: '轻快潮流 · 中英同音色',
    assetPath: 'assets/img/digital_human/ryan.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-GuyNeural',
    edgeVoiceZh: 'zh-CN-YunxiNeural',
    voiceLabel: '龙泽 · 中英双语',
    voiceGender: 'male',
    recommendedVoiceId: 'longze_v3.1',
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'finley',
    displayName: 'Finley',
    tagline: '好奇爱提问 · 中英同音色',
    assetPath: 'assets/img/digital_human/finley.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-ChristopherNeural',
    edgeVoiceZh: 'zh-CN-YunxiNeural',
    voiceLabel: '龙杰力豆 · 中英双语',
    voiceGender: 'male',
    recommendedVoiceId: 'longjielidou_v3.6',
    isChild: true,
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'miles',
    displayName: 'Miles',
    tagline: '开朗爱分享 · 中英同音色',
    assetPath: 'assets/img/digital_human/miles.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-ChristopherNeural',
    edgeVoiceZh: 'zh-CN-YunxiNeural',
    voiceLabel: '龙火火 · 中英双语',
    voiceGender: 'male',
    recommendedVoiceId: 'longhuohuo_v3.6',
    isChild: true,
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'ruby',
    displayName: 'Ruby',
    tagline: '喜欢讲故事 · 中英同音色',
    assetPath: 'assets/img/digital_human/ruby.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-AnaNeural',
    edgeVoiceZh: 'zh-CN-XiaoxiaoNeural',
    voiceLabel: '龙安小昕 · 中英双语',
    voiceGender: 'female',
    recommendedVoiceId: 'longanxiaoxin',
    isChild: true,
    isAsianAppearance: true,
  ),
  DigitalHumanPersona(
    id: 'sophie',
    displayName: 'Sophie',
    tagline: '喜欢猜谜语 · 中英同音色',
    assetPath: 'assets/img/digital_human/sophie.webp',
    liveTalkingAvatarId: '',
    edgeVoiceEn: 'en-US-AnaNeural',
    edgeVoiceZh: 'zh-CN-XiaoxiaoNeural',
    voiceLabel: '龙安灵希 · 中英双语',
    voiceGender: 'female',
    recommendedVoiceId: 'longanlingxi',
    isChild: true,
    isAsianAppearance: true,
  ),
];

DigitalHumanPersona digitalHumanById(String? id) {
  final String want = (id ?? '').trim();
  for (final DigitalHumanPersona persona in digitalHumanCatalog) {
    if (persona.id == want) {
      return persona;
    }
  }
  return digitalHumanCatalog.first;
}

/// Resolve Edge voice from persona id (server + client share the same ids).
String edgeVoiceForDigitalHuman({
  required String? digitalHumanId,
  required bool chinese,
}) {
  return digitalHumanById(digitalHumanId).edgeVoice(chinese: chinese);
}

/// True when the learner explicitly asks to switch the coach to Chinese.
bool learnerRequestsChineseReply(String text) {
  final String value = text.trim().toLowerCase();
  if (value.isEmpty) {
    return false;
  }
  const List<String> cues = <String>[
    '用中文',
    '说中文',
    '讲中文',
    '请用中文',
    '换成中文',
    '中文回答',
    '中文回复',
    'speak chinese',
    'in chinese',
    'reply in chinese',
    'answer in chinese',
    'use chinese',
  ];
  for (final String cue in cues) {
    if (value.contains(cue)) {
      return true;
    }
  }
  return false;
}

/// True when the learner asks to go back to English.
bool learnerRequestsEnglishReply(String text) {
  final String value = text.trim().toLowerCase();
  if (value.isEmpty) {
    return false;
  }
  const List<String> cues = <String>[
    '用英文',
    '说英文',
    '讲英文',
    '请用英文',
    '换成英文',
    '英文回答',
    'speak english',
    'in english',
    'reply in english',
    'answer in english',
    'use english',
  ];
  for (final String cue in cues) {
    if (value.contains(cue)) {
      return true;
    }
  }
  return false;
}
