import '../../sync/data/acquire_api_client.dart';

/// Daily-path modality tags stored in [AcquirePreferencesDto.tags].
const String kTrackVideo = 'track_video';
const String kTrackVocab = 'track_vocab';
const String kTrackReading = 'track_reading';

const List<({String id, String label, String hint})> kLearningTracks =
    <({String id, String label, String hint})>[
      (id: kTrackVideo, label: '视频学习', hint: '精听 / 跟读课程路径'),
      (id: kTrackVocab, label: '词书与收藏', hint: '统一 FSRS：收藏优先，词书补新'),
      (id: kTrackReading, label: '阅读学习', hint: '按 i+1 推文章并复习生词'),
    ];

Set<String> selectedLearningTracks(Iterable<String> tags) {
  final Set<String> selected = tags
      .where(
        (String t) =>
            t == kTrackVideo || t == kTrackVocab || t == kTrackReading,
      )
      .toSet();
  // Default: all three so existing users keep a full daily path.
  if (selected.isEmpty) {
    return <String>{kTrackVideo, kTrackVocab, kTrackReading};
  }
  return selected;
}

bool trackEnabled(AcquirePreferencesDto prefs, String trackId) =>
    selectedLearningTracks(prefs.tags).contains(trackId);

List<String> prefsTagsWithTracks({
  required List<String> keepTags,
  required Set<String> tracks,
}) {
  final List<String> next = keepTags
      .where(
        (String t) =>
            t != kTrackVideo && t != kTrackVocab && t != kTrackReading,
      )
      .toList(growable: true);
  for (final ({String id, String label, String hint}) track in kLearningTracks) {
    if (tracks.contains(track.id)) {
      next.add(track.id);
    }
  }
  return next;
}
