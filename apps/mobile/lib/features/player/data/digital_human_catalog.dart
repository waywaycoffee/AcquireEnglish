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
    this.localPitch = 1.0,
    this.localSpeechRate = 0.48,
  });

  final String id;
  final String displayName;
  final String tagline;
  /// Local Flutter asset for idle stage / home picker.
  final String assetPath;
  String get cartoonAssetPath => 'assets/img/digital_human/$id-cartoon.png';
  /// Matching LiveTalking `--avatar_id` when lip-sync backend is used.
  final String liveTalkingAvatarId;
  /// Microsoft Edge Neural voice for English replies.
  final String edgeVoiceEn;
  /// Microsoft Edge Neural voice for Chinese replies.
  final String edgeVoiceZh;
  /// Short Chinese label shown in the picker.
  final String voiceLabel;
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

const List<DigitalHumanPersona> digitalHumanCatalog =
    <DigitalHumanPersona>[
      DigitalHumanPersona(
        id: 'mia',
        displayName: 'Mia',
        tagline: '温柔耐心 · 美式英语',
        assetPath: 'assets/img/digital_human/mia.jpg',
        liveTalkingAvatarId: 'wav2lip_avatar_glass_man',
        edgeVoiceEn: 'en-US-AriaNeural',
        edgeVoiceZh: 'zh-CN-XiaoxiaoNeural',
        voiceLabel: '温柔女声',
        voiceGender: 'female',
        localPitch: 1.05,
        localSpeechRate: 0.46,
      ),
      DigitalHumanPersona(
        id: 'leo',
        displayName: 'Leo',
        tagline: '清晰稳重 · 日常对话',
        assetPath: 'assets/img/digital_human/leo.jpg',
        liveTalkingAvatarId: 'wav2lip_avatar_glass_man',
        edgeVoiceEn: 'en-US-GuyNeural',
        edgeVoiceZh: 'zh-CN-YunxiNeural',
        voiceLabel: '沉稳男声',
        voiceGender: 'male',
        localPitch: 0.92,
        localSpeechRate: 0.45,
      ),
      DigitalHumanPersona(
        id: 'emma',
        displayName: 'Emma',
        tagline: '活泼鼓励 · 美式口语',
        assetPath: 'assets/img/digital_human/emma.jpg',
        liveTalkingAvatarId: 'wav2lip256_avatar1',
        edgeVoiceEn: 'en-US-JennyNeural',
        edgeVoiceZh: 'zh-CN-XiaoyiNeural',
        voiceLabel: '明亮女声',
        voiceGender: 'female',
        localPitch: 1.12,
        localSpeechRate: 0.52,
      ),
      DigitalHumanPersona(
        id: 'arun',
        displayName: 'Arun',
        tagline: '友善细致 · 国际英语',
        assetPath: 'assets/img/digital_human/arun.jpg',
        liveTalkingAvatarId: 'wav2lip256_avatar1',
        edgeVoiceEn: 'en-IN-PrabhatNeural',
        edgeVoiceZh: 'zh-CN-YunjianNeural',
        voiceLabel: '国际男声',
        voiceGender: 'male',
        localPitch: 0.98,
        localSpeechRate: 0.47,
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
