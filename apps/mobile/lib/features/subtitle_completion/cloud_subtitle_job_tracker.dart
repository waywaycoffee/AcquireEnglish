/// In-memory map of episode → ECS GPU subtitle job for UI progress polling.
class CloudSubtitleJobTrack {
  const CloudSubtitleJobTrack({
    required this.episodeId,
    required this.jobId,
    required this.bvid,
    required this.page,
    required this.needEnglish,
    required this.needChinese,
  });

  final String episodeId;
  final String jobId;
  final String bvid;
  final int page;
  final bool needEnglish;
  final bool needChinese;
}

class CloudSubtitleJobTracker {
  CloudSubtitleJobTracker._();

  static final CloudSubtitleJobTracker instance = CloudSubtitleJobTracker._();

  final Map<String, CloudSubtitleJobTrack> _byEpisode =
      <String, CloudSubtitleJobTrack>{};

  void track({
    required String episodeId,
    required String jobId,
    required String bvid,
    required int page,
    required bool needEnglish,
    required bool needChinese,
  }) {
    final String ep = episodeId.trim();
    final String id = jobId.trim();
    final String bv = bvid.trim();
    if (ep.isEmpty || bv.isEmpty) {
      return;
    }
    _byEpisode[ep] = CloudSubtitleJobTrack(
      episodeId: ep,
      jobId: id,
      bvid: bv,
      page: page < 1 ? 1 : page,
      needEnglish: needEnglish,
      needChinese: needChinese,
    );
  }

  CloudSubtitleJobTrack? forEpisode(String episodeId) =>
      _byEpisode[episodeId.trim()];

  List<CloudSubtitleJobTrack> get activeTracks =>
      _byEpisode.values.toList(growable: false);

  void clear(String episodeId) {
    _byEpisode.remove(episodeId.trim());
  }
}
