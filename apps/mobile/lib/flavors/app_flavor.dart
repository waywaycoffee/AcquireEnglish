import 'dart:ui' show Locale, PlatformDispatcher;

enum AppFlavor { dev, staging, prod }

class FlavorConfig {
  static AppFlavor _flavor = AppFlavor.prod;

  static void setFlavor(AppFlavor flavor) {
    _flavor = flavor;
  }

  static AppFlavor get flavor => _flavor;

  static String get flavorName => _flavor.name;

  static bool get isDev => _flavor == AppFlavor.dev;
  static bool get isStaging => _flavor == AppFlavor.staging;
  static bool get isProd => _flavor == AppFlavor.prod;

  static bool get isChineseLocale {
    final Locale locale = PlatformDispatcher.instance.locale;
    return locale.languageCode.toLowerCase() == 'zh';
  }

  /// Launcher / UI display name. Chinese systems use 爱快英语.
  static String get appName {
    final bool zh = isChineseLocale;
    switch (_flavor) {
      case AppFlavor.dev:
        return zh ? '爱快英语 Dev' : 'AcquireEnglish Dev';
      case AppFlavor.staging:
        return zh ? '爱快英语 Staging' : 'AcquireEnglish Staging';
      case AppFlavor.prod:
        return zh ? '爱快英语' : 'AcquireEnglish';
    }
  }

  static String get bundleId {
    switch (_flavor) {
      case AppFlavor.dev:
        return 'com.acquire.english.dev';
      case AppFlavor.staging:
        return 'com.acquire.english.staging';
      case AppFlavor.prod:
        return 'com.acquire.english';
    }
  }
}
