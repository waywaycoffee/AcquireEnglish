import '../../sync/data/acquire_api_client.dart';
import '../domain/reading_doc.dart';
import 'reading_ingest.dart';

/// Build local reading docs from a fingerprint asset / lessons payload.
List<ReadingDoc> readingDocsFromFingerprintAsset({
  required FingerprintCacheSearchResult result,
  required String fallbackText,
  required String fileName,
  DateTime? now,
}) {
  final DateTime created = now ?? DateTime.now();
  final String courseId = result.userCourseAssetId.isNotEmpty
      ? result.userCourseAssetId
      : (result.assetId.isNotEmpty
          ? 'fp_${result.assetId}'
          : 'fp_${created.millisecondsSinceEpoch}');
  final String courseTitle = result.assetName.trim().isNotEmpty
      ? result.assetName.trim()
      : titleFromFilename(fileName);
  final String level = '${result.asset['cefr_level'] ?? ''}'.trim();

  final List<ReadingDoc> docs = <ReadingDoc>[];
  for (int i = 0; i < result.lessons.length; i++) {
    final Map<String, dynamic> lesson = result.lessons[i];
    final String text = _lessonText(lesson);
    if (text.trim().isEmpty) continue;
    final int lessonNo =
        (lesson['lesson_no'] as num?)?.toInt() ?? (i + 1);
    final String lessonTitle = '${lesson['title'] ?? ''}'.trim().isNotEmpty
        ? '${lesson['title']}'.trim()
        : '$courseTitle · 第$lessonNo课';
    final String cefr = '${lesson['cefr'] ?? level}'.trim();
    docs.add(
      ReadingDoc(
        id: 'fp_${courseId}_l$lessonNo',
        title: lessonTitle,
        sourceType: ReadingSourceType.import,
        plainText: text,
        level: cefr,
        courseId: courseId,
        episodeId: 'lesson_$lessonNo',
        courseTitle: courseTitle,
        episodeTitle: lessonTitle,
        sourceLabel: '指纹复用',
        createdAt: created,
      ),
    );
  }

  if (docs.isNotEmpty) return docs;

  // Hit without lesson bodies: still open one doc tagged as cache reuse.
  final String plain = fallbackText.trim().isNotEmpty
      ? fallbackText
      : '${result.asset['summary_text'] ?? ''}'.trim();
  if (plain.isEmpty) return const <ReadingDoc>[];
  return <ReadingDoc>[
    ReadingDoc(
      id: 'fp_${courseId}_full',
      title: courseTitle,
      sourceType: ReadingSourceType.import,
      plainText: plain,
      level: level,
      courseId: courseId,
      episodeId: 'full',
      courseTitle: courseTitle,
      episodeTitle: courseTitle,
      sourceLabel: '指纹复用',
      createdAt: created,
    ),
  ];
}

String _lessonText(Map<String, dynamic> lesson) {
  for (final String key in <String>[
    'text_content',
    'plain_text',
    'plainText',
    'content',
    'text',
  ]) {
    final String value = '${lesson[key] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}
