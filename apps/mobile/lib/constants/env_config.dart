/// Compile-time secrets from `--dart-define-from-file=.env`.
///
/// Prefer putting keys in `apps/mobile/.env` (see `.env.example`) instead of
/// pasting them into the in-app settings UI.
class EnvConfig {
  EnvConfig._();

  static const String _bailianAsrApiKey = String.fromEnvironment(
    'BAILIAN_ASR_API_KEY',
  );
  static const String _dashscopeApiKey = String.fromEnvironment(
    'DASHSCOPE_API_KEY',
  );
  static const String _asrApiKey = String.fromEnvironment('ASR_API_KEY');
  static const String _bilibiliSessdata = String.fromEnvironment(
    'BILIBILI_SESSDATA',
  );
  static const String _bilibiliCookie = String.fromEnvironment(
    'BILIBILI_COOKIE',
  );

  /// Alibaba Bailian / DashScope key for cloud ASR.
  static String get bailianAsrApiKey {
    for (final String value in <String>[
      _bailianAsrApiKey,
      _dashscopeApiKey,
      _asrApiKey,
    ]) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  static bool get hasBailianAsrApiKey => bailianAsrApiKey.isNotEmpty;

  /// Bilibili login SESSDATA cookie value (without the `SESSDATA=` prefix).
  ///
  /// Official CC/AI subtitle lists are empty for anonymous clients; a logged-in
  /// cookie is required to download them via `x/player/v2`.
  static String get bilibiliSessdata => _bilibiliSessdata.trim();

  /// Full Cookie header override (may include SESSDATA and other fields).
  static String get bilibiliCookie => _bilibiliCookie.trim();

  /// Ready-to-send Cookie header for Bilibili API requests.
  static String get bilibiliCookieHeader {
    final String full = bilibiliCookie;
    if (full.isNotEmpty) {
      return full;
    }
    final String sess = bilibiliSessdata;
    if (sess.isEmpty) {
      return '';
    }
    if (sess.toLowerCase().contains('sessdata=')) {
      return sess;
    }
    return 'SESSDATA=$sess';
  }

  static bool get hasBilibiliCookie => bilibiliCookieHeader.isNotEmpty;
}
