class Endpoints {
  Endpoints._();

  /// Compile-time default. Override with `--dart-define=API_BASE=...`
  /// Runtime override: Settings → 爱快账号 → 云端 API 地址.
  /// Production host: Guangzhou ECS `8.163.45.100` → https://acquireenglish.curlhairai.com/
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://acquireenglish.curlhairai.com/',
  );

  /// Ensure trailing slash for Dio path joins (`api/auth/login` etc.).
  static String normalizeBaseUrl(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    }
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  static const int receiveTimeout = 15000;
  static const int connectionTimeout = 30000;

  static const String login = 'api/auth/login';
  static const String register = 'api/auth/register';
  static const String emailSend = 'api/auth/email/send';
  static const String smsSend = 'api/auth/sms/send';
  static const String smsLogin = 'api/auth/sms/login';
  static const String wechatLogin = 'api/auth/wechat/login';
  static const String me = 'api/auth/me';
  static const String courses = 'api/courses';
  static const String progress = 'api/progress';
  static const String vocab = 'api/vocab';
  static const String reviewBackup = 'api/review-backup';
  static const String readingBackup = 'api/reading-backup';
  static const String wordbookBackup = 'api/wordbook-backup';
  static const String appSettingsBackup = 'api/app-settings-backup';
  static const String syncStatus = 'api/sync/status';
  static const String phrases = 'api/phrases';
  static const String preferences = 'api/preferences';
  static const String dailyFeed = 'api/feed/daily';
  static const String creatorsFollowed = 'api/creators/followed';
  static const String creatorsFollow = 'api/creators/follow';
  static const String creatorsUnfollow = 'api/creators/unfollow';
  static const String creatorsRecommended = 'api/creators/recommended';
  static const String communityFeed = 'api/community/feed';
  static const String communityPosts = 'api/community/posts';
  static const String communityLeaderboard = 'api/community/leaderboard';
  static const String communityStudyStats = 'api/community/study-stats';
  static const String communitySimilarUsers = 'api/community/similar-users';
  static const String communityHotShares = 'api/community/hot-shares';
  static const String communityHotCreators = 'api/community/hot-creators';
  static const String communityMe = 'api/community/me';
  static const String communityPk = 'api/community/pk';
  static const String communityPkMine = 'api/community/pk/mine';
  static const String communityReclassifyRequests =
      'api/community/reclassify-requests';
  static const String communityExamAssets = 'api/community/exam-assets';
  static const String communityPacks = 'api/community/packs';
  static const String communityGroups = 'api/community/groups';
  static String communityPostTranscribe(int postId) =>
      'api/community/posts/$postId/transcribe';
  static const String writingGrade = 'api/writing/grade';
  static const String usageEvents = 'api/usage/events';
  static const String examPacks = 'api/exam/packs';
  static const String cosmeticsBalance = 'api/cosmetics/balance';
  static const String cosmeticsEarn = 'api/cosmetics/earn';
  static const String cosmeticsCatalog = 'api/cosmetics/catalog';
  static const String cosmeticsMe = 'api/cosmetics/me';
  static const String cosmeticsPurchase = 'api/cosmetics/purchase';
  static const String cosmeticsEquip = 'api/cosmetics/equip';
  static const String learningSummary = 'api/learning/summary';
  static const String health = 'api/health';
  static const String assets = 'api/assets';
  static const String assetsSkus = 'api/assets/skus';
  static const String assetsOrders = 'api/assets/orders';
  static const String assetsConsume = 'api/assets/entitlements/consume';
  static const String commerceCatalog = 'api/commerce/catalog';
  static const String commerceFreeTrialSeeds = 'api/commerce/free-trial-seeds';
  static const String commerceTrialStatus = 'api/commerce/trial/status';
  static const String commerceTrialClaimExtend = 'api/commerce/trial/claim-extend';
  static const String commercePoints = 'api/commerce/points';
  static const String commercePointsEarn = 'api/commerce/points/earn';
  static const String commercePointsSpend = 'api/commerce/points/spend';
  static String commerceModuleAccess(String code) =>
      'api/commerce/modules/$code/access';
  static const String learningTasks = 'api/learning/tasks';
  static const String learningSessions = 'api/learning/sessions';
  static const String learningSceneRecognize = 'api/learning/scene-recognize';
  static const String learningWrongItems = 'api/learning/wrong-items';
  static const String learningReviews = 'api/learning/reviews';
  static const String learningReviewsDue = 'api/learning/reviews/due';
  static const String livekitToken = 'api/livekit/token';
  static const String livekitStatus = 'api/livekit/status';
  static const String oralMatchEnqueue = 'api/oral-match/enqueue';
  static const String oralMatchStatus = 'api/oral-match/status';
  static const String oralMatchLeave = 'api/oral-match/leave';
  static const String oralMatchHeartbeat = 'api/oral-match/heartbeat';
  static String oralMatchMessages(String roomId) =>
      'api/oral-match/rooms/$roomId/messages';
  static String oralMatchReport(String roomId) =>
      'api/oral-match/rooms/$roomId/report';
  static const String sharedSubtitlesBilibili =
      'api/shared-subtitles/bilibili';
  static const String sharedSubtitlesBilibiliList =
      'api/shared-subtitles/bilibili/list';
  /// ECS durable queue for GPU ASR + translate (Bilibili shared packs).
  static const String sharedSubtitlesJobs = 'api/shared-subtitles/jobs';
  static String sharedSubtitlesJob(String jobId) =>
      'api/shared-subtitles/jobs/${Uri.encodeComponent(jobId)}';
  static const String imports = 'api/imports';
  static const String importsAsset = 'api/imports/asset';
  static const String netdiskStatus = 'api/netdisk/status';
  static const String netdiskBind = 'api/netdisk/bind';
  static const String netdiskList = 'api/netdisk/list';
  static const String netdiskImport = 'api/netdisk/import';
  static const String netdiskImportSeries = 'api/netdisk/import-series';
  static const String rewardsShare = 'api/rewards/share';
  static const String rewardsPoints = 'api/rewards/points';
  static const String foundationMediaManifest = 'api/foundation/media/manifest';
  static const String foundationMediaLookup = 'api/foundation/media/lookup';
  static const String foundationMediaUpload = 'api/foundation/media/upload';
  /// ECS-hosted A/V for any namespace (`foundation|reading|oral|course|misc`).
  static const String contentMediaManifest = 'api/content/media/manifest';
  static const String contentMediaLookup = 'api/content/media/lookup';
  static const String contentMediaUpload = 'api/content/media/upload';
  static const String syllabusCatalog = 'api/syllabus/catalog';
  static String syllabusBook(String bookId) =>
      'api/syllabus/books/${Uri.encodeComponent(bookId)}';

  /// Aliyun DashScope (Qwen Audio) TTS — voices list + speech synthesis.
  static const String readingVoices = 'api/reading/voices';
  static const String readingSpeech = 'api/reading/speech';
  static const String readingSpeechLookup = 'api/reading/speech/lookup';
  static const String pregenSentences = 'api/pregen/sentences';
  static String pregenVocab(String word) =>
      'api/pregen/vocab/${Uri.encodeComponent(word)}';
  static String pregenOralTopics(String key) =>
      'api/pregen/oral-topics/${Uri.encodeComponent(key)}';
  static const String sharedOcrBooks = 'api/shared-ocr-books';

  /// 素材指纹缓存复用（同源教材秒出课程包）。
  static const String fingerprintCacheConfig = 'api/fingerprint-cache/config';
  static const String fingerprintCacheSearch = 'api/fingerprint-cache/search';
  static const String fingerprintCacheRegister = 'api/fingerprint-cache/register';
  static const String fingerprintCacheMyCourses = 'api/fingerprint-cache/my-courses';
  static const String fingerprintCacheConfirmBind =
      'api/fingerprint-cache/confirm-bind';
  static String fingerprintCacheAsset(String assetId) =>
      'api/fingerprint-cache/assets/${Uri.encodeComponent(assetId)}';
  static String fingerprintCacheUploadTask(String taskId) =>
      'api/fingerprint-cache/upload-tasks/${Uri.encodeComponent(taskId)}';
  static String fingerprintCacheMyCourse(String courseId) =>
      'api/fingerprint-cache/my-courses/${Uri.encodeComponent(courseId)}';
  static String fingerprintCacheCourseDiff(String courseId) =>
      'api/fingerprint-cache/my-courses/${Uri.encodeComponent(courseId)}/diff';
  static String fingerprintCacheCourseLessons(String courseId) =>
      'api/fingerprint-cache/my-courses/${Uri.encodeComponent(courseId)}/lessons';
  static String fingerprintCacheCourseFinalize(String courseId) =>
      'api/fingerprint-cache/my-courses/${Uri.encodeComponent(courseId)}/finalize';
  static String fingerprintCacheCourseShare(String courseId) =>
      'api/fingerprint-cache/my-courses/${Uri.encodeComponent(courseId)}/share';

  /// Kept for Dio header compatibility; AcquireEnglish API ignores it.
  static const String apiKey = '';
}
