import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../constants/feature_flags.dart';
import '../../../router/app_router.dart';
import '../../../utils/url_utils.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/local_whisper_asr.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../sync/data/progress_sync_service.dart';
import '../../sync/data/vocab_sync_service.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'ai_subtitle_management_screen.dart';
import 'app_update_provider.dart';
import '../../home/presentation/widgets/theme_widget.dart';
import 'bilibili_login_sheet.dart';
import 'learning_preferences_screen.dart';
import 'settings_provider.dart';
import 'widgets/api_usage_card.dart';
import 'widgets/pronunciation_settings_card.dart';
import 'widgets/settings_group_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool compact = context.isPadCompact;
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool isAiProvider = _isAiProvider(settings.translationProvider);
    final bool isGoogleTranslate = settings.translationProvider == 'Google 翻译';
    final bool isBaiduTranslate = settings.translationProvider == '百度翻译';
    final bool isAliyunTranslate = settings.translationProvider == '阿里云翻译';
    final AsyncValue<TtsEngineSnapshot> ttsEngines = ref.watch(
      ttsEngineSnapshotProvider,
    );
    final AsyncValue<TtsVoiceSnapshot> ttsVoices = ref.watch(
      ttsVoiceSnapshotProvider(settings.ttsEngine),
    );
    final AppUpdateState updateState = ref.watch(appUpdateProvider);
    final AsyncValue<String> appVersion = ref.watch(appVersionProvider);
    final AuthSessionState authSession = ref.watch(authSessionProvider);
    ref.listen<AppUpdateState>(appUpdateProvider, (
      AppUpdateState? previous,
      AppUpdateState next,
    ) {
      if (((previous?.isChecking ?? false) ||
              (previous?.isDownloading ?? false) ||
              (previous?.isInstalling ?? false)) &&
          !next.isChecking &&
          !next.isDownloading &&
          !next.isInstalling &&
          next.message != null) {
        _showMessage(context, next.message!);
      }
    });

    return PadScaffold(
      currentDestination: AppNavDestination.settings,
      topBar: const PadTopBar(title: '英语学习休息室', subtitle: '设置'),
      body: ListView(
        padding: EdgeInsets.all(context.padPagePadding),
        children: <Widget>[
          Text(
            '设置',
            style: TextStyle(
              fontSize: compact ? 30 : 34,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            '管理您的学习体验',
            style: TextStyle(
              fontSize: compact ? 14 : 15,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          SizedBox(height: context.padSectionGap),
          const SettingsGroupCard(
            title: '外观',
            icon: Icons.palette_rounded,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: ThemeWidget(),
              ),
            ],
          ),
          SizedBox(height: context.padSectionGap),
          SettingsGroupCard(
            title: '爱快账号',
            icon: Icons.person_rounded,
            children: <Widget>[
              _InputRow(
                title: '云端 API 地址',
                description:
                    '仅账号 / 进度 / 词库同步部署在服务器。 '
                    '留空则用编译参数 API_BASE（当前 ${settings.resolvedCloudApiBaseUrl}）。 '
                    'ASR、翻译、口语陪练等仍在 App 内运行。',
                value: settings.cloudApiBaseUrl,
                hintText: settings.resolvedCloudApiBaseUrl,
                onChanged: (String value) {
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setCloudApiBaseUrl(value);
                },
              ),
              if (authSession.isLoggedIn) ...<Widget>[
                _ActionRow(
                  title: authSession.displayName.isEmpty
                      ? authSession.email
                      : authSession.displayName,
                  description: authSession.displayName.isEmpty
                      ? '已登录，可同步学习进度与词库。'
                      : '${authSession.email}\n已登录，可同步学习进度与词库。',
                  icon: Icons.verified_user_rounded,
                  onTap: () {},
                ),
                _ActionRow(
                  title: '退出登录',
                  description: '退出后云端同步将暂停，本地学习数据仍保留。',
                  danger: true,
                  icon: Icons.logout_rounded,
                  onTap: () async {
                    await ref.read(authSessionProvider.notifier).signOut();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已退出爱快账号')),
                    );
                  },
                ),
              ] else ...<Widget>[
                _ActionRow(
                  title: '登录账号',
                  description: '登录后可同步进度、词库与学习偏好。',
                  icon: Icons.login_rounded,
                  onTap: () => context.push(SGRoute.login.route),
                ),
                _ActionRow(
                  title: '注册新账号',
                  description: '使用邮箱创建爱快英语账号。',
                  icon: Icons.person_add_alt_1_rounded,
                  onTap: () => context.push(SGRoute.register.route),
                ),
              ],
            ],
          ),
          SizedBox(height: context.padSectionGap),
          const ApiUsageCard(),
          SizedBox(height: context.padSectionGap),
          SettingsGroupCard(
            title: '课程与偏好',
            icon: Icons.tune_rounded,
            children: <Widget>[
              _ActionRow(
                title: '学习偏好 / 每日课程',
                description: '按级别与标签每日后台更新推荐课',
                icon: Icons.chevron_right_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          const LearningPreferencesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          SizedBox(height: context.padSectionGap),
          SettingsGroupCard(
            title: '播放',
            icon: Icons.play_circle_rounded,
            children: <Widget>[
              _SelectRow(
                title: '默认字幕模式',
                description: '选择默认情况下字幕的显示方式。',
                value: settings.subtitleMode,
                options: subtitleModeOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleMode(value);
                },
              ),
              _SelectRow(
                title: '英文字幕大小写',
                description: '切换已有和新字幕的显示格式；首字母大写按句首处理。',
                value: settings.subtitleLetterCase,
                options: subtitleLetterCaseOptions,
                onChanged: (String? value) {
                  if (value == null) return;
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleLetterCase(value);
                },
              ),
              _SelectRow(
                title: '默认速度',
                description: '设置新视频的默认播放速度。',
                value: settings.playbackSpeed,
                options: playbackSpeedOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setPlaybackSpeed(value);
                },
              ),
              _SelectRow(
                title: '字幕字体大小',
                description: '调整学习字幕和文字型内嵌字幕大小，也可在播放器中直接调节。',
                value: settings.fontSize,
                options: playerFontOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setFontSize(value);
                },
              ),
              _InputRow(
                title: '字幕延迟 ms',
                description: '字幕比视频快时填正数，例如 500；比视频慢时填负数。',
                value: settings.subtitleDelayMs.toString(),
                hintText: '0',
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                onChanged: (String value) {
                  final int? delayMs = int.tryParse(value.trim());
                  if (delayMs == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleDelayMs(delayMs);
                },
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: '学习',
            icon: Icons.school_outlined,
            children: <Widget>[
              _SwitchRow(
                title: '开启单词高亮',
                description: '自动高亮复杂词汇。',
                value: settings.highlightWords,
                onChanged: (bool value) {
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setHighlightWords(value: value);
                },
              ),
              _SelectRow(
                title: '单词高亮样式',
                description: '设置播放中当前字幕单词的选中效果。',
                value: settings.subtitleWordHighlightStyle,
                options: subtitleWordHighlightStyleOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleWordHighlightStyle(value);
                },
              ),
              _SubtitleWordHighlightBorderWidthRow(
                value: settings.subtitleWordHighlightBorderWidth,
                onChanged: (double value) => ref
                    .read(learningSettingsProvider.notifier)
                    .setSubtitleWordHighlightBorderWidth(value),
              ),
              _SwitchRow(
                title: '每日打卡提醒',
                description: '接收温和的提示以保持您的学习连续记录。',
                value: settings.reminder,
                onChanged: (bool value) {
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setReminder(value: value);
                },
              ),
              _TtsEngineRow(
                selectedEngine: settings.ttsEngine,
                snapshot: ttsEngines.value,
                isLoading: ttsEngines.isLoading,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setTtsEngine(value);
                },
              ),
              _TtsVoiceRow(
                selectedEngine: settings.ttsEngine,
                selectedVoice: settings.ttsVoice,
                selectedRate: settings.ttsRate,
                snapshot: ttsVoices.value,
                isLoading: ttsVoices.isLoading,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setTtsVoice(value);
                },
              ),
              _TtsRateRow(
                value: settings.ttsRate,
                onChanged: (double value) => ref
                    .read(learningSettingsProvider.notifier)
                    .setTtsRate(value),
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          if (pronunciationScoringEnabled) ...<Widget>[
            const PronunciationSettingsCard(),
            SizedBox(height: compact ? 20 : 24),
          ],
          SettingsGroupCard(
            title: '口语陪练（数字人）',
            icon: Icons.record_voice_over_rounded,
            children: <Widget>[
              _SelectRow(
                title: '陪练引擎',
                description:
                    '视频陪练管线=当前视频主题实时对话（ASR→发音→LLM→TTS→数字人）；'
                    'LiveTalking=仅数字人 WebRTC；本地 TTS=无画面。',
                value: oralCoachBackendOptions.contains(settings.oralCoachBackend)
                    ? settings.oralCoachBackend
                    : '本地 TTS',
                options: oralCoachBackendOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setOralCoachBackend(value);
                },
              ),
              if (settings.oralCoachBackend == '视频陪练管线')
                _InputRow(
                  title: '陪练管线地址',
                  description:
                      '默认已指向生产托管 https://acquireenglish.curlhairai.com/coach ；'
                      '也可改成本机 tools/oral_coach（如 http://192.168.1.8:8770）。',
                  value: settings.oralCoachPipelineUrl,
                  hintText: 'https://acquireenglish.curlhairai.com/coach',
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setOralCoachPipelineUrl(value);
                  },
                ),
              if (settings.oralCoachBackend == '视频陪练管线' ||
                  settings.oralCoachBackend == 'LiveTalking')
                _InputRow(
                  title: 'LiveTalking / 数字人地址',
                  description:
                      '虚拟外教画面（WebRTC）。管线 avatar=livetalking 时用于播报回复；'
                      '也可直连 LiveTalking。示例 http://192.168.1.8:8010',
                  value: settings.oralCoachServerUrl,
                  hintText: 'http://127.0.0.1:8010',
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setOralCoachServerUrl(value);
                  },
                ),
              _InputRow(
                title: 'LiveKit 房间地址（可选）',
                description:
                    '填入后口语 Tab 可加入全双工房间（需服务端配置 LIVEKIT_* 并运行 Agent）。'
                    '例如 wss://xxx.livekit.cloud。留空则只用 HTTP 管线。',
                value: settings.liveKitUrl,
                hintText: 'wss://…livekit…',
                onChanged: (String value) {
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setLiveKitUrl(value);
                },
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: 'Voice 本地口语（影子跟读）',
            icon: Icons.hearing_rounded,
            children: <Widget>[
              _InputRow(
                title: 'Voice 服务地址',
                description:
                    '接入开源 Zemksh/voice：电脑运行 tools/voice/run_server.sh，'
                    '手机跟读录音后可上传做本地 Whisper 转写 + 词重叠反馈。留空则关闭。',
                value: settings.voicePracticeServerUrl,
                hintText: 'http://192.168.1.8:8765',
                onChanged: (String value) {
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setVoicePracticeServerUrl(value);
                },
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: 'B 站账号',
            icon: Icons.live_tv_rounded,
            children: <Widget>[
              _ActionRow(
                title: settings.isBilibiliLoggedIn ? '扫码重新登录' : '扫码登录哔哩哔哩',
                description: settings.isBilibiliLoggedIn
                    ? (settings.bilibiliUserId.isEmpty
                          ? '已登录：可用于拉取官方字幕与缓存视频。'
                          : '已登录 UID ${settings.bilibiliUserId}：可用于拉取官方字幕与缓存视频。')
                    : settings.bilibiliCookieFromEnv
                    ? '已从 .env 加载 Cookie；也可扫码覆盖。'
                    : '推荐：手机哔哩哔哩 App 扫码，确认后自动保存登录态。',
                icon: Icons.qr_code_2_rounded,
                onTap: () async {
                  final bool ok = await showBilibiliLoginSheet(context, ref);
                  if (!context.mounted || !ok) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('B 站登录成功')),
                  );
                },
              ),
              if (settings.isBilibiliLoggedIn)
                _ActionRow(
                  title: '退出 B 站登录',
                  description: '清除后会立即要求重新扫码，才能继续使用本应用。',
                  danger: true,
                  icon: Icons.logout_rounded,
                  onTap: () {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .clearBilibiliLogin();
                  },
                ),
              if (settings.isBilibiliLoggedIn)
                _ActionRow(
                  title: '同步 B 站 Cookie 到云端',
                  description: authSession.isLoggedIn
                      ? '写入当前账号的服务器偏好（字幕 / 拉流用）。'
                      : '请先登录爱快账号，再同步到 ECS。',
                  icon: Icons.cloud_upload_rounded,
                  onTap: () async {
                    if (!authSession.isLoggedIn) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请先登录爱快账号')),
                      );
                      return;
                    }
                    final String? err = await ref
                        .read(learningSettingsProvider.notifier)
                        .syncBilibiliCookieToCloudNow();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          err == null ? '已同步 B 站 Cookie 到云端' : '同步失败：$err',
                        ),
                      ),
                    );
                  },
                ),
              _InputRow(
                title: 'SESSDATA（高级）',
                description: settings.bilibiliCookieFromEnv
                    ? '已从 apps/mobile/.env 的 BILIBILI_SESSDATA / BILIBILI_COOKIE 加载；此处可覆盖。'
                    : '也可手动粘贴 Cookie。优先使用上方扫码登录。',
                value: settings.bilibiliSessdata,
                hintText: settings.bilibiliCookieFromEnv
                    ? '（已使用 .env）'
                    : '粘贴 SESSDATA 或整段 Cookie',
                obscureText: true,
                onChanged: (String value) {
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setBilibiliSessdata(value);
                },
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: '翻译',
            icon: Icons.translate_rounded,
            children: <Widget>[
              _SelectRow(
                title: '翻译来源',
                description: '先选择翻译 API，再填写对应配置。',
                value: settings.translationProvider,
                options: translationProviderOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setTranslationProvider(value);
                },
              ),
              if (isAiProvider) ...<Widget>[
                _InputRow(
                  title: 'API Key',
                  description: '用于调用 AI 翻译接口。',
                  value: settings.translationApiKey,
                  hintText: 'YOUR_API_KEY_HERE',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiKey(value);
                  },
                ),
                _SwitchRow(
                  title: '自定义接口地址',
                  description: '关闭时使用内置厂商默认 baseUrl 和 model。',
                  value: settings.useCustomTranslationEndpoint,
                  onChanged: (bool value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setUseCustomTranslationEndpoint(value: value);
                  },
                ),
                _InputRow(
                  title: 'Base URL',
                  description: '默认已内置，可按需覆盖。',
                  value: settings.translationBaseUrl,
                  hintText: 'https://api.example.com/v1',
                  enabled: settings.useCustomTranslationEndpoint,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationBaseUrl(value);
                  },
                ),
                _ModelFetchRow(
                  isLoading: settings.isFetchingTranslationModels,
                  hasModels: settings.availableTranslationModels.isNotEmpty,
                  onTap: () async {
                    if (settings.translationApiKey.trim().isEmpty) {
                      _showMessage(context, '请先填写 API Key。');
                      return;
                    }
                    try {
                      final List<String> models = await ref
                          .read(learningSettingsProvider.notifier)
                          .fetchTranslationModels();
                      if (!context.mounted) {
                        return;
                      }
                      _showMessage(
                        context,
                        models.isEmpty
                            ? '未获取到可用模型。'
                            : '已获取 ${models.length} 个模型。',
                      );
                    } catch (_) {
                      if (!context.mounted) {
                        return;
                      }
                      _showMessage(context, '获取模型失败，请检查当前配置。');
                    }
                  },
                ),
                if (settings.availableTranslationModels.isNotEmpty)
                  _SelectRow(
                    title: '模型选择',
                    description: '从当前 provider 返回的模型列表中直接选择。',
                    value:
                        settings.availableTranslationModels.contains(
                          settings.translationModel,
                        )
                        ? settings.translationModel
                        : settings.availableTranslationModels.first,
                    options: settings.availableTranslationModels,
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }
                      ref
                          .read(learningSettingsProvider.notifier)
                          .setTranslationModel(value);
                    },
                  ),
                _InputRow(
                  title: 'Model',
                  description: '可手动输入模型名；已获取模型后也可以直接覆盖。',
                  value: settings.translationModel,
                  hintText: 'gpt-4o-mini',
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationModel(value);
                  },
                ),
              ],
              if (isGoogleTranslate)
                _InputRow(
                  title: 'API Key',
                  description: 'Google Cloud Translation API Key。',
                  value: settings.translationApiKey,
                  hintText: 'YOUR_GOOGLE_API_KEY',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiKey(value);
                  },
                ),
              if (isBaiduTranslate) ...<Widget>[
                _InputRow(
                  title: 'App ID',
                  description: '百度翻译开放平台 App ID。',
                  value: settings.translationApiKey,
                  hintText: 'YOUR_BAIDU_APP_ID',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiKey(value);
                  },
                ),
                _InputRow(
                  title: 'Secret',
                  description: '百度翻译开放平台密钥。',
                  value: settings.translationApiSecret,
                  hintText: 'YOUR_BAIDU_SECRET',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiSecret(value);
                  },
                ),
              ],
              if (isAliyunTranslate) ...<Widget>[
                _InputRow(
                  title: 'AccessKey ID',
                  description: '阿里云 AccessKey ID。',
                  value: settings.translationApiKey,
                  hintText: 'YOUR_ACCESS_KEY_ID',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiKey(value);
                  },
                ),
                _InputRow(
                  title: 'AccessKey Secret',
                  description: '阿里云 AccessKey Secret。',
                  value: settings.translationApiSecret,
                  hintText: 'YOUR_ACCESS_KEY_SECRET',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiSecret(value);
                  },
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: 'AI生成可跟读的词级同步字幕',
            icon: Icons.auto_awesome_rounded,
            children: <Widget>[
              Builder(
                builder: (BuildContext context) {
                  final bool isLocalWhisper =
                      settings.asrProvider == LocalWhisperAsr.providerName;
                  final bool isTencentAsr = settings.asrProvider == '腾讯云';
                  final bool isAlibabaAsr = settings.asrProvider == '阿里云百炼';
                  final String whisperModel =
                      localWhisperModelOptions.contains(settings.asrModel)
                      ? settings.asrModel
                      : LocalWhisperAsr.defaultModel;
                  final ({String secretId, String secretKey})
                  tencentCredential = _splitTencentCredential(
                    settings.asrApiKey,
                  );
                  return Column(
                    children: <Widget>[
                      _SwitchRow(
                        title: '生成双语字幕',
                        description: '开启后会使用“翻译”设置补齐每句中文。',
                        value: settings.generateBilingualAsrSubtitles,
                        onChanged: (bool value) {
                          ref
                              .read(learningSettingsProvider.notifier)
                              .setGenerateBilingualAsrSubtitles(value: value);
                        },
                      ),
                      _SelectRow(
                        title: 'ASR 来源',
                        description: isLocalWhisper
                            ? '设备端 Whisper.cpp，无需云端 API Key。'
                            : '独立于翻译 API，用于生成视频字幕。',
                        value: settings.asrProvider,
                        options: asrProviderOptions,
                        onChanged: (String? value) {
                          if (value == null) {
                            return;
                          }
                          ref
                              .read(learningSettingsProvider.notifier)
                              .setAsrProvider(value);
                        },
                      ),
                      if (isLocalWhisper) ...<Widget>[
                        _SelectRow(
                          title: 'Whisper 模型',
                          description:
                              '英语课推荐 base.en；弱设备用 tiny.en；small.en 更准但更大。',
                          value: whisperModel,
                          options: localWhisperModelOptions,
                          optionLabel: _whisperModelLabel,
                          onChanged: (String? value) {
                            if (value == null) {
                              return;
                            }
                            ref
                                .read(learningSettingsProvider.notifier)
                                .setAsrModel(value);
                          },
                        ),
                        _LocalWhisperModelStatusRow(modelId: whisperModel),
                      ] else ...<Widget>[
                        if (isTencentAsr) ...<Widget>[
                          _InputRow(
                            title: '腾讯云 SecretId',
                            description: '在腾讯云访问密钥页面创建。',
                            value: tencentCredential.secretId,
                            hintText: 'AKIDxxxxxxxx',
                            obscureText: true,
                            onChanged: (String value) {
                              ref
                                  .read(learningSettingsProvider.notifier)
                                  .setAsrApiKey(
                                    _joinTencentCredential(
                                      secretId: value,
                                      secretKey: tencentCredential.secretKey,
                                    ),
                                  );
                            },
                          ),
                          _InputRow(
                            title: '腾讯云 SecretKey',
                            description: '与 SecretId 配套的密钥。',
                            value: tencentCredential.secretKey,
                            hintText: 'SECRET_KEY',
                            obscureText: true,
                            onChanged: (String value) {
                              ref
                                  .read(learningSettingsProvider.notifier)
                                  .setAsrApiKey(
                                    _joinTencentCredential(
                                      secretId: tencentCredential.secretId,
                                      secretKey: value,
                                    ),
                                  );
                            },
                          ),
                        ] else
                          _InputRow(
                            title: '百炼 API Key',
                            description: settings.asrApiKeyFromEnv
                                ? '已从 apps/mobile/.env 的 BAILIAN_ASR_API_KEY 加载；此处可覆盖。'
                                : '优先写在 apps/mobile/.env（BAILIAN_ASR_API_KEY）；也可在此临时填写。',
                            value: settings.asrApiKey,
                            hintText: settings.asrApiKeyFromEnv
                                ? '（已使用 .env）'
                                : 'YOUR_ASR_API_KEY_HERE',
                            obscureText: true,
                            onChanged: (String value) {
                              ref
                                  .read(learningSettingsProvider.notifier)
                                  .setAsrApiKey(value);
                            },
                          ),
                        if (isAlibabaAsr)
                          _ActionRow(
                            title: '申请百炼 API Key',
                            description:
                                '1. 登录阿里云并开通百炼；2. 在 API Key 管理页创建；3. 复制到上方。',
                            icon: Icons.open_in_new_rounded,
                            onTap: () {
                              openUrl(
                                Uri.parse(
                                  'https://help.aliyun.com/zh/model-studio/get-api-key',
                                ),
                              );
                            },
                          ),
                        _SwitchRow(
                          title: '自定义 ASR 接口地址',
                          description: '关闭时使用内置厂商默认 baseUrl 和 model。',
                          value: settings.useCustomAsrEndpoint,
                          onChanged: (bool value) {
                            ref
                                .read(learningSettingsProvider.notifier)
                                .setUseCustomAsrEndpoint(value: value);
                          },
                        ),
                        _InputRow(
                          title: 'ASR Base URL',
                          description: '默认已内置，可按需覆盖。',
                          value: settings.asrBaseUrl,
                          hintText: 'https://api.example.com/v1',
                          enabled: settings.useCustomAsrEndpoint,
                          onChanged: (String value) {
                            ref
                                .read(learningSettingsProvider.notifier)
                                .setAsrBaseUrl(value);
                          },
                        ),
                        _InputRow(
                          title: 'ASR Model',
                          description: isTencentAsr
                              ? '腾讯英文识别使用 16k_en。'
                              : '默认使用 qwen3-asr-flash-filetrans，提供词级时间戳。',
                          value: settings.asrModel,
                          hintText: isTencentAsr
                              ? '16k_en'
                              : 'qwen3-asr-flash-filetrans',
                          onChanged: (String value) {
                            ref
                                .read(learningSettingsProvider.notifier)
                                .setAsrModel(value);
                          },
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: '系统',
            icon: Icons.settings_system_daydream_rounded,
            children: <Widget>[
              _ActionRow(
                title: updateState.downloadedPath != null
                    ? (updateState.isInstalling
                          ? '正在打开安装包…'
                          : '安装 v${updateState.update!.version}')
                    : updateState.update == null
                    ? (updateState.isChecking ? '正在检查更新…' : '检查更新')
                    : (updateState.isDownloading
                          ? _downloadTitle(updateState)
                          : '更新到 v${updateState.update!.version}'),
                description: updateState.isDownloading
                    ? _downloadDescription(updateState)
                    : updateState.downloadedPath != null
                    ? '安装包已校验完成，点击开始安装。'
                    : updateState.update == null
                    ? '从 GitHub Release 检查当前平台的最新安装包。'
                    : '已找到适用于当前平台的安装包。',
                icon: Icons.system_update_rounded,
                onTap: () => _handleUpdateAction(ref, updateState),
              ),
              _ActionRow(
                title: '管理 AI 字幕',
                description: '查看、编辑、导出、重新生成或删除已生成的字幕。',
                icon: Icons.subtitles_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiSubtitleManagementScreen(),
                  ),
                ),
              ),
              _ActionRow(
                title: '备份同步云端数据',
                description: authSession.isLoggedIn
                    ? '上传收藏生词并拉取云端进度 / 词库 / 学习偏好。'
                    : '请先登录爱快账号后再同步。',
                icon: Icons.cloud_sync_rounded,
                onTap: () async {
                  if (!authSession.isLoggedIn) {
                    _showMessage(context, '请先登录后再同步云端数据');
                    return;
                  }
                  try {
                    final int pushed = await ref
                        .read(vocabSyncServiceProvider)
                        .pushAllFavorites();
                    await ref.read(vocabSyncServiceProvider).pullAndMerge();
                    await ref
                        .read(progressSyncServiceProvider)
                        .pullIndexed();
                    await ref
                        .read(learningPreferencesProvider.notifier)
                        .pullRemote();
                    if (!context.mounted) {
                      return;
                    }
                    _showMessage(
                      context,
                      '已同步：上传 $pushed 个收藏词，并拉取云端词库与偏好',
                    );
                  } catch (error) {
                    if (!context.mounted) {
                      return;
                    }
                    _showMessage(
                      context,
                      '同步失败：${'$error'.replaceFirst('Exception: ', '')}',
                    );
                  }
                },
              ),
              _ActionRow(
                title: '清除应用缓存与生词记录',
                description: '清除所有收藏例句和缓存图片，重置应用到初始状态。',
                danger: true,
                onTap: () => _confirmReset(context, ref),
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: '支持项目',
            icon: Icons.coffee_rounded,
            children: <Widget>[
              _ActionRow(
                title: '请我喝杯咖啡',
                description: '自愿赞助，支持开源维护与改进。将在浏览器打开 Buy Me a Coffee。',
                icon: Icons.open_in_new_rounded,
                onTap: () => _openSupportPage(context),
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          Center(
            child: Text(
              appVersion.when(
                data: (String version) => '当前版本 v$version',
                loading: () => '当前版本',
                error: (_, _) => '当前版本未知',
              ),
              style: TextStyle(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSupportPage(BuildContext context) async {
    try {
      final bool opened = await openUrl(
        Uri.parse('https://buymeacoffee.com/marklongpcm'),
      );
      if (opened) return;
    } catch (_) {
      // Platform failures use the same actionable fallback as a rejected launch.
    }
    if (!context.mounted) return;
    _showMessage(context, '无法打开浏览器，请访问 buymeacoffee.com/marklongpcm');
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认清除缓存'),
          content: const Text('确定要清除缓存和重置所有学习数据吗？这会清空您的生词本。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认清除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    ref.read(learningSettingsProvider.notifier).resetToDefaults();
    _showMessage(context, '缓存清除成功，数据已重置！');
  }

  void _handleUpdateAction(WidgetRef ref, AppUpdateState state) {
    if (state.isChecking || state.isDownloading || state.isInstalling) {
      return;
    }
    if (state.downloadedPath != null) {
      ref.read(appUpdateProvider.notifier).install();
      return;
    }
    if (state.update == null) {
      ref.read(appUpdateProvider.notifier).check();
      return;
    }
    ref.read(appUpdateProvider.notifier).download();
  }

  String _downloadTitle(AppUpdateState state) {
    final double? progress = state.downloadProgress;
    return progress == null
        ? '正在下载更新…'
        : '正在下载更新 ${(progress * 100).toStringAsFixed(0)}%';
  }

  String _downloadDescription(AppUpdateState state) {
    final double downloaded = state.downloadedBytes / (1024 * 1024);
    final int? totalBytes = state.totalBytes;
    if (totalBytes == null) {
      return '已下载 ${downloaded.toStringAsFixed(1)} MB。';
    }
    final double total = totalBytes / (1024 * 1024);
    return '已下载 ${downloaded.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} MB。';
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isAiProvider(String provider) {
    return provider == 'OpenAI' ||
        provider == 'OpenRouter' ||
        provider == 'SiliconFlow' ||
        provider == 'DeepSeek';
  }
}

({String secretId, String secretKey}) _splitTencentCredential(String value) {
  final String trimmed = value.trim();
  int separator = trimmed.indexOf(':');
  if (separator < 0) {
    separator = trimmed.indexOf('：');
  }
  if (separator < 0) {
    return (secretId: trimmed, secretKey: '');
  }
  return (
    secretId: trimmed.substring(0, separator).trim(),
    secretKey: trimmed.substring(separator + 1).trim(),
  );
}

String _joinTencentCredential({
  required String secretId,
  required String secretKey,
}) {
  final String id = secretId.trim();
  final String key = secretKey.trim();
  if (id.isEmpty && key.isEmpty) {
    return '';
  }
  return '$id:$key';
}

String _whisperModelLabel(String modelId) {
  switch (modelId) {
    case 'tiny.en':
      return 'tiny.en（最快）';
    case 'base.en':
      return 'base.en（默认）';
    case 'small.en':
      return 'small.en（更准）';
    default:
      return modelId;
  }
}

class _LocalWhisperModelStatusRow extends StatefulWidget {
  const _LocalWhisperModelStatusRow({required this.modelId});

  final String modelId;

  @override
  State<_LocalWhisperModelStatusRow> createState() =>
      _LocalWhisperModelStatusRowState();
}

class _LocalWhisperModelStatusRowState
    extends State<_LocalWhisperModelStatusRow> {
  bool _ready = false;
  bool _busy = false;
  String _status = '正在检查模型…';
  double? _progress;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant _LocalWhisperModelStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = false;
      _progress = null;
      _status = '正在检查 ${widget.modelId}…';
    });
    final String modelId = widget.modelId;
    final bool ready = await LocalWhisperAsr.instance.isModelReady(modelId);
    if (!mounted || widget.modelId != modelId) {
      return;
    }
    setState(() {
      _ready = ready;
      _status = ready
          ? '$modelId 已就绪，可直接生成字幕'
          : '$modelId 未下载，首次识别时会自动下载';
    });
  }

  Future<void> _download() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _progress = null;
      _status = '正在下载 ${widget.modelId}…';
    });
    try {
      await LocalWhisperAsr.instance.ensureModel(
        widget.modelId,
        onProgress: (double? fraction, String message) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = fraction;
            _status = message;
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
        _busy = false;
        _progress = 1;
        _status = '${widget.modelId} 已就绪，可直接生成字幕';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _progress = null;
        _status = error.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = _ready
        ? '模型已下载'
        : (_busy ? '正在下载模型' : '下载 Whisper 模型');
    return Column(
      children: <Widget>[
        _ActionRow(
          title: title,
          description: _status,
          icon: _ready
              ? Icons.check_circle_outline_rounded
              : Icons.download_rounded,
          onTap: _ready || _busy ? () {} : _download,
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: LinearProgressIndicator(value: _progress),
          ),
      ],
    );
  }
}

class _ModelFetchRow extends StatelessWidget {
  const _ModelFetchRow({
    this.title = '获取模型',
    this.emptyDescription = '从当前 provider 拉取可用模型列表。',
    this.loadedDescription = '已拿到模型列表，可直接在下方选择。',
    required this.isLoading,
    required this.hasModels,
    required this.onTap,
  });

  final String title;
  final String emptyDescription;
  final String loadedDescription;
  final bool isLoading;
  final bool hasModels;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(
              title: title,
              description: hasModels ? loadedDescription : emptyDescription,
            ),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: isLoading ? null : onTap,
            child: Text(isLoading ? '获取中...' : '获取模型'),
          ),
        ],
      ),
    );
  }
}

class _TtsEngineRow extends StatelessWidget {
  const _TtsEngineRow({
    required this.selectedEngine,
    required this.snapshot,
    required this.isLoading,
    required this.onChanged,
  });

  final String selectedEngine;
  final TtsEngineSnapshot? snapshot;
  final bool isLoading;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<TtsEngineOption> engines =
        snapshot?.engines ?? const <TtsEngineOption>[];
    final bool hasSelected = engines.any(
      (TtsEngineOption engine) => engine.id == selectedEngine,
    );
    final String value = hasSelected ? selectedEngine : '';

    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(
              title: 'TTS 语音引擎',
              description: isLoading
                  ? '正在读取设备语音引擎。'
                  : '默认跟随系统；系统未设置时自动使用设备可用引擎。',
            ),
          ),
          const SizedBox(width: 16),
          _SettingsSelectShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                borderRadius: BorderRadius.circular(16),
                dropdownColor: AppDesignTokens.appWhite,
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppDesignTokens.textSecondary,
                ),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(_systemDefaultLabel(engines)),
                  ),
                  for (final TtsEngineOption engine in engines)
                    DropdownMenuItem<String>(
                      value: engine.id,
                      child: Text(
                        engine.isDefault
                            ? '${engine.label}（当前系统）'
                            : engine.label,
                      ),
                    ),
                ],
                onChanged: isLoading ? null : onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _systemDefaultLabel(List<TtsEngineOption> engines) {
    final TtsEngineOption? systemDefault = _firstOrNull(
      engines.where((TtsEngineOption engine) => engine.isDefault),
    );
    if (systemDefault != null) {
      return '系统默认（${systemDefault.label}）';
    }
    final TtsEngineOption? fallback = engines.isEmpty ? null : engines.first;
    if (fallback == null) {
      return '系统默认';
    }
    return '系统默认（未设置，自动使用 ${fallback.label}）';
  }

  TtsEngineOption? _firstOrNull(Iterable<TtsEngineOption> engines) {
    for (final TtsEngineOption engine in engines) {
      return engine;
    }
    return null;
  }
}

