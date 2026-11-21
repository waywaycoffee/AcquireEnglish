import 'package:shared_preferences/shared_preferences.dart';

import 'digital_human_catalog.dart';

const String coachEnglishVoicePreference = 'coach_english_voice_v1';

typedef CoachEnglishVoice = ({String id, String name, String description});

const List<CoachEnglishVoice> coachEnglishVoices = <CoachEnglishVoice>[
  (
    id: 'qwen-audio-3.0-tts-flash-loongolivialin',
    name: 'Olivia Lin',
    description: '温柔知性 · 女声 · 英音',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loonglunawang',
    name: 'Luna Wang',
    description: '日常对话 · 女声 · 英音',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongalexanderhu',
    name: 'Alexander Hu',
    description: '复古质感 · 男声 · 英音',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongnorahu',
    name: 'Nora Hu',
    description: '活泼灵动 · 女声 · 英音',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongadriangao',
    name: 'Adrian Gao',
    description: '沉稳大气 · 男声 · 英音',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongjameszhao',
    name: 'James Zhao',
    description: '清晰播报 · 男声 · 英音',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongryanma',
    name: 'Ryan Ma',
    description: '轻快潮流 · 男声 · 英音',
  ),
  (
    id: 'qwen-audio-3.0-tts-flash-loongivyhu',
    name: 'Ivy Hu',
    description: '自信从容 · 女声 · 英音',
  ),
];

/// Qwen-Audio 3.0 Flash system voices that natively speak Mandarin + English.
const List<CoachEnglishVoice> coachBilingualVoices = <CoachEnglishVoice>[
  (id: 'longanfengyue', name: '龙安风悦', description: '自然亲切 · 女声 · 中英双语'),
  (id: 'longanxiaoxin', name: '龙安小昕', description: '亲切活泼 · 女声 · 中英双语'),
  (id: 'longanlingxi', name: '龙安灵希', description: '甜美轻快 · 女声 · 中英双语'),
  (id: 'longanhuan_v3.6', name: '龙安欢', description: '元气陪伴 · 女声 · 中英双语'),
  (id: 'longpaopao_v3.6', name: '龙泡泡', description: '飞天泡泡 · 女童 · 中英双语'),
  (id: 'longjielidou_v3.6', name: '龙杰力豆', description: '天真男童 · 中英双语'),
  (id: 'longhuohuo_v3.6', name: '龙火火', description: '顽皮少年 · 中英双语'),
  (id: 'longchuanshu_v3.6', name: '龙川叔', description: '沉稳大叔 · 男声 · 中英双语'),
];

const List<CoachEnglishVoice> coachVoices = <CoachEnglishVoice>[
  ...coachBilingualVoices,
  ...coachEnglishVoices,
];

bool isBilingualCoachVoice(String? id) =>
    coachBilingualVoices.any((CoachEnglishVoice voice) => voice.id == id);

/// Default bilingual voice for an Asian-coded persona (gender + child aware).
String bilingualVoiceIdForPersona(DigitalHumanPersona persona) {
  if (persona.isChild) {
    return persona.isFemaleVoice ? 'longpaopao_v3.6' : 'longjielidou_v3.6';
  }
  return persona.isFemaleVoice ? 'longanfengyue' : 'longchuanshu_v3.6';
}

/// Voices offered in the picker: Asian personas stay on bilingual-only.
List<CoachEnglishVoice> coachVoicesForPersona(DigitalHumanPersona persona) =>
    persona.isAsianAppearance ? coachBilingualVoices : coachVoices;

Future<String?> readCoachVoicePreference(
  SharedPreferencesAsync prefs,
  DigitalHumanPersona persona,
) async {
  final String? saved =
      await prefs.getString('$coachEnglishVoicePreference:${persona.id}') ??
      (persona.recommendedVoiceId == null
          ? await prefs.getString(coachEnglishVoicePreference)
          : null);
  final List<CoachEnglishVoice> allowed = coachVoicesForPersona(persona);
  if (allowed.any((CoachEnglishVoice voice) => voice.id == saved)) {
    return saved;
  }
  // Drop stale English-only picks for Asian personas so bilingual defaults apply.
  return null;
}
