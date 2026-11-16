/// Process-wide notify so enqueue (outside Riverpod) can wake the UI.
class SubtitleCompletionStatusHub {
  SubtitleCompletionStatusHub._();
  static final SubtitleCompletionStatusHub instance =
      SubtitleCompletionStatusHub._();

  void Function()? _listener;

  void bind(void Function() listener) {
    _listener = listener;
  }

  void unbind(void Function() listener) {
    if (identical(_listener, listener)) {
      _listener = null;
    }
  }

  void notifyChanged() {
    _listener?.call();
  }
}
