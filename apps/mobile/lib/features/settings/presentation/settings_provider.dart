import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../constants/endpoints.dart';
import '../../../constants/env_config.dart';
import '../../../data/repository/network_repository.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../digital_human/data/digital_human_catalog.dart';
import '../../shared/domain/subtitle_letter_case.dart';
import '../../sync/data/acquire_api_client.dart';

export '../../shared/domain/subtitle_letter_case.dart'
    show subtitleLetterCaseOptions;

/// Fixes the historical typo host `caurlhairai` → `curlhairai` (breaks DNS).
String fixCurlhairaiTypoHost(String raw) {
  final String value = raw.trim();
  if (value.isEmpty || !value.contains('caurlhairai')) {
    return value;
  }
  return value.replaceAll('caurlhairai', 'curlhairai');
}

const List<double> ttsRateOptions = <double>[
  0.5,
  0.75,
  1,
  1.25,
  1.5,
  2,
  2.5,
  3,
];

const List<String> playerFontOptions = <String>[
  '特小',
  '小',
  '中',
  '大',
  '特大',
  '超大',
  '最大',
];
const Map<String, double> playerFontScales = <String, double>{
  '特小': 0.75,
  '小': 0.92,
  '中': 1,
  '大': 1.18,
  '特大': 1.4,
  '超大': 1.7,
  '最大': 2,
};
const List<String> subtitleWordHighlightStyleOptions = <String>[
  '绿色填充',
  '下划线',
  '描边',
];

/// Older builds persisted these; map them onto the sparse green-text look.
const Set<String> legacySubtitleWordHighlightStyles = <String>{
  '黄色填充',
  '蓝色填充',
};

const List<String> subtitleModeOptions = <String>[
  '双语',
  '英文',
  '中文',
  '盲听',
];
const List<String> playbackSpeedOptions = <String>[
  '0.5×',
  '0.8×',
  '1.0×',
  '1.25×',
  '1.5×',
];
const List<String> translationProviderOptions = <String>[
  '本地 Ollama',
  'OpenAI',
  'OpenRouter',
  'SiliconFlow',
  'DeepSeek',
  'Google 翻译',
  '百度翻译',
  '阿里云翻译',
];
const List<String> asrProviderOptions = <String>[
  '本地 Whisper',
  '阿里云百炼',
  '腾讯云',
];
const List<String> localWhisperModelOptions = <String>[
  'tiny.en',
  'base.en',
  'small.en',
];
const List<String> oralCoachBackendOptions = <String>[
  '视频陪练管线',
  'LiveTalking',
  '本地 TTS',
];

/// Public HTTPS reverse proxy on ECS → GPU LiveTalking (phones must use this).
const String defaultLiveTalkingUrlPublic =
    'https://acquireenglish.curlhairai.com/livetalking';

/// Same-WiFi GPU box (optional LAN shortcut; not required).
const String defaultLiveTalkingUrlLan = 'http://192.168.31.121:8010';

/// @Deprecated Tailscale-only — do not use on phones. Alias of public URL.
const String defaultLiveTalkingUrl = defaultLiveTalkingUrlPublic;

/// @Deprecated Tailscale CGNAT — do not use on phones.
const String defaultLiveTalkingUrlIp = 'http://100.115.252.55:8010';

/// Legacy Tailscale-only URLs — migrate saved settings to the public base.
const Set<String> legacyTailscaleLiveTalkingUrls = <String>{
  'http://100.115.252.55:8010',
  'http://100.115.252.55:8010/',
  'http://5060ti.tailc30b42.ts.net:8010',
  'http://5060ti.tailc30b42.ts.net:8010/',
};

/// Probe order for digital-human connect (public HTTPS first).
const List<String> liveTalkingUrlCandidates = <String>[
  defaultLiveTalkingUrlPublic,
  defaultLiveTalkingUrlLan,
];

/// Default wav2lip avatar id on the GPU LiveTalking checkout.
const String defaultLiveTalkingAvatarId = 'wav2lip_avatar_glass_man';

/// Public STUN + TURNS so phones can receive GPU WebRTC media without Tailscale.
/// Mirrors `GET /coach/api/health` → `webrtc_ice_servers`.
const List<Map<String, dynamic>> defaultLiveTalkingIceServers =
    <Map<String, dynamic>>[
      <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      <String, dynamic>{
        'urls': 'turns:turn.curlhairai.com:443?transport=tcp',
        'username': 'acquire',
        'credential': 'sElj0IvyOQCe7vb6VIDCW8ax3KcKv3VT',
      },
    ];

/// Public Ollama OpenAI-compatible API (ECS nginx → GPU Tailscale :11434).
/// Phone needs no Tailscale — same pattern as LiveTalking.
const String defaultOllamaBaseUrl =
    'https://acquireenglish.curlhairai.com/ollama/v1';

/// Legacy Tailscale / LAN Ollama bases — migrate saved settings to public HTTPS.
const Set<String> legacyTailscaleOllamaBaseUrls = <String>{
  'http://100.115.252.55:11434/v1',
  'http://100.115.252.55:11434/v1/',
  'http://5060ti.tailc30b42.ts.net:11434/v1',
  'http://5060ti.tailc30b42.ts.net:11434/v1/',
  'http://192.168.31.121:11434/v1',
  'http://192.168.31.121:11434/v1/',
};

/// Ollama tag currently installed on 5060 Ti (EN↔ZH). Prefer 3b while sharing
/// VRAM with LiveTalking; pull `qwen2.5:7b` later if quality needs a bump.
const String defaultOllamaTranslationModel = 'qwen2.5:3b';

const String _learningSettingsStorageKey = 'learning_settings_v1';

class TranslationProviderPreset {
  const TranslationProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  final String name;
  final String baseUrl;
  final String model;
}

