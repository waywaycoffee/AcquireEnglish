import 'subtitle_completion_queue.dart';

/// Progress report emitted from enqueue/worker outside Riverpod.
typedef SubtitleCompletionHubProgress =
    void Function(
      String episodeId,
      String label, {
      SubtitleCompletionStatus? status,
      bool? needEnglish,
      bool? needChinese,
    });

/// Shared-pack applied locally; catalog should adopt these paths.
typedef SubtitleCompletionHubSharedApplied =
    void Function({
      required String episodeId,
      String? enPath,
      String? zhPath,
    });

/// Process-wide notify so enqueue (outside Riverpod) can wake the UI.
class SubtitleCompletionStatusHub {
  SubtitleCompletionStatusHub._();
  static final SubtitleCompletionStatusHub instance =
      SubtitleCompletionStatusHub._();

  void Function()? _listener;
  SubtitleCompletionHubProgress? _onProgress;
  SubtitleCompletionHubSharedApplied? _onSharedApplied;

  void bind(void Function() listener) {
    _listener = listener;
  }

  void unbind(void Function() listener) {
    if (identical(_listener, listener)) {
      _listener = null;
    }
  }

  void bindProgress(SubtitleCompletionHubProgress? onProgress) {
    _onProgress = onProgress;
  }

  void bindSharedApplied(SubtitleCompletionHubSharedApplied? onSharedApplied) {
    _onSharedApplied = onSharedApplied;
  }

  void notifyChanged() {
    _listener?.call();
  }

  void reportProgress(
    String episodeId,
    String label, {
    SubtitleCompletionStatus? status,
    bool? needEnglish,
    bool? needChinese,
  }) {
    _onProgress?.call(
      episodeId,
      label,
      status: status,
      needEnglish: needEnglish,
      needChinese: needChinese,
    );
    notifyChanged();
  }

  void reportSharedApplied({
    required String episodeId,
    String? enPath,
    String? zhPath,
  }) {
    _onSharedApplied?.call(
      episodeId: episodeId,
      enPath: enPath,
      zhPath: zhPath,
    );
  }
}
