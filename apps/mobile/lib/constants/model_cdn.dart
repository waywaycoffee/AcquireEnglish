/// Official AcquireEnglish model CDN (ECS app host + public website).
///
/// Whisper weights and OCR asset packs are downloaded on first use from here,
/// with public mirrors only as fallback.
class ModelCdn {
  ModelCdn._();

  /// Primary: Guangzhou ECS behind acquireenglish.curlhairai.com
  static const String baseUrl = String.fromEnvironment(
    'MODEL_CDN_BASE',
    defaultValue: 'https://acquireenglish.curlhairai.com/models',
  );

  /// Secondary fast lane on the public product site (same files on ECS).
  static const String websiteBaseUrl = String.fromEnvironment(
    'MODEL_CDN_WEBSITE_BASE',
    defaultValue: 'https://www.curlhairai.com/models',
  );

  static const List<String> officialBases = <String>[
    baseUrl,
    websiteBaseUrl,
  ];

  static String whisperUrl(String fileName, {String? base}) =>
      '${base ?? baseUrl}/whisper/${fileName.trim()}';

  static String ocrAssetPackUrl({String? base}) =>
      '${base ?? baseUrl}/ocr/mlkit-google-ocr-models.zip';

  static List<String> whisperOfficialUrls(String fileName) => <String>[
        for (final String base in officialBases) whisperUrl(fileName, base: base),
      ];

  static List<String> get ocrOfficialUrls => <String>[
        for (final String base in officialBases) ocrAssetPackUrl(base: base),
      ];

  static bool isOfficialHost(String host) {
    final String h = host.toLowerCase();
    return h == 'acquireenglish.curlhairai.com' ||
        h == 'www.curlhairai.com' ||
        h == 'curlhairai.com' ||
        h.endsWith('.curlhairai.com');
  }
}