const Map<String, TranslationProviderPreset> translationProviderPresets =
    <String, TranslationProviderPreset>{
      '本地 Ollama': TranslationProviderPreset(
        name: '本地 Ollama',
        baseUrl: defaultOllamaBaseUrl,
        model: defaultOllamaTranslationModel,
      ),
      'OpenAI': TranslationProviderPreset(
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
      ),
      'OpenRouter': TranslationProviderPreset(
        name: 'OpenRouter',
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'openrouter/auto',
      ),
      'SiliconFlow': TranslationProviderPreset(
        name: 'SiliconFlow',
        baseUrl: 'https://api.siliconflow.com/v1',
        model: 'Qwen/Qwen3-32B',
      ),
      'DeepSeek': TranslationProviderPreset(
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
      ),
      'Google 翻译': TranslationProviderPreset(
        name: 'Google 翻译',
        baseUrl: 'https://translation.googleapis.com',
        model: '',
      ),
      '百度翻译': TranslationProviderPreset(
        name: '百度翻译',
        baseUrl: 'https://fanyi-api.baidu.com',
        model: '',
      ),
      '阿里云翻译': TranslationProviderPreset(
        name: '阿里云翻译',
        baseUrl: 'https://mt.cn-hangzhou.aliyuncs.com',
        model: 'general',
      ),
    };

const Map<String, TranslationProviderPreset> asrProviderPresets =
    <String, TranslationProviderPreset>{
      '本地 Whisper': TranslationProviderPreset(
        name: '本地 Whisper',
        baseUrl: 'local://whisper',
        model: 'base.en',
      ),
      '阿里云百炼': TranslationProviderPreset(
        name: '阿里云百炼',
        baseUrl: 'https://dashscope.aliyuncs.com',
        model: 'qwen3-asr-flash-filetrans',
      ),
      '腾讯云': TranslationProviderPreset(
        name: '腾讯云',
        baseUrl: 'https://asr.tencentcloudapi.com',
        model: '16k_en',
      ),
    };

class LearningSettingsState {
  const LearningSettingsState({
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    required this.playbackSpeed,
    required this.fontSize,
    required this.subtitleDelayMs,
    required this.dictionarySource,
    required this.highlightWords,
    required this.subtitleWordHighlightStyle,
    required this.subtitleWordHighlightBorderWidth,
    required this.reminder,
    required this.translationProvider,
    required this.translationApiKey,
    required this.translationApiSecret,
    required this.translationBaseUrl,
    required this.translationModel,
    required this.availableTranslationModels,
    required this.isFetchingTranslationModels,
    required this.useCustomTranslationEndpoint,
    required this.asrProvider,
    required this.asrApiKey,
    required this.asrBaseUrl,
    required this.asrModel,
    required this.useCustomAsrEndpoint,
    required this.generateBilingualAsrSubtitles,
    this.enableChineseSpeechAsr = false,
    required this.ttsEngine,
    required this.ttsVoice,
    required this.ttsRate,
    this.cloudApiBaseUrl = '',
    this.oralCoachBackend = '视频陪练管线',
    this.oralCoachServerUrl = defaultLiveTalkingUrlPublic,
    this.oralCoachPipelineUrl = 'https://acquireenglish.curlhairai.com/coach',
    this.voicePracticeServerUrl = '',
    this.liveKitUrl =
        'wss://acquireenglish-e5la1koz.livekit.cloud',
    this.bilibiliSessdata = '',
    this.bilibiliUserId = '',
    this.digitalHumanId = defaultDigitalHumanId,
    this.cartoonDigitalHuman = true,
  });

  factory LearningSettingsState.defaults() {
    // EN↔ZH defaults to GPU-box Ollama (qwen2.5) — not DeepSeek / OpenAI cloud.
    final TranslationProviderPreset defaultPreset =
        translationProviderPresets['本地 Ollama']!;
    // Phone installs often lack dart-define Bailian keys — default on-device.
    final TranslationProviderPreset defaultAsrPreset =
        asrProviderPresets['本地 Whisper']!;
    return LearningSettingsState(
      subtitleMode: '双语',
      playbackSpeed: '0.8×',
      fontSize: '中',
      subtitleDelayMs: 0,
      dictionarySource: '牛津学习者',
      highlightWords: true,
      subtitleWordHighlightStyle: '绿色填充',
      subtitleWordHighlightBorderWidth: 2.5,
      reminder: false,
      translationProvider: defaultPreset.name,
      translationApiKey: 'ollama',
      translationApiSecret: '',
      translationBaseUrl: defaultPreset.baseUrl,
      translationModel: defaultPreset.model,
      availableTranslationModels: const <String>[],
      isFetchingTranslationModels: false,
      useCustomTranslationEndpoint: false,
      asrProvider: defaultAsrPreset.name,
      asrApiKey: '',
      asrBaseUrl: defaultAsrPreset.baseUrl,
      asrModel: defaultAsrPreset.model.isEmpty
          ? 'base.en'
          : defaultAsrPreset.model,
      useCustomAsrEndpoint: false,
      generateBilingualAsrSubtitles: true,
      enableChineseSpeechAsr: false,
      ttsEngine: '',
      ttsVoice: '',
      ttsRate: 0.75,
    );
  }

  final String subtitleMode;
  final String subtitleLetterCase;
  final String playbackSpeed;
  final String fontSize;
  final int subtitleDelayMs;
  final String dictionarySource;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final bool reminder;
  final String translationProvider;
  final String translationApiKey;
  final String translationApiSecret;
  final String translationBaseUrl;
  final String translationModel;
  final List<String> availableTranslationModels;
  final bool isFetchingTranslationModels;
  final bool useCustomTranslationEndpoint;
  final String asrProvider;
  final String asrApiKey;
  final String asrBaseUrl;
  final String asrModel;
  final bool useCustomAsrEndpoint;
  final bool generateBilingualAsrSubtitles;

  /// Optional on-device Chinese speech ASR (needs multilingual Whisper `base`).
  final bool enableChineseSpeechAsr;
  final String ttsEngine;
  final String ttsVoice;
  final double ttsRate;
  /// Empty → use compile-time [Endpoints.baseUrl] (`API_BASE`).
  final String cloudApiBaseUrl;
  final String oralCoachBackend;
  final String oralCoachServerUrl;
  /// Hosted or LAN `tools/oral_coach` pipeline.
  final String oralCoachPipelineUrl;
  /// Laptop sidecar for [Zemksh/voice](https://github.com/Zemksh/voice), e.g. http://192.168.1.8:8765
  final String voicePracticeServerUrl;
  /// Optional LiveKit ws URL for full-duplex; empty = HTTP draft/confirm pipeline.
  final String liveKitUrl;
  final String bilibiliSessdata;
  /// DedeUserID from QR login (display only).
  final String bilibiliUserId;
  /// Selected digital-human persona id (see [digitalHumanCatalog]).
  final String digitalHumanId;
  final bool cartoonDigitalHuman;