class _TtsVoiceRow extends ConsumerStatefulWidget {
  const _TtsVoiceRow({
    required this.selectedEngine,
    required this.selectedVoice,
    required this.selectedRate,
    required this.snapshot,
    required this.isLoading,
    required this.onChanged,
  });

  final String selectedEngine;
  final String selectedVoice;
  final double selectedRate;
  final TtsVoiceSnapshot? snapshot;
  final bool isLoading;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<_TtsVoiceRow> createState() => _TtsVoiceRowState();
}

class _TtsVoiceRowState extends ConsumerState<_TtsVoiceRow> {
  bool _previewing = false;
  int _previewVersion = 0;
  WordPronunciationService? _speech;

  @override
  void didUpdateWidget(covariant _TtsVoiceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVoice != widget.selectedVoice ||
        oldWidget.selectedEngine != widget.selectedEngine ||
        oldWidget.selectedRate != widget.selectedRate) {
      unawaited(_stopPreview());
    }
  }

  Future<void> _stopPreview() async {
    _previewVersion++;
    final WordPronunciationService? speech = _speech;
    _speech = null;
    if (mounted && _previewing) setState(() => _previewing = false);
    try {
      await speech?.stop();
    } catch (_) {
      // Cancelling a preview does not need an error message.
    }
  }

  Future<void> _preview() async {
    if (_previewing) return;
    final int version = ++_previewVersion;
    setState(() => _previewing = true);
    try {
      _speech = ref.read(wordPronunciationServiceProvider);
      await _speech!.speak('Hello! I have three projects to finish today.');
    } catch (_) {
      if (mounted && version == _previewVersion) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('试听失败，请检查设备是否已安装所选英语音色。')));
      }
    } finally {
      if (mounted && version == _previewVersion) {
        _speech = null;
        setState(() => _previewing = false);
      }
    }
  }

  @override
  void dispose() {
    _previewing = false;
    unawaited(_stopPreview());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<TtsVoiceOption> voices =
        widget.snapshot?.voices ?? const <TtsVoiceOption>[];
    final bool hasSelected = voices.any(
      (TtsVoiceOption voice) => voice.id == widget.selectedVoice,
    );
    final String value = hasSelected ? widget.selectedVoice : '';
    final Widget title = _TitleBlock(
      title: '英语朗读音色',
      description: widget.isLoading ? '正在读取当前引擎的英语音色。' : '选择后可试听，使用下方设置的朗读速度。',
    );
    final Widget dropdown = _SettingsSelectShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: AppDesignTokens.appWhite,
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppDesignTokens.textSecondary,
          ),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: '',
              child: Text('自动选择（优先高质量）'),
            ),
              for (final TtsVoiceOption voice in voices)
                DropdownMenuItem<String>(
                  value: voice.id,
                  child: Text(
                    voice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: widget.isLoading ? null : widget.onChanged,
          ),
        ),
    );
    final Widget preview = OutlinedButton.icon(
      key: const Key('tts-voice-preview'),
      onPressed: widget.isLoading
          ? null
          : _previewing
          ? _stopPreview
          : _preview,
      icon: Icon(
        _previewing ? Icons.stop_rounded : Icons.volume_up_outlined,
        size: 18,
      ),
      label: Text(_previewing ? '停止' : '试听'),
      style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
    );
    return _SettingsRowFrame(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                title,
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(child: dropdown),
                    const SizedBox(width: 8),
                    preview,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: title),
              const SizedBox(width: 16),
              SizedBox(width: 330, child: dropdown),
              const SizedBox(width: 8),
              preview,
            ],
          );
        },
      ),
    );
  }
}

