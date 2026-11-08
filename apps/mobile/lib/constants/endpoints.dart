class Endpoints {
  Endpoints._();

  /// Override with `--dart-define=API_BASE=http://...`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://127.0.0.1:8001/',
  );

  static const int receiveTimeout = 15000;
  static const int connectionTimeout = 30000;

  static const String login = 'api/auth/login';
  static const String register = 'api/auth/register';
  static const String me = 'api/auth/me';
  static const String courses = 'api/courses';
  static const String progress = 'api/progress';
  static const String vocab = 'api/vocab';
  static const String preferences = 'api/preferences';
  static const String dailyFeed = 'api/feed/daily';

  /// Kept for Dio header compatibility; AcquireEnglish API ignores it.
  static const String apiKey = '';
}