  /// Auth / sync API used by the mobile app (server-deployed).
  String get resolvedCloudApiBaseUrl {
    final String fromSettings = cloudApiBaseUrl.trim();
    if (fromSettings.isNotEmpty) {
      return Endpoints.normalizeBaseUrl(fromSettings);
    }
    return Endpoints.normalizeBaseUrl(Endpoints.baseUrl);
  }

  bool get usesLiveTalkingCoach =>
      oralCoachBackend == 'LiveTalking' &&
      resolvedOralCoachServerUrl.trim().isNotEmpty;

  bool get usesOralCoachPipeline =>
      oralCoachBackend == '视频陪练管线' && oralCoachPipelineUrl.trim().isNotEmpty;

  bool get usesVoicePractice => voicePracticeServerUrl.trim().isNotEmpty;

  bool get usesLiveKit => liveKitUrl.trim().isNotEmpty;

  /// LiveTalking / 数字人 base URL (settings → public HTTPS).
  String get resolvedOralCoachServerUrl {
    final String fromSettings = oralCoachServerUrl.trim();
    if (fromSettings.isNotEmpty) {
      final String normalized = fromSettings.replaceAll(RegExp(r'/+$'), '');
      // Migrate away from Tailscale-only endpoints on phones.
      if (normalized.contains('100.115.252.55') ||
          normalized.contains('ts.net')) {
        return defaultLiveTalkingUrlPublic;
      }
      return normalized;
    }
    return defaultLiveTalkingUrlPublic;
  }

  /// Show a coach stage (local avatar / fixed motions). Does **not** imply
  /// LiveTalking WebRTC lip-sync — that is [usesRealtimeLipSync] only.
  bool get wantsDigitalHumanAvatar =>
      usesLiveTalkingCoach ||
      usesOralCoachPipeline ||
      oralCoachBackend == '本地 TTS';

  /// Real-time wav2lip WebRTC on the GPU box. Expensive; default pipeline
  /// conversation uses a local avatar + TTS instead.
  bool get usesRealtimeLipSync => !cartoonDigitalHuman &&
      (usesLiveTalkingCoach || usesOralCoachPipeline);

  bool get isBilibiliLoggedIn => hasBilibiliCookie;

  /// Settings UI key wins; otherwise fall back to `.env` / dart-define.
  String get resolvedAsrApiKey {
    final String fromSettings = asrApiKey.trim();
    if (fromSettings.isNotEmpty) {
      return fromSettings;
    }
    if (asrProvider == '阿里云百炼' || asrProvider == 'Alibaba Cloud') {
      return EnvConfig.bailianAsrApiKey;
    }
    return '';
  }

  bool get asrApiKeyFromEnv =>
      asrApiKey.trim().isEmpty &&
      (asrProvider == '阿里云百炼' || asrProvider == 'Alibaba Cloud') &&
      EnvConfig.hasBailianAsrApiKey;

  /// Settings SESSDATA wins; otherwise `.env` / dart-define Cookie header.
  String get resolvedBilibiliCookieHeader {
    final String fromSettings = bilibiliSessdata.trim();
    if (fromSettings.isNotEmpty) {
      if (fromSettings.toLowerCase().contains('sessdata=')) {
        return fromSettings;
      }
      return 'SESSDATA=$fromSettings';
    }
    return EnvConfig.bilibiliCookieHeader;
  }

  bool get bilibiliCookieFromEnv =>
      bilibiliSessdata.trim().isEmpty && EnvConfig.hasBilibiliCookie;

  bool get hasBilibiliCookie => resolvedBilibiliCookieHeader.isNotEmpty;

