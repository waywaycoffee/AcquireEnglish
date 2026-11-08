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

  static String get appName {
    switch (_flavor) {
      case AppFlavor.dev:
        return 'AcquireEnglish Dev';
      case AppFlavor.staging:
        return 'AcquireEnglish Staging';
      case AppFlavor.prod:
        return 'AcquireEnglish';
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
