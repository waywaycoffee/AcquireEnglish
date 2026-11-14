import '../flavors/app_flavor.dart';

class Strings {
  Strings._();

  /// Prefer [FlavorConfig.appName] for locale-aware branding.
  static String get appName => FlavorConfig.appName;
  static const String appNameZh = '爱快英语';
  static const String appNameEn = 'AcquireEnglish';
  static const String appVersion = '1.0.0';
  static const String localizationsPath = 'assets/translations';
}