  LearningSettingsState copyWith({
    String? subtitleMode,
    String? subtitleLetterCase,
    String? playbackSpeed,
    String? fontSize,
    int? subtitleDelayMs,
    String? dictionarySource,
    bool? highlightWords,
    String? subtitleWordHighlightStyle,
    double? subtitleWordHighlightBorderWidth,
    bool? reminder,
    String? translationProvider,
    String? translationApiKey,
    String? translationApiSecret,
    String? translationBaseUrl,
    String? translationModel,
    List<String>? availableTranslationModels,
    bool? isFetchingTranslationModels,
    bool? useCustomTranslationEndpoint,
    String? asrProvider,
    String? asrApiKey,
    String? asrBaseUrl,
    String? asrModel,
    bool? useCustomAsrEndpoint,
    bool? generateBilingualAsrSubtitles,
    bool? enableChineseSpeechAsr,
    String? ttsEngine,
    String? ttsVoice,
    double? ttsRate,
    String? cloudApiBaseUrl,
    String? oralCoachBackend,
    String? oralCoachServerUrl,
    String? oralCoachPipelineUrl,
    String? voicePracticeServerUrl,
    String? liveKitUrl,
    String? bilibiliSessdata,
    String? bilibiliUserId,
    String? digitalHumanId,
    bool? cartoonDigitalHuman,
  }) {
    return LearningSettingsState(
      subtitleMode: subtitleMode ?? this.subtitleMode,
      subtitleLetterCase: subtitleLetterCase ?? this.subtitleLetterCase,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      fontSize: fontSize ?? this.fontSize,
      subtitleDelayMs: subtitleDelayMs ?? this.subtitleDelayMs,
      dictionarySource: dictionarySource ?? this.dictionarySource,
      highlightWords: highlightWords ?? this.highlightWords,
      subtitleWordHighlightStyle:
          subtitleWordHighlightStyle ?? this.subtitleWordHighlightStyle,
      subtitleWordHighlightBorderWidth:
          subtitleWordHighlightBorderWidth ??
          this.subtitleWordHighlightBorderWidth,
      reminder: reminder ?? this.reminder,
      translationProvider: translationProvider ?? this.translationProvider,
      translationApiKey: translationApiKey ?? this.translationApiKey,
      translationApiSecret: translationApiSecret ?? this.translationApiSecret,
      translationBaseUrl: translationBaseUrl ?? this.translationBaseUrl,
      translationModel: translationModel ?? this.translationModel,
      availableTranslationModels:
          availableTranslationModels ?? this.availableTranslationModels,
      isFetchingTranslationModels:
          isFetchingTranslationModels ?? this.isFetchingTranslationModels,
      useCustomTranslationEndpoint:
          useCustomTranslationEndpoint ?? this.useCustomTranslationEndpoint,
      asrProvider: asrProvider ?? this.asrProvider,
      asrApiKey: asrApiKey ?? this.asrApiKey,
      asrBaseUrl: asrBaseUrl ?? this.asrBaseUrl,
      asrModel: asrModel ?? this.asrModel,
      useCustomAsrEndpoint: useCustomAsrEndpoint ?? this.useCustomAsrEndpoint,
      generateBilingualAsrSubtitles:
          generateBilingualAsrSubtitles ?? this.generateBilingualAsrSubtitles,
      enableChineseSpeechAsr:
          enableChineseSpeechAsr ?? this.enableChineseSpeechAsr,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsRate: ttsRate ?? this.ttsRate,
      cloudApiBaseUrl: cloudApiBaseUrl ?? this.cloudApiBaseUrl,
      oralCoachBackend: oralCoachBackend ?? this.oralCoachBackend,
      oralCoachServerUrl: oralCoachServerUrl ?? this.oralCoachServerUrl,
      oralCoachPipelineUrl: oralCoachPipelineUrl ?? this.oralCoachPipelineUrl,
      voicePracticeServerUrl:
          voicePracticeServerUrl ?? this.voicePracticeServerUrl,
      liveKitUrl: liveKitUrl ?? this.liveKitUrl,
      bilibiliSessdata: bilibiliSessdata ?? this.bilibiliSessdata,
      bilibiliUserId: bilibiliUserId ?? this.bilibiliUserId,
      digitalHumanId: digitalHumanId ?? this.digitalHumanId,
      cartoonDigitalHuman: cartoonDigitalHuman ?? this.cartoonDigitalHuman,
    );
  }

  double get fontScale => playerFontScales[fontSize] ?? 1;

  DigitalHumanPersona get selectedDigitalHuman =>
      digitalHumanById(digitalHumanId);
}

final NotifierProvider<LearningSettingsNotifier, LearningSettingsState>
learningSettingsProvider =
    NotifierProvider<LearningSettingsNotifier, LearningSettingsState>(
      LearningSettingsNotifier.new,
    );

final Provider<TranslationModelService> translationModelServiceProvider =
    Provider<TranslationModelService>(
      (Ref ref) => const TranslationModelService(),
    );

class TranslationModelService {
  const TranslationModelService({this.httpRequestOverride});

  final Future<Response<dynamic>> Function({
    required BaseOptions options,
    required String path,
  })?
  httpRequestOverride;

