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
  static const String smsSend = 'api/auth/sms/send';
  static const String smsLogin = 'api/auth/sms/login';
  static const String wechatLogin = 'api/auth/wechat/login';
  static const String me = 'api/auth/me';
  static const String courses = 'api/courses';
  static const String progress = 'api/progress';
  static const String vocab = 'api/vocab';
  static const String preferences = 'api/preferences';
  static const String dailyFeed = 'api/feed/daily';
  static const String health = 'api/health';
  static const String learningSessions = 'api/learning/sessions';
  static const String learningWrongItems = 'api/learning/wrong-items';
  static const String learningReviews = 'api/learning/reviews';
  static const String learningReviewsDue = 'api/learning/reviews/due';
  static const String livekitToken = 'api/livekit/token';
  static const String livekitStatus = 'api/livekit/status';

  /// Kept for Dio header compatibility; AcquireEnglish API ignores it.
  static const String apiKey = '';
}