class _SubtitleWordHighlightBorderWidthRow extends StatelessWidget {
  const _SubtitleWordHighlightBorderWidthRow({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static final Map<double, String> _options = <double, String>{
    1.5: '细',
    2.5: '标准',
    3.5: '粗',
  };

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          const Expanded(
            child: _TitleBlock(
              title: '单词高亮边框粗细',
              description: '调整播放中当前朗读单词的边框粗细。',
            ),
          ),
          const SizedBox(width: 16),
          _SettingsSelectShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double>(
                value: value,
                borderRadius: BorderRadius.circular(16),
                dropdownColor: AppDesignTokens.appWhite,
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppDesignTokens.textSecondary,
                ),
                items: _options.entries
                    .map(
                      (MapEntry<double, String> entry) =>
                          DropdownMenuItem<double>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                    )
                    .toList(growable: false),
                onChanged: (double? nextValue) {
                  if (nextValue != null) onChanged(nextValue);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TtsRateRow extends StatelessWidget {
  const _TtsRateRow({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const List<double> _rates = ttsRateOptions;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          const Expanded(
            child: _TitleBlock(
              title: '英语朗读速度',
              description: '只影响单词和句子朗读，不影响视频播放速度。',
            ),
          ),
          const SizedBox(width: 16),
          _SettingsSelectShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double>(
                value: value,
                borderRadius: BorderRadius.circular(16),
                dropdownColor: AppDesignTokens.appWhite,
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppDesignTokens.textSecondary,
                ),
                items: _rates
                    .map(
                      (double rate) => DropdownMenuItem<double>(
                        value: rate,
                        child: Text('$rate×'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (double? nextValue) {
                  if (nextValue != null) onChanged(nextValue);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.title,
    required this.description,
    required this.value,
    required this.hintText,
    required this.onChanged,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
  });

  final String title;
  final String description;
  final String value;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _TitleBlock(title: title, description: description),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey<int>(Object.hash(title, enabled, value.hashCode)),
            initialValue: value,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: TextStyle(color: AppDesignTokens.textPrimary),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: AppDesignTokens.textSecondary),
              filled: true,
              fillColor: enabled
                  ? (AppDesignTokens.isDark
                        ? AppDesignTokens.softGray
                        : Colors.white)
                  : AppDesignTokens.softGray,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppDesignTokens.borderGray),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppDesignTokens.borderGray),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppDesignTokens.borderGray),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.title,
    required this.description,
    required this.value,
    required this.options,
    required this.onChanged,
    this.optionLabel,
  });

  final String title;
  final String description;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String Function(String value)? optionLabel;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(title: title, description: description),
          ),
          const SizedBox(width: 16),
          _SettingsSelectShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                borderRadius: BorderRadius.circular(16),
                dropdownColor: AppDesignTokens.appWhite,
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppDesignTokens.textSecondary,
                ),
                items: options
                    .map((String item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(optionLabel?.call(item) ?? item),
                      );
                    })
                    .toList(growable: false),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(title: title, description: description),
          ),
          const SizedBox(width: 16),
          SwitchTheme(
            data: SwitchThemeData(
              trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF0F7A43);
                }
                return Colors.transparent;
              }),
              trackColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF0F7A43);
                }
                return AppDesignTokens.isDark
                    ? AppDesignTokens.softGray
                    : const Color(0xFFE4E8E4);
              }),
              thumbColor: WidgetStateProperty.all<Color>(
                AppDesignTokens.onAccent,
              ),
            ),
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.description,
    required this.onTap,
    this.danger = false,
    this.icon,
  });

  final String title;
  final String description;
  final VoidCallback onTap;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = danger
        ? const Color(0xFFC62828)
        : AppDesignTokens.textPrimary;
    final Color descColor = danger
        ? const Color(0xFFD86A6A)
        : AppDesignTokens.textSecondary;
    final Color iconColor = danger
        ? const Color(0xFFC62828)
        : AppDesignTokens.textSecondary;

    return InkWell(
      onTap: onTap,
      child: _SettingsRowFrame(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: descColor),
                  ),
                ],
              ),
            ),
            Icon(
              icon ??
                  (danger
                      ? Icons.restore_from_trash_rounded
                      : Icons.chevron_right_rounded),
              color: iconColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRowFrame extends StatelessWidget {
  const _SettingsRowFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: child,
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: TextStyle(
            fontSize: 12,
            color: AppDesignTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SettingsSelectShell extends StatelessWidget {
  const _SettingsSelectShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.isDark
            ? AppDesignTokens.softGray
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Theme(
          data: Theme.of(context).copyWith(
            canvasColor: AppDesignTokens.appWhite,
            highlightColor: AppDesignTokens.softGray,
          ),
          child: child,
        ),
      ),
    );
  }
}