  Future<List<String>> fetchModels({
    required LearningSettingsState settings,
  }) async {
    final String apiKey = settings.translationApiKey.trim().isNotEmpty
        ? settings.translationApiKey.trim()
        : (settings.translationProvider == '本地 Ollama' ? 'ollama' : '');
    final Response<dynamic> response = httpRequestOverride != null
        ? await httpRequestOverride!(
            options: BaseOptions(
              baseUrl: settings.translationBaseUrl,
              headers: <String, String>{
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
            path: '/models',
          )
        : await Dio(
            BaseOptions(
              baseUrl: settings.translationBaseUrl,
              headers: <String, String>{
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          ).get<dynamic>('/models');

    final dynamic data = response.data;
    final List<dynamic> modelItems = data is Map<String, dynamic>
        ? (data['data'] as List<dynamic>? ?? <dynamic>[])
        : data is List<dynamic>
        ? data
        : <dynamic>[];

    return modelItems
        .map((dynamic item) => (item as Map<String, dynamic>)['id'] as String?)
        .whereType<String>()
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }
}

class LearningSettingsNotifier extends Notifier<LearningSettingsState> {
  @override
  LearningSettingsState build() {
    // Push local Bilibili cookie after cloud login (token may arrive later).
    ref.listen<AuthSessionState>(authSessionProvider, (
      AuthSessionState? previous,
      AuthSessionState next,
    ) {
      if (!next.isLoggedIn) {
        return;
      }
      if (previous?.isLoggedIn == true &&
          previous?.accessToken == next.accessToken) {
        return;
      }
      // Defer until build() has returned and `state` is assigned.
      Future<void>.microtask(() {
        if (!ref.mounted) {
          return;
        }
        _scheduleSyncBilibiliCookieToCloud(state);
      });
    });

    final LearningSettingsState defaults = LearningSettingsState.defaults();
    if (!Hive.isBoxOpen('prefs')) {
      _scheduleApplyCloudApiBase(defaults);
      return defaults;
    }

    final String? raw = Hive.box<String>(
      'prefs',
    ).get(_learningSettingsStorageKey);
    if (raw == null || raw.isEmpty) {
      _scheduleApplyCloudApiBase(defaults);
      return defaults;
    }

    try {
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      final String? asrProvider = _asrProviderOrNull(json['asrProvider']);
      final LearningSettingsState loaded = defaults.copyWith(
        subtitleMode: _normalizeSubtitleModeOrNull(json['subtitleMode']),
        subtitleLetterCase:
            subtitleLetterCaseOptions.contains(json['subtitleLetterCase'])
            ? json['subtitleLetterCase'] as String
            : null,
        playbackSpeed: _stringOrNull(json['playbackSpeed']),
        fontSize: _stringOrNull(json['fontSize']),
        subtitleDelayMs: _intOrNull(json['subtitleDelayMs']),
        dictionarySource: _stringOrNull(json['dictionarySource']),
        highlightWords: _boolOrNull(json['highlightWords']),
        subtitleWordHighlightStyle: _subtitleWordHighlightStyleOrNull(
          json['subtitleWordHighlightStyle'],
        ),
        subtitleWordHighlightBorderWidth:
            _subtitleWordHighlightBorderWidthOrNull(
              json['subtitleWordHighlightBorderWidth'],
            ),
        reminder: _boolOrNull(json['reminder']),
        translationProvider: _translationProviderOrNull(
          json['translationProvider'],
        ),
        translationApiKey: _stringOrNull(json['translationApiKey']),
        translationApiSecret: _stringOrNull(json['translationApiSecret']),
        translationBaseUrl: _stringOrNull(json['translationBaseUrl']),
        translationModel: _stringOrNull(json['translationModel']),
        useCustomTranslationEndpoint: _boolOrNull(
          json['useCustomTranslationEndpoint'],
        ),
        asrProvider: asrProvider,
        asrApiKey: asrProvider == null
            ? null
            : _stringOrNull(json['asrApiKey']),
        asrBaseUrl: asrProvider == null
            ? null
            : _stringOrNull(json['asrBaseUrl']),
        asrModel: asrProvider == null ? null : _stringOrNull(json['asrModel']),
        useCustomAsrEndpoint: asrProvider == null
            ? null
            : _boolOrNull(json['useCustomAsrEndpoint']),
        generateBilingualAsrSubtitles: _boolOrNull(
          json['generateBilingualAsrSubtitles'],
        ),
        enableChineseSpeechAsr: _boolOrNull(json['enableChineseSpeechAsr']),
        ttsEngine: _stringOrNull(json['ttsEngine']),
        ttsVoice: _stringOrNull(json['ttsVoice']),
        ttsRate: _doubleOrNull(json['ttsRate']),
        cloudApiBaseUrl: _stringOrNull(json['cloudApiBaseUrl']),
        oralCoachBackend: oralCoachBackendOptions.contains(
              json['oralCoachBackend'],
            )
            ? json['oralCoachBackend'] as String
            : null,
        oralCoachServerUrl: _stringOrNull(json['oralCoachServerUrl']),
        oralCoachPipelineUrl: _stringOrNull(json['oralCoachPipelineUrl']),
        voicePracticeServerUrl: _stringOrNull(json['voicePracticeServerUrl']),
        liveKitUrl: _stringOrNull(json['liveKitUrl']),
        bilibiliSessdata: _stringOrNull(json['bilibiliSessdata']),
        bilibiliUserId: _stringOrNull(json['bilibiliUserId']),
        cartoonDigitalHuman: json['cartoonDigitalHuman'] is bool ? json['cartoonDigitalHuman'] as bool : true,
        digitalHumanId: () {
          final String? raw = _stringOrNull(json['digitalHumanId']);
          if (raw == null || raw.isEmpty) {
            return defaultDigitalHumanId;
          }
          return digitalHumanById(raw).id;
        }(),
      );
      LearningSettingsState coerced =
          _fallbackLocalWhisperIfCloudKeyMissing(loaded);
      coerced = _preferGpuOllamaTranslation(coerced);
      // Prod LiveKit was added after some installs saved an empty liveKitUrl.
      if (coerced.liveKitUrl.trim().isEmpty) {
        coerced = coerced.copyWith(
          liveKitUrl: LearningSettingsState.defaults().liveKitUrl,
        );
      }
      // Digital-human URL: empty → public HTTPS; migrate Tailscale / LAN saves.
      final String oralCoachUrl = coerced.oralCoachServerUrl.trim();
      if (oralCoachUrl.isEmpty ||
          legacyTailscaleLiveTalkingUrls.contains(oralCoachUrl) ||
          oralCoachUrl.contains('100.115.252.55') ||
          oralCoachUrl.contains('ts.net') ||
          oralCoachUrl.contains('192.168.31.121')) {
        coerced = coerced.copyWith(
          oralCoachServerUrl: defaultLiveTalkingUrlPublic,
        );
      }
      // Translation Ollama: migrate Tailscale / LAN → public HTTPS.
      final String ollamaBase = coerced.translationBaseUrl.trim();
      if (coerced.translationProvider == '本地 Ollama' &&
          (ollamaBase.isEmpty ||
              legacyTailscaleOllamaBaseUrls.contains(ollamaBase) ||
              ollamaBase.contains('100.115.252.55:11434') ||
              (ollamaBase.contains('ts.net') &&
                  ollamaBase.contains(':11434')))) {
        coerced = coerced.copyWith(translationBaseUrl: defaultOllamaBaseUrl);
      }
      // Typo host that breaks DNS (caurlhairai → curlhairai).
      coerced = coerced.copyWith(
        oralCoachPipelineUrl: fixCurlhairaiTypoHost(
          coerced.oralCoachPipelineUrl,
        ),
        oralCoachServerUrl: fixCurlhairaiTypoHost(coerced.oralCoachServerUrl),
        voicePracticeServerUrl: fixCurlhairaiTypoHost(
          coerced.voicePracticeServerUrl,
        ),
        cloudApiBaseUrl: fixCurlhairaiTypoHost(coerced.cloudApiBaseUrl),
        liveKitUrl: fixCurlhairaiTypoHost(coerced.liveKitUrl),
        translationBaseUrl: fixCurlhairaiTypoHost(coerced.translationBaseUrl),
      );
      _scheduleApplyCloudApiBase(coerced);
      if (coerced.asrProvider != loaded.asrProvider ||
          coerced.translationProvider != loaded.translationProvider ||
          coerced.translationBaseUrl != loaded.translationBaseUrl ||
          coerced.translationModel != loaded.translationModel ||
          coerced.liveKitUrl != loaded.liveKitUrl ||
          coerced.oralCoachPipelineUrl != loaded.oralCoachPipelineUrl ||
          coerced.oralCoachServerUrl != loaded.oralCoachServerUrl ||
          coerced.voicePracticeServerUrl != loaded.voicePracticeServerUrl ||
          coerced.cloudApiBaseUrl != loaded.cloudApiBaseUrl) {
        Future.microtask(() {
          if (!ref.mounted) {
            return;
          }
          state = coerced;
          _persist();
        });
      }
      if (coerced.hasBilibiliCookie) {
        _scheduleSyncBilibiliCookieToCloud(coerced);
      }
      return coerced;
    } catch (_) {
      _scheduleApplyCloudApiBase(defaults);
      return defaults;
    }
  }

  void _scheduleApplyCloudApiBase(LearningSettingsState settings) {
    Future.microtask(() {
      if (!ref.mounted) {
        return;
      }
      ref
          .read(networkRepositoryProvider.notifier)
          .setBaseUrl(settings.resolvedCloudApiBaseUrl);
    });
  }

  /// Cloud ASR without a key typed in Settings → fall back to on-device Whisper.
  /// (Env/dart-define Bailian keys alone must not keep the import queue on
  /// cloud uploads; mobile completion always prefers Whisper.)
  LearningSettingsState _fallbackLocalWhisperIfCloudKeyMissing(
    LearningSettingsState settings,
  ) {
    if (settings.asrProvider == '本地 Whisper') {
      return settings;
    }
    // Only keep cloud ASR when the user explicitly saved a key in Settings.
    if (settings.asrApiKey.trim().isNotEmpty) {
      return settings;
    }
    final TranslationProviderPreset local =
        asrProviderPresets['本地 Whisper']!;
    return settings.copyWith(
      asrProvider: local.name,
      asrApiKey: '',
      asrBaseUrl: local.baseUrl,
      asrModel: local.model.isEmpty ? 'base.en' : local.model,
      useCustomAsrEndpoint: false,
    );
  }

  /// Point EN↔ZH at 5060 Ti Ollama when the user never configured a paid API.
  ///
  /// Keeps DeepSeek / OpenAI / etc. if they already saved a real key.
  LearningSettingsState _preferGpuOllamaTranslation(
    LearningSettingsState settings,
  ) {
    final TranslationProviderPreset ollama =
        translationProviderPresets['本地 Ollama']!;
    final String provider = settings.translationProvider.trim();
    final String key = settings.translationApiKey.trim();
    final bool unpaidCloud =
        (provider == 'OpenAI' ||
            provider == 'DeepSeek' ||
            provider == 'OpenRouter' ||
            provider == 'SiliconFlow') &&
        (key.isEmpty || key == 'ollama');
    final bool alreadyOllama = provider == '本地 Ollama';
    if (!unpaidCloud && !alreadyOllama) {
      return settings;
    }
    final String model = settings.translationModel.trim();
    final bool staleSevenB = model == 'qwen2.5:7b' || model.isEmpty;
    return settings.copyWith(
      translationProvider: ollama.name,
      translationBaseUrl: settings.useCustomTranslationEndpoint
          ? settings.translationBaseUrl
          : ollama.baseUrl,
      translationModel: alreadyOllama && !staleSevenB
          ? settings.translationModel
          : ollama.model,
      translationApiKey: key.isEmpty ? 'ollama' : settings.translationApiKey,
    );
  }

  void setSubtitleMode(String value) {
    final String normalized = _normalizeSubtitleMode(value);
    if (!subtitleModeOptions.contains(normalized)) {
      return;
    }
    state = state.copyWith(subtitleMode: normalized);
    _persist();
  }

  void setSubtitleLetterCase(String value) {
    if (!subtitleLetterCaseOptions.contains(value)) return;
    state = state.copyWith(subtitleLetterCase: value);
    _persist();
  }

  void setPlaybackSpeed(String value) {
    if (!playbackSpeedOptions.contains(value)) {
      return;
    }
    state = state.copyWith(playbackSpeed: value);
    _persist();
  }

  void setFontSize(String value) {
    if (!playerFontOptions.contains(value)) {
      return;
    }
    state = state.copyWith(fontSize: value);
    _persist();
  }

  void setSubtitleDelayMs(int value) {
    state = state.copyWith(subtitleDelayMs: value.clamp(-5000, 5000));
    _persist();
  }

  void setDictionarySource(String value) {
    state = state.copyWith(dictionarySource: value);
    _persist();
  }

  void setTranslationProvider(String value) {
    if (!translationProviderOptions.contains(value)) {
      return;
    }
    final TranslationProviderPreset preset = translationProviderPresets[value]!;
    final bool isOllama = value == '本地 Ollama';
    state = state.copyWith(
      translationProvider: value,
      translationBaseUrl: preset.baseUrl,
      translationModel: preset.model,
      // Ollama ignores the key; keep a non-empty placeholder for shared checks.
      translationApiKey: isOllama && state.translationApiKey.trim().isEmpty
          ? 'ollama'
          : state.translationApiKey,
      availableTranslationModels: isOllama
          ? <String>[
              defaultOllamaTranslationModel,
              'qwen2.5:7b',
              'qwen3:8b',
              'qwen3:4b',
            ]
          : const <String>[],
      isFetchingTranslationModels: false,
    );
    _persist();
  }

  void setTranslationApiKey(String value) {
    state = state.copyWith(translationApiKey: value.trim());
    _persist();
  }

  void setTranslationApiSecret(String value) {
    state = state.copyWith(translationApiSecret: value.trim());
    _persist();
  }

  void setUseCustomTranslationEndpoint({required bool value}) {
    if (value) {
      state = state.copyWith(useCustomTranslationEndpoint: true);
      _persist();
      return;
    }

    final TranslationProviderPreset preset =
        translationProviderPresets[state.translationProvider]!;
    state = state.copyWith(
      useCustomTranslationEndpoint: false,
      translationBaseUrl: preset.baseUrl,
      translationModel: preset.model,
    );
    _persist();
  }

  void setTranslationBaseUrl(String value) {
    state = state.copyWith(translationBaseUrl: value.trim());
    _persist();
  }

  void setTranslationModel(String value) {
    state = state.copyWith(translationModel: value.trim());
    _persist();
  }

  Future<List<String>> fetchTranslationModels() async {
    if (!_isAiProvider(state.translationProvider)) {
      return const <String>[];
    }
    if (state.translationApiKey.isEmpty &&
        state.translationProvider != '本地 Ollama') {
      throw StateError('missing-api-key');
    }

    state = state.copyWith(isFetchingTranslationModels: true);
    try {
      final List<String> models = await ref
          .read(translationModelServiceProvider)
          .fetchModels(settings: state);
      state = state.copyWith(
        isFetchingTranslationModels: false,
        availableTranslationModels: models,
        translationModel:
            models.contains(state.translationModel) || models.isEmpty
            ? state.translationModel
            : models.first,
      );
      return models;
    } catch (_) {
      state = state.copyWith(isFetchingTranslationModels: false);
      rethrow;
    }
  }

  void setAsrProvider(String value) {
    final String provider = _normalizeAsrProvider(value);
    if (!asrProviderOptions.contains(provider)) {
      return;
    }
    final TranslationProviderPreset preset = asrProviderPresets[provider]!;
    state = state.copyWith(
      asrProvider: provider,
      asrBaseUrl: preset.baseUrl,
      asrModel: preset.model,
    );
    _persist();
  }

  void setAsrApiKey(String value) {
    state = state.copyWith(asrApiKey: value.trim());
    _persist();
  }

  void setGenerateBilingualAsrSubtitles({required bool value}) {
    state = state.copyWith(generateBilingualAsrSubtitles: value);
    _persist();
  }

  void setEnableChineseSpeechAsr({required bool value}) {
    state = state.copyWith(enableChineseSpeechAsr: value);
    _persist();
  }

  void setUseCustomAsrEndpoint({required bool value}) {
    if (value) {
      state = state.copyWith(useCustomAsrEndpoint: true);
      _persist();
      return;
    }

    final TranslationProviderPreset preset =
        asrProviderPresets[state.asrProvider]!;
    state = state.copyWith(
      useCustomAsrEndpoint: false,
      asrBaseUrl: preset.baseUrl,
      asrModel: preset.model,
    );
    _persist();
  }

  void setAsrBaseUrl(String value) {
    state = state.copyWith(asrBaseUrl: value.trim());
    _persist();
  }

  void setAsrModel(String value) {
    state = state.copyWith(asrModel: value.trim());
    _persist();
  }

  void setHighlightWords({required bool value}) {
    state = state.copyWith(highlightWords: value);
    _persist();
  }

  void setSubtitleWordHighlightStyle(String value) {
    if (!subtitleWordHighlightStyleOptions.contains(value)) {
      return;
    }
    state = state.copyWith(subtitleWordHighlightStyle: value);
    _persist();
  }

  void setSubtitleWordHighlightBorderWidth(double value) {
    state = state.copyWith(
      subtitleWordHighlightBorderWidth: value.clamp(1.5, 3.5),
    );
    _persist();
  }

  void setReminder({required bool value}) {
    state = state.copyWith(reminder: value);
    _persist();
  }

  void setTtsEngine(String value) {
    state = state.copyWith(ttsEngine: value.trim(), ttsVoice: '');
    _persist();
  }

  void setTtsVoice(String value) {
    state = state.copyWith(ttsVoice: value.trim());
    _persist();
  }

  void setTtsRate(double value) {
    state = state.copyWith(
      ttsRate: value.clamp(ttsRateOptions.first, ttsRateOptions.last),
    );
    _persist();
  }

  void setCloudApiBaseUrl(String value) {
    state = state.copyWith(
      cloudApiBaseUrl: fixCurlhairaiTypoHost(value.trim()),
    );
    _persist();
    ref
        .read(networkRepositoryProvider.notifier)
        .setBaseUrl(state.resolvedCloudApiBaseUrl);
  }

  void setOralCoachBackend(String value) {
    if (!oralCoachBackendOptions.contains(value)) {
      return;
    }
    state = state.copyWith(oralCoachBackend: value);
    _persist();
  }

  void setOralCoachServerUrl(String value) {
    state = state.copyWith(
      oralCoachServerUrl: fixCurlhairaiTypoHost(value.trim()),
    );
    _persist();
  }

  void setOralCoachPipelineUrl(String value) {
    state = state.copyWith(
      oralCoachPipelineUrl: fixCurlhairaiTypoHost(value.trim()),
    );
    _persist();
  }

  void setVoicePracticeServerUrl(String value) {
    state = state.copyWith(
      voicePracticeServerUrl: fixCurlhairaiTypoHost(value.trim()),
    );
    _persist();
  }

  void setLiveKitUrl(String value) {
    state = state.copyWith(liveKitUrl: fixCurlhairaiTypoHost(value.trim()));
    _persist();
  }

  void setCartoonDigitalHuman(bool value) {
    state = state.copyWith(cartoonDigitalHuman: value);
    _persist();
  }

  void setDigitalHumanId(String value) {
    state = state.copyWith(digitalHumanId: digitalHumanById(value).id);
    _persist();
  }

  void setBilibiliSessdata(String value) {
    state = state.copyWith(bilibiliSessdata: value.trim());
    _persist();
    _scheduleSyncBilibiliCookieToCloud(state);
  }

  void setBilibiliLogin({
    required String cookieOrSessdata,
    String userId = '',
  }) {
    state = state.copyWith(
      bilibiliSessdata: cookieOrSessdata.trim(),
      bilibiliUserId: userId.trim(),
    );
    _persist();
    _scheduleSyncBilibiliCookieToCloud(state);
  }

  void clearBilibiliLogin() {
    state = state.copyWith(bilibiliSessdata: '', bilibiliUserId: '');
    _persist();
    _scheduleSyncBilibiliCookieToCloud(state, clear: true);
  }

  void _scheduleSyncBilibiliCookieToCloud(
    LearningSettingsState settings, {
    bool clear = false,
  }) {
    unawaited(
      syncBilibiliCookieToCloudNow(
        settingsOverride: settings,
        clear: clear,
      ),
    );
  }

  /// Returns null on success, otherwise a short error message.
  Future<String?> syncBilibiliCookieToCloudNow({
    LearningSettingsState? settingsOverride,
    bool clear = false,
  }) async {
    final LearningSettingsState settings = settingsOverride ?? state;
    final String cookie = clear
        ? ''
        : settings.resolvedBilibiliCookieHeader.trim();
    if (!clear && cookie.isEmpty) {
      return '本地没有 B 站 Cookie';
    }
    for (int attempt = 0; attempt < 6; attempt++) {
      if (!ref.mounted) {
        return '页面已关闭';
      }
      final AuthSessionState auth = ref.read(authSessionProvider);
      if (!auth.isLoggedIn) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        continue;
      }
      ref.read(networkRepositoryProvider.notifier).setToken(auth.accessToken);
      try {
        final AcquireApiClient api = ref.read(acquireApiClientProvider);
        final AcquirePreferencesDto current = await api.getPreferences();
        final AcquirePreferencesDto saved = await api.putPreferences(
          current.copyWith(bilibiliCookie: cookie),
        );
        if (!clear && !saved.hasBilibiliCookie) {
          return '服务器未确认写入';
        }
        if (clear && saved.hasBilibiliCookie) {
          return '服务器未确认清除 Cookie';
        }
        return null;
      } catch (error) {
        if (attempt >= 5) {
          return error.toString();
        }
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    return '未登录云端账号';
  }

  void resetToDefaults() {
    state = LearningSettingsState.defaults();
    _persist();
    ref
        .read(networkRepositoryProvider.notifier)
        .setBaseUrl(state.resolvedCloudApiBaseUrl);
  }

  void _persist() {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    unawaited(
      Hive.box<String>('prefs').put(
        _learningSettingsStorageKey,
        jsonEncode(<String, Object?>{
          'subtitleMode': state.subtitleMode,
          'subtitleLetterCase': state.subtitleLetterCase,
          'playbackSpeed': state.playbackSpeed,
          'fontSize': state.fontSize,
          'subtitleDelayMs': state.subtitleDelayMs,
          'dictionarySource': state.dictionarySource,
          'highlightWords': state.highlightWords,
          'subtitleWordHighlightStyle': state.subtitleWordHighlightStyle,
          'subtitleWordHighlightBorderWidth':
              state.subtitleWordHighlightBorderWidth,
          'reminder': state.reminder,
          'translationProvider': state.translationProvider,
          'translationApiKey': state.translationApiKey,
          'translationApiSecret': state.translationApiSecret,
          'translationBaseUrl': state.translationBaseUrl,
          'translationModel': state.translationModel,
          'useCustomTranslationEndpoint': state.useCustomTranslationEndpoint,
          'asrProvider': state.asrProvider,
          'asrApiKey': state.asrApiKey,
          'asrBaseUrl': state.asrBaseUrl,
          'asrModel': state.asrModel,
          'useCustomAsrEndpoint': state.useCustomAsrEndpoint,
          'generateBilingualAsrSubtitles': state.generateBilingualAsrSubtitles,
          'enableChineseSpeechAsr': state.enableChineseSpeechAsr,
          'ttsEngine': state.ttsEngine,
          'ttsVoice': state.ttsVoice,
          'ttsRate': state.ttsRate,
          'cloudApiBaseUrl': state.cloudApiBaseUrl,
          'oralCoachBackend': state.oralCoachBackend,
          'oralCoachServerUrl': state.oralCoachServerUrl,
          'oralCoachPipelineUrl': state.oralCoachPipelineUrl,
          'voicePracticeServerUrl': state.voicePracticeServerUrl,
          'liveKitUrl': state.liveKitUrl,
          'bilibiliSessdata': state.bilibiliSessdata,
          'bilibiliUserId': state.bilibiliUserId,
          'digitalHumanId': state.digitalHumanId,
          'cartoonDigitalHuman': state.cartoonDigitalHuman,
        }),
      ),
    );
  }

  String _normalizeSubtitleMode(String value) {
    switch (value.trim()) {
      case '单英':
        return '英文';
      case '单中':
        return '中文';
      case '隐藏':
        // Hidden is no longer a learning preset; restore bilingual.
        return '双语';
      case '英文':
      case '中文':
      case '双语':
      case '盲听':
        return value.trim();
      default:
        return '双语';
    }
  }

  String? _normalizeSubtitleModeOrNull(Object? value) {
    final String? raw = _stringOrNull(value);
    if (raw == null) {
      return null;
    }
    final String normalized = _normalizeSubtitleMode(raw);
    return subtitleModeOptions.contains(normalized) ? normalized : null;
  }

  String? _stringOrNull(Object? value) {
    final String? raw = value as String?;
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return raw.trim();
  }

  bool? _boolOrNull(Object? value) => value as bool?;

  double? _doubleOrNull(Object? value) =>
      value is num ? value.toDouble() : null;

  String? _subtitleWordHighlightStyleOrNull(Object? value) {
    final String? style = _stringOrNull(value);
    if (style == null) {
      return null;
    }
    if (legacySubtitleWordHighlightStyles.contains(style)) {
      return '绿色填充';
    }
    return subtitleWordHighlightStyleOptions.contains(style) ? style : null;
  }

  double? _subtitleWordHighlightBorderWidthOrNull(Object? value) {
    final double? width = _doubleOrNull(value);
    return width != null && width >= 1.5 && width <= 3.5 ? width : null;
  }

  int? _intOrNull(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return null;
  }

  String? _translationProviderOrNull(Object? value) {
    final String? provider = _stringOrNull(value);
    if (provider == null || !translationProviderOptions.contains(provider)) {
      return null;
    }
    return provider;
  }

  String? _asrProviderOrNull(Object? value) {
    final String? rawProvider = _stringOrNull(value);
    final String? provider = rawProvider == null
        ? null
        : _normalizeAsrProvider(rawProvider);
    if (provider == null || !asrProviderOptions.contains(provider)) {
      return null;
    }
    return provider;
  }

  String _normalizeAsrProvider(String value) {
    if (value == 'Tencent Cloud') return '腾讯云';
    if (value == 'Alibaba Cloud') return '阿里云百炼';
    return value;
  }

  bool _isAiProvider(String provider) {
    return provider == '本地 Ollama' ||
        provider == 'OpenAI' ||
        provider == 'OpenRouter' ||
        provider == 'SiliconFlow' ||
        provider == 'DeepSeek';
  }
}
