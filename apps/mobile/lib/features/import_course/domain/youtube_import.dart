/// YouTube URL helpers (Lingua-style paste-link flow).
class YoutubeImport {
  YoutubeImport._();

  static final RegExp _idPattern = RegExp(
    r'(?:youtu\.be/|youtube\.com/(?:watch\?v=|embed/|shorts/|live/))([A-Za-z0-9_-]{6,})',
    caseSensitive: false,
  );

  static String? extractVideoId(String raw) {
    final String input = raw.trim();
    if (input.isEmpty) {
      return null;
    }
    final RegExpMatch? match = _idPattern.firstMatch(input);
    if (match != null) {
      return match.group(1);
    }
    if (RegExp(r'^[A-Za-z0-9_-]{6,}$').hasMatch(input)) {
      return input;
    }
    return null;
  }

  static bool isYoutubeUrl(String raw) => extractVideoId(raw) != null;

  static String watchUrl(String videoId) =>
      'https://www.youtube.com/watch?v=$videoId';
}
